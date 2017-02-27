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

@interface TIPImageRenderedEntriesCollection : NSObject <TIPLRUEntry>

@property (nonatomic, readonly, copy, nonnull) NSString *identifier;

- (nonnull instancetype)initWithIdentifier:(nonnull NSString *)identifier;
- (nonnull instancetype)init NS_UNAVAILABLE;
+ (nonnull instancetype)new NS_UNAVAILABLE;

- (NSUInteger)collectionCost;
- (void)addImageEntry:(nonnull TIPImageCacheEntry *)entry;
- (nullable TIPImageCacheEntry *)imageEntryMatchingDimensions:(CGSize)size contentMode:(UIViewContentMode)mode;
- (nullable NSArray *)allEntries;

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

- (void)clearAllImages:(void (^)(void))completion
{
    if (![NSThread mainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:completion waitUntilDone:NO];
        return;
    }

    // Clear the manifest in the background to avoid main thread stalls

    TIPLRUCache *oldManifest = _manifest;
    const SInt16 totalCount = (SInt16)oldManifest.numberOfEntries;
    _manifest = [[TIPLRUCache alloc] initWithEntries:nil delegate:self];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [oldManifest clearAllEntries];
    });

    [self _tip_addByteCount:0 removeByteCount:(UInt64)self.atomicTotalCost];
    [TIPGlobalConfiguration sharedInstance].internalTotalCountForAllRenderedCaches -= totalCount;
    TIPLogInformation(@"Cleared all images in %@", self);
    if (completion) {
        completion();
    }
}

- (TIPImageCacheEntry *)imageEntryWithIdentifier:(NSString *)identifier targetDimensions:(CGSize)size targetContentMode:(UIViewContentMode)mode
{
    TIPAssert(identifier != nil);
    if (identifier != nil && [NSThread isMainThread]) {
        TIPImageRenderedEntriesCollection *collection = [_manifest entryWithIdentifier:identifier];
        return [collection imageEntryMatchingDimensions:size contentMode:mode];
    }
    return nil;
}

- (void)storeImageEntry:(TIPImageCacheEntry *)entry
{
    TIPAssert(entry != nil);
    if (!entry.completeImage || !entry.completeImageContext) {
        return;
    }

    if (entry.completeImageContext.treatAsPlaceholder) {
        // no placeholders in the rendered cache
        return;
    }

    entry = [entry copy];
    entry.partialImage = nil;
    entry.partialImageContext = nil;

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self storeImageEntry:entry];
        });
        return;
    }

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

    [collection addImageEntry:entry];
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

    TIPImageRenderedEntriesCollection *collection = [_manifest entryWithIdentifier:identifier];
    [_manifest removeEntry:collection];
}

#pragma mark Delegate

- (void)tip_cache:(nonnull TIPLRUCache *)manifest didEvictEntry:(nonnull TIPImageRenderedEntriesCollection *)entry
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

@end

@implementation TIPImageRenderedEntriesCollection
{
    NSMutableArray *_entries;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
{
    if (self = [super init]) {
        _identifier = [identifier copy];
        _entries = [NSMutableArray arrayWithCapacity:4];
    }
    return self;
}

- (void)addImageEntry:(TIPImageCacheEntry *)entry
{
    const CGSize dimensions = entry.completeImage.dimensions;
    if (dimensions.width < (CGFloat)1.0 || dimensions.height < (CGFloat)1.0) {
        return;
    }

    for (TIPImageCacheEntry *other in _entries) {
        const CGSize otherDimensions = other.completeImage.dimensions;
        if (CGSizeEqualToSize(otherDimensions, dimensions)) {
            return;
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

    [_entries insertObject:entry atIndex:0];
    if (_entries.count > 3) {
        [_entries removeLastObject];
    }
}

- (TIPImageCacheEntry *)imageEntryMatchingDimensions:(CGSize)dimensions contentMode:(UIViewContentMode)mode
{
    if (!TIPSizeGreaterThanZero(dimensions) || mode >= UIViewContentModeRedraw) {
        return nil;
    }

    NSUInteger index = NSNotFound;
    NSUInteger i = 0;
    TIPImageCacheEntry *returnValue = nil;

    for (TIPImageCacheEntry *entry in _entries) {
        if ([entry.completeImage.image tip_matchesTargetDimensions:dimensions contentMode:mode]) {
            index = i;
            returnValue = entry;
            break;
        }
        i++;
    }

    if (NSNotFound != index && returnValue) {
        if (index != 0) {
            [_entries removeObjectAtIndex:index];
            [_entries insertObject:returnValue atIndex:0];
        }
        return returnValue;
    }

    return nil;
}

- (NSArray *)allEntries
{
    return [_entries copy];
}

- (NSUInteger)collectionCost
{
    NSUInteger cost = 0;
    for (TIPImageCacheEntry *entry in _entries) {
        cost += entry.completeImage.sizeInMemory;
    }
    return cost;
}

- (nonnull NSString *)LRUEntryIdentifier
{
    return self.identifier;
}

- (BOOL)shouldAccessMoveLRUEntryToHead
{
    return YES;
}

@end
