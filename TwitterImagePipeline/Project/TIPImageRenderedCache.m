//
//  TIPImageRenderedCache.m
//  TwitterImagePipeline
//
//  Created on 4/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <UIKit/UIApplication.h>

#import "TIP_Project.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageCacheEntry.h"
#import "TIPImagePipeline+Project.h"
#import "TIPImagePipelineInspectionResult+Project.h"
#import "TIPImageRenderedCache.h"
#import "TIPLRUCache.h"
#import "UIImage+TIPAdditions.h"

NS_ASSUME_NONNULL_BEGIN

static const NSUInteger kMaxEntriesPerRenderedCollection = 3;

NS_INLINE BOOL TIPStringsAreEqual(NSString * __nullable string1, NSString * __nullable string2)
{
    if (string1 == string2) {
        return YES;
    }
    if (!string1 || !string2) {
        return NO;
    }
    return [string1 isEqualToString:string2];
}

@interface TIPRenderedCacheItem : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *transformerIdentifier;
@property (nonatomic, readonly) TIPImageCacheEntry *entry;
- (instancetype)initWithEntry:(TIPImageCacheEntry *)entry transformerIdentifier:(nullable NSString *)transformerIdentifier;
@end

@interface TIPImageRenderedEntriesCollection : NSObject <TIPLRUEntry>

@property (nonatomic, readonly, copy) NSString *identifier;

- (instancetype)initWithIdentifier:(NSString *)identifier;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (NSUInteger)collectionCost;
- (void)addImageEntry:(TIPImageCacheEntry *)entry transformerIdentifier:(nullable NSString *)transformerIdentifier;
- (nullable TIPImageCacheEntry *)imageEntryMatchingDimensions:(CGSize)size contentMode:(UIViewContentMode)mode transformerIdentifier:(nullable NSString *)transformerIdentifier;
- (NSArray<TIPImageCacheEntry *> *)allEntries;

#pragma mark TIPLRUEntry

@property (nonatomic, nullable) TIPImageRenderedEntriesCollection *nextLRUEntry;
@property (nonatomic, nullable, weak) TIPImageRenderedEntriesCollection *previousLRUEntry;

@end

@interface TIPImageRenderedCache () <TIPLRUCacheDelegate>
@property (atomic) SInt64 atomicTotalCost;
@end

@implementation TIPImageRenderedCache
{
    TIPLRUCache *_manifest;
}

@synthesize manifest = _manifest;

- (NSUInteger)totalCost
{
    return (NSUInteger)self.atomicTotalCost;
}

- (TIPImageCacheType)cacheType
{
    return TIPImageCacheTypeRendered;
}

- (instancetype)init
{
    if (self = [super init]) {
        _manifest = [[TIPLRUCache alloc] initWithEntries:nil delegate:self];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_tip_didReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];

    // Remove the cache's total bytes from our global count of total bytes
    const SInt64 totalSize = (SInt64)self.atomicTotalCost;
    const SInt16 totalCount = (SInt16)_manifest.numberOfEntries;
    TIPGlobalConfiguration *config = [TIPGlobalConfiguration sharedInstance];
    dispatch_async(dispatch_get_main_queue(), ^{
        config.internalTotalBytesForAllRenderedCaches -= totalSize;
        config.internalTotalCountForAllRenderedCaches -= totalCount;
    });
}

- (void)_tip_didReceiveMemoryWarning:(NSNotification *)note
{
    [self clearAllImages:NULL];
}

- (void)_tip_addByteCount:(UInt64)bytesAdded removeByteCount:(UInt64)bytesRemoved
{
    TIP_UPDATE_BYTES(self.atomicTotalCost, bytesAdded, bytesRemoved, @"Rendered Cache Size");
    TIP_UPDATE_BYTES([TIPGlobalConfiguration sharedInstance].internalTotalBytesForAllRenderedCaches, bytesAdded, bytesRemoved, @"All Rendered Caches Size");
}

- (void)clearAllImages:(nullable void (^)(void))completion
{
    if (![NSThread mainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:completion waitUntilDone:NO];
        return;
    }

    // Clear the manifest in the background to avoid main thread stalls

    @autoreleasepool {
        TIPLRUCache *oldManifest = _manifest;
        const SInt16 totalCount = (SInt16)oldManifest.numberOfEntries;
        _manifest = [[TIPLRUCache alloc] initWithEntries:nil delegate:self];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            @autoreleasepool {
                [oldManifest clearAllEntries];
            }
        });

        [self _tip_addByteCount:0 removeByteCount:(UInt64)self.atomicTotalCost];
        [TIPGlobalConfiguration sharedInstance].internalTotalCountForAllRenderedCaches -= totalCount;
        TIPLogInformation(@"Cleared all images in %@", self);
        if (completion) {
            completion();
        }
    }
}

- (nullable TIPImageCacheEntry *)imageEntryWithIdentifier:(NSString *)identifier transformerIdentifier:(nullable NSString *)transformerIdentifier targetDimensions:(CGSize)size targetContentMode:(UIViewContentMode)mode
{
    TIPAssert(identifier != nil);
    if (identifier != nil && [NSThread isMainThread]) {
        @autoreleasepool {
            TIPImageRenderedEntriesCollection *collection = [_manifest entryWithIdentifier:identifier];
            return [collection imageEntryMatchingDimensions:size contentMode:mode transformerIdentifier:transformerIdentifier];
        }
    }
    return nil;
}

- (void)storeImageEntry:(TIPImageCacheEntry *)entry transformerIdentifier:(nullable NSString *)transformerIdentifier
{
    TIPAssert(entry != nil);
    if (!entry.completeImage || !entry.completeImageContext) {
        return;
    }

    if (entry.completeImageContext.treatAsPlaceholder) {
        // no placeholders in the rendered cache
        return;
    }

    @autoreleasepool {
        entry = [entry copy];
        entry.partialImage = nil;
        entry.partialImageContext = nil;
    }

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self storeImageEntry:entry transformerIdentifier:transformerIdentifier];
        });
        return;
    }

    @autoreleasepool {
        TIPGlobalConfiguration *globalConfig = [TIPGlobalConfiguration sharedInstance];
        NSString *identifier = entry.identifier;
        TIPImageRenderedEntriesCollection *collection = (TIPImageRenderedEntriesCollection *)[_manifest entryWithIdentifier:identifier];
        const BOOL hasCollection = (collection != nil);
        const NSUInteger oldCost = hasCollection ? collection.collectionCost : 0;

        // Cap our entry size
        if ((SInt64)entry.completeImage.sizeInMemory > [globalConfig internalMaxBytesForCacheEntryOfType:self.cacheType]) {
            // too big, don't cache.
            return;
        }

        if (!collection) {
            collection = [[TIPImageRenderedEntriesCollection alloc] initWithIdentifier:identifier];
        }

        [collection addImageEntry:entry transformerIdentifier:transformerIdentifier];
        const NSUInteger newCost = collection.collectionCost;

        if (!newCost) {
            if (hasCollection) {
                [_manifest removeEntry:collection];
            }
        } else {
            [_manifest addEntry:collection]; // add entry or move to front
            if (!hasCollection) {
                globalConfig.internalTotalCountForAllRenderedCaches += 1;
            }
        }

        [self _tip_addByteCount:newCost removeByteCount:oldCost];
        [globalConfig pruneAllCachesOfType:self.cacheType withPriorityCache:self];
    }
}

- (void)clearImagesWithIdentifier:(NSString *)identifier
{
    TIPAssert(identifier != nil);
    if (!identifier) {
        return;
    }

    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:identifier waitUntilDone:NO];
        return;
    }

    @autoreleasepool {
        TIPImageRenderedEntriesCollection *collection = [_manifest entryWithIdentifier:identifier];
        [_manifest removeEntry:collection];
    }
}

#pragma mark Delegate

- (void)tip_cache:(TIPLRUCache *)manifest didEvictEntry:(TIPImageRenderedEntriesCollection *)entry
{
    [TIPGlobalConfiguration sharedInstance].internalTotalCountForAllRenderedCaches -= 1;
    [self _tip_addByteCount:0 removeByteCount:entry.collectionCost];
    TIPLogDebug(@"%@ Evicted '%@'", NSStringFromClass([self class]), entry.identifier);
}

#pragma mark Inspect

- (void)inspect:(TIPInspectableCacheCallback)callback
{
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:callback waitUntilDone:NO];
        return;
    }

    @autoreleasepool {
        NSMutableArray *inspectedEntries = [[NSMutableArray alloc] init];

        for (TIPImageRenderedEntriesCollection *collection in _manifest) {
            NSArray *allEntries = [collection allEntries];
            for (TIPImageCacheEntry *cacheEntry in allEntries) {
                TIPImagePipelineInspectionResultEntry *entry = [TIPImagePipelineInspectionResultEntry entryWithCacheEntry:cacheEntry class:[TIPImagePipelineInspectionResultRenderedEntry class]];
                TIPAssert(entry != nil);
                entry.bytesUsed = [entry.image tip_estimatedSizeInBytes];
                [inspectedEntries addObject:entry];
            }
        }

        callback(inspectedEntries, nil);
    }
}

@end

@implementation TIPImageRenderedEntriesCollection
{
    NSMutableArray<TIPRenderedCacheItem *> *_items;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
{
    if (self = [super init]) {
        _identifier = [identifier copy];
        _items = [NSMutableArray arrayWithCapacity:kMaxEntriesPerRenderedCollection + 1];
        // ^ we +1 the capacity because we will overfill the array first before trimming it back down to the cap
    }
    return self;
}

- (void)addImageEntry:(TIPImageCacheEntry *)entry transformerIdentifier:(nullable NSString *)transformerIdentifier
{
    const CGSize dimensions = entry.completeImage.dimensions;
    if (dimensions.width < (CGFloat)1.0 || dimensions.height < (CGFloat)1.0) {
        return;
    }

    for (TIPRenderedCacheItem *item in _items) {
        const CGSize otherDimensions = item.entry.completeImage.dimensions;
        if (CGSizeEqualToSize(otherDimensions, dimensions)) {
            if (TIPStringsAreEqual(item.transformerIdentifier, transformerIdentifier)) {
                return;
            }
        }
    }

    if (gTwitterImagePipelineAssertEnabled && 0 == entry.completeImage.sizeInMemory) {
        NSDictionary *info = @{
                               @"dimensions" : NSStringFromCGSize(entry.completeImageContext.dimensions),
                               @"URL" : entry.completeImageContext.URL,
                               @"id" : entry.identifier,
                               };
        TIPLogError(@"Cached zero cost image to rendered cache %@", info);
    }

    [self _tip_insertEntry:entry transformerIdentifier:transformerIdentifier];
    if (_items.count > kMaxEntriesPerRenderedCollection) {
        [_items removeLastObject];
    }
    TIPAssert(_items.count <= kMaxEntriesPerRenderedCollection);
}

- (nullable TIPImageCacheEntry *)imageEntryMatchingDimensions:(CGSize)dimensions contentMode:(UIViewContentMode)mode transformerIdentifier:(nullable NSString *)transformerIdentifier
{
    if (!TIPSizeGreaterThanZero(dimensions) || mode >= UIViewContentModeRedraw) {
        return nil;
    }

    NSUInteger index = NSNotFound;
    NSUInteger i = 0;
    TIPImageCacheEntry *returnValue = nil;

    for (TIPRenderedCacheItem *item in _items) {
        TIPImageCacheEntry *entry = item.entry;
        if ([entry.completeImage.image tip_matchesTargetDimensions:dimensions contentMode:mode]) {
            if (TIPStringsAreEqual(item.transformerIdentifier, transformerIdentifier)) {
                index = i;
                returnValue = entry;
                break;
            }
        }
        i++;
    }

    if (NSNotFound != index && returnValue) {
        if (index != 0) {
            // HIT, move entry to front
            TIPRenderedCacheItem *item = _items[index];
            [_items removeObjectAtIndex:index];
            [_items insertObject:item atIndex:0];
        }
        return returnValue;
    }

    return nil;
}

- (NSArray<TIPImageCacheEntry *> *)allEntries
{
    NSMutableArray<TIPImageCacheEntry *> *allEntries = [NSMutableArray arrayWithCapacity:_items.count];
    for (TIPRenderedCacheItem *item in _items) {
        [allEntries addObject:item.entry];
    }
    return [allEntries copy];
}

- (NSUInteger)collectionCost
{
    NSUInteger cost = 0;
    for (TIPRenderedCacheItem *item in _items) {
        cost += item.entry.completeImage.sizeInMemory;
    }
    return cost;
}

- (NSString *)LRUEntryIdentifier
{
    return self.identifier;
}

- (BOOL)shouldAccessMoveLRUEntryToHead
{
    return YES;
}

#pragma mark Private

- (void)_tip_insertEntry:(TIPImageCacheEntry *)entry transformerIdentifier:(nullable NSString *)transformerIdentifier
{
    TIPRenderedCacheItem *item = [[TIPRenderedCacheItem alloc] initWithEntry:entry transformerIdentifier:transformerIdentifier];
    [_items insertObject:item atIndex:0];
}

@end

@implementation TIPRenderedCacheItem

- (instancetype)initWithEntry:(TIPImageCacheEntry *)entry transformerIdentifier:(nullable NSString *)transformerIdentifier
{
    if (self = [super init]) {
        _entry = entry;
        _transformerIdentifier = [transformerIdentifier copy];
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
