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

NS_INLINE BOOL _StringsAreEqual(NSString * __nullable string1, NSString * __nullable string2)
{
    if (string1 == string2) {
        return YES;
    }
    if (!string1 || !string2) {
        return NO;
    }
    return [string1 isEqualToString:string2];
}

TIP_OBJC_FINAL TIP_OBJC_DIRECT_MEMBERS
@interface TIPRenderedCacheItem : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *transformerIdentifier;
@property (nonatomic, readonly) CGSize sourceImageDimensions;
@property (nonatomic, readonly, getter=isDirty) BOOL dirty;
@property (nonatomic, readonly) TIPImageCacheEntry *entry;
- (instancetype)initWithEntry:(TIPImageCacheEntry *)entry
        transformerIdentifier:(nullable NSString *)transformerIdentifier
        sourceImageDimensions:(CGSize)sourceDims;
- (void)markDirty;

// Methods for weakify (used when going into background to release images)
- (void)weakify;
- (BOOL)strongify;
@end

TIP_OBJC_FINAL TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageRenderedEntriesCollection : NSObject

@property (nonatomic, readonly, copy) NSString *identifier;

- (instancetype)initWithIdentifier:(NSString *)identifier;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (NSUInteger)collectionCost;
- (void)addImageEntry:(TIPImageCacheEntry *)entry
        transformerIdentifier:(nullable NSString *)transformerIdentifier
        sourceImageDimensions:(CGSize)sourceDims;
- (nullable TIPImageCacheEntry *)imageEntryMatchingDimensions:(CGSize)size
                                                  contentMode:(UIViewContentMode)mode
                                        transformerIdentifier:(nullable NSString *)transformerIdentifier
                                        sourceImageDimensions:(out CGSize * __nullable)sourceDimsOut
                                                        dirty:(out BOOL * __nullable)dirtyOut;
- (NSArray<TIPImageCacheEntry *> *)allEntries;
- (void)dirtyAllEntries;

// weakify pattern
- (void)weakifyEntries;
- (BOOL)strongifyEntries;

@end

@interface TIPImageRenderedEntriesCollection () <TIPLRUEntry>
@end

@interface TIPImageRenderedCache () <TIPLRUCacheDelegate>
@property (tip_atomic_direct) SInt64 atomicTotalCost;
@end

#define STRONGIFY_TEMPORARILY_IF_NEEDED() \
    const BOOL tip_macro_concat(inWeakMode__, __LINE__) = self->_weakCollections != nil; \
    if ( tip_macro_concat(inWeakMode__, __LINE__) ) { \
        [self _strongifyEntries]; \
    } \
    tip_defer(^{ \
        if ( tip_macro_concat(inWeakMode__, __LINE__) ) { \
            [self weakifyEntries]; \
        } \
    });

@implementation TIPImageRenderedCache
{
    TIPLRUCache *_manifest;
    NSMutableArray<TIPImageRenderedEntriesCollection *> *_weakCollections;
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
    tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        config.internalTotalBytesForAllRenderedCaches -= totalSize;
        config.internalTotalCountForAllRenderedCaches -= totalCount;
    });
}

- (void)clearAllImages:(nullable void (^)(void))completion
{
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd
                               withObject:completion
                            waitUntilDone:NO];
        return;
    }

    // Clear the manifest in the background to avoid main thread stalls

    @autoreleasepool {

        STRONGIFY_TEMPORARILY_IF_NEEDED();

        TIPLRUCache *oldManifest = _manifest;
        const SInt16 totalCount = (SInt16)oldManifest.numberOfEntries;
        _manifest = [[TIPLRUCache alloc] initWithEntries:nil delegate:self];
        tip_dispatch_async_autoreleasing(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            [oldManifest clearAllEntries];
        });

        [self _updateByteCountsAdded:0 removed:(UInt64)self.atomicTotalCost];
        [TIPGlobalConfiguration sharedInstance].internalTotalCountForAllRenderedCaches -= totalCount;
        TIPLogInformation(@"Cleared all images in %@", self);

    }

    if (completion) {
        completion();
    }
}

- (nullable TIPImageCacheEntry *)imageEntryWithIdentifier:(NSString *)identifier
                                    transformerIdentifier:(nullable NSString *)transformerIdentifier
                                         targetDimensions:(CGSize)size
                                        targetContentMode:(UIViewContentMode)mode
                                    sourceImageDimensions:(out CGSize * __nullable)sourceDimsOut
                                                    dirty:(out BOOL * __nullable)dirtyOut
{
    TIPAssert([NSThread isMainThread]);
    TIPAssert(identifier != nil);
    if (identifier != nil && [NSThread isMainThread]) {
        @autoreleasepool {
            [self _strongifyEntries];
            TIPImageRenderedEntriesCollection *collection = [_manifest entryWithIdentifier:identifier];
            return [collection imageEntryMatchingDimensions:size
                                                contentMode:mode
                                      transformerIdentifier:transformerIdentifier
                                      sourceImageDimensions:sourceDimsOut
                                                      dirty:dirtyOut];
        }
    }

    if (sourceDimsOut) {
        *sourceDimsOut = CGSizeZero;
    }
    if (dirtyOut) {
        *dirtyOut = NO;
    }
    return nil;
}

- (void)storeImageEntry:(TIPImageCacheEntry *)entry
  transformerIdentifier:(nullable NSString *)transformerIdentifier
  sourceImageDimensions:(CGSize)sourceDims
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
        tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            [self storeImageEntry:entry
            transformerIdentifier:transformerIdentifier
            sourceImageDimensions:sourceDims];
        });
        return;
    }

    @autoreleasepool {

        STRONGIFY_TEMPORARILY_IF_NEEDED();

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

        [collection addImageEntry:entry
            transformerIdentifier:transformerIdentifier
            sourceImageDimensions:sourceDims];
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

        [self _updateByteCountsAdded:newCost removed:oldCost];
        [globalConfig pruneAllCachesOfType:self.cacheType withPriorityCache:self];
    }
}

- (void)clearImageWithIdentifier:(NSString *)identifier
{
    TIPAssert(identifier != nil);
    if (!identifier) {
        return;
    }

    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd
                               withObject:identifier
                            waitUntilDone:NO];
        return;
    }

    @autoreleasepool {

        STRONGIFY_TEMPORARILY_IF_NEEDED();

        TIPImageRenderedEntriesCollection *collection = [_manifest entryWithIdentifier:identifier];
        [_manifest removeEntry:collection];
    }
}

- (void)dirtyImageWithIdentifier:(NSString *)identifier
{
    TIPAssert(identifier != nil);
    if (!identifier) {
        return;
    }

    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd
                               withObject:identifier
                            waitUntilDone:NO];
        return;
    }

    @autoreleasepool {

        STRONGIFY_TEMPORARILY_IF_NEEDED();

        TIPImageRenderedEntriesCollection *collection = [_manifest entryWithIdentifier:identifier];
        [collection dirtyAllEntries];
    }
}

- (void)weakifyEntries
{
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:nil waitUntilDone:NO];
        return;
    }

    @autoreleasepool {
        if (!_weakCollections) {
            _weakCollections = [[NSMutableArray alloc] initWithCapacity:_manifest.numberOfEntries];
        }
        TIPImageRenderedEntriesCollection *collection;
        while ((collection = _manifest.headEntry) != nil) {
            [_weakCollections addObject:collection];
            [_manifest removeEntry:collection]; // remove before weakifying to properly decrement cost
            [collection weakifyEntries];
        }
    }
}

#pragma mark Delegate

- (void)tip_cache:(TIPLRUCache *)manifest didEvictEntry:(TIPImageRenderedEntriesCollection *)entry
{
    [TIPGlobalConfiguration sharedInstance].internalTotalCountForAllRenderedCaches -= 1;
    [self _updateByteCountsAdded:0 removed:entry.collectionCost];
    TIPLogDebug(@"%@ Evicted '%@'", NSStringFromClass([self class]), entry.identifier);
}

#pragma mark Inspect

- (void)inspect:(TIPInspectableCacheCallback)callback
{
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd
                               withObject:callback
                            waitUntilDone:NO];
        return;
    }

    @autoreleasepool {
        NSMutableArray *inspectedEntries = [[NSMutableArray alloc] init];

        // WARNING: if in weakify mode, this will yield zero results

        for (TIPImageRenderedEntriesCollection *collection in _manifest) {
            NSArray *allEntries = [collection allEntries];
            for (TIPImageCacheEntry *cacheEntry in allEntries) {
                TIPImagePipelineInspectionResultEntry *entry;
                entry = [TIPImagePipelineInspectionResultEntry entryWithCacheEntry:cacheEntry
                                                                             class:[TIPImagePipelineInspectionResultRenderedEntry class]];
                TIPAssert(entry != nil);
                entry.bytesUsed = [entry.image tip_estimatedSizeInBytes];
#ifndef __clang_analyzer__ // reports entry can be nil; we prefer to crash if it is
                [inspectedEntries addObject:entry];
#endif
            }
        }

        callback(inspectedEntries, nil);
    }
}

#pragma mark Private

- (void)_tip_didReceiveMemoryWarning:(NSNotification *)note
{
    [self clearAllImages:NULL];
}

- (void)_updateByteCountsAdded:(UInt64)bytesAdded removed:(UInt64)bytesRemoved
{
    TIP_UPDATE_BYTES(self.atomicTotalCost, bytesAdded, bytesRemoved, @"Rendered Cache Size");
    TIP_UPDATE_BYTES([TIPGlobalConfiguration sharedInstance].internalTotalBytesForAllRenderedCaches, bytesAdded, bytesRemoved, @"All Rendered Caches Size");
}

- (void)_strongifyEntries
{
    if (!_weakCollections) {
        return;
    }

    NSArray<TIPImageRenderedEntriesCollection *> *collections = _weakCollections;
    _weakCollections = nil;
    TIPGlobalConfiguration *globalConfig = [TIPGlobalConfiguration sharedInstance];
    for (TIPImageRenderedEntriesCollection *collection in collections) {
        if ([collection strongifyEntries]) {
            [_manifest addEntry:collection];
            globalConfig.internalTotalCountForAllRenderedCaches += 1;
            [self _updateByteCountsAdded:collection.collectionCost removed:0];
        }
    }
    [globalConfig pruneAllCachesOfType:self.cacheType withPriorityCache:self];
}

@end

@implementation TIPImageRenderedEntriesCollection
{
    NSMutableArray<TIPRenderedCacheItem *> *_items;
}

@synthesize nextLRUEntry = _nextLRUEntry;
@synthesize previousLRUEntry = _previousLRUEntry;

- (instancetype)initWithIdentifier:(NSString *)identifier
{
    if (self = [super init]) {
        _identifier = [identifier copy];
        _items = [NSMutableArray arrayWithCapacity:kMaxEntriesPerRenderedCollection + 1];
        // ^ we +1 the capacity because we will overfill the array first before trimming it back down to the cap
    }
    return self;
}

- (void)addImageEntry:(TIPImageCacheEntry *)entry
transformerIdentifier:(nullable NSString *)transformerIdentifier
sourceImageDimensions:(CGSize)sourceDims
{
    const CGSize dimensions = entry.completeImage.dimensions;
    if (dimensions.width < (CGFloat)1.0 || dimensions.height < (CGFloat)1.0) {
        return;
    }

    for (NSInteger i = 0; i < (NSInteger)_items.count; i++) {
        TIPRenderedCacheItem *item = _items[(NSUInteger)i];
        const CGSize otherDimensions = item.entry.completeImage.dimensions;
        if (CGSizeEqualToSize(otherDimensions, dimensions)) {
            if (_StringsAreEqual(item.transformerIdentifier, transformerIdentifier)) {
                if (!item.isDirty && item.sourceImageDimensions.height >= sourceDims.height && item.sourceImageDimensions.width >= sourceDims.width) {
                    return; // keep existing entry
                } else {
                    // improved source image dims
                    // removal old item since it's lower fidelity
                    [_items removeObjectAtIndex:(NSUInteger)i];
                    i--;
                }
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

    [self _insertEntry:entry
 transformerIdentifier:transformerIdentifier
 sourceImageDimensions:sourceDims];
    if (_items.count > kMaxEntriesPerRenderedCollection) {
        [_items removeLastObject];
    }
    TIPAssert(_items.count <= kMaxEntriesPerRenderedCollection);
}

- (nullable TIPImageCacheEntry *)imageEntryMatchingDimensions:(CGSize)dimensions
                                                  contentMode:(UIViewContentMode)mode
                                        transformerIdentifier:(nullable NSString *)transformerIdentifier
                                        sourceImageDimensions:(out CGSize * __nullable)sourceDimsOut
                                                        dirty:(out BOOL * __nullable)dirtyOut
{
    if (!TIPSizeGreaterThanZero(dimensions) || mode >= UIViewContentModeRedraw) {
        return nil;
    }

    NSUInteger index = NSNotFound;
    NSUInteger i = 0;
    TIPImageCacheEntry *returnValue = nil;
    CGSize returnDims = CGSizeZero;
    BOOL returnDirty = NO;

    for (TIPRenderedCacheItem *item in _items) {
        TIPImageCacheEntry *entry = item.entry;
        if ([entry.completeImage.image tip_matchesTargetDimensions:dimensions contentMode:mode]) {
            if (_StringsAreEqual(item.transformerIdentifier, transformerIdentifier)) {
                index = i;
                returnValue = entry;
                returnDims = item.sourceImageDimensions;
                returnDirty = item.isDirty;
                break;
            }
        }
        i++;
    }

    if (sourceDimsOut) {
        *sourceDimsOut = returnDims;
    }
    if (dirtyOut) {
        *dirtyOut = returnDirty;
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

- (void)dirtyAllEntries
{
    for (TIPRenderedCacheItem *item in _items) {
        [item markDirty];
    }
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

- (void)weakifyEntries
{
    for (TIPRenderedCacheItem *item in _items) {
        [item weakify];
    }
}

- (BOOL)strongifyEntries
{
    BOOL anyStrongified = NO;
    NSArray<TIPRenderedCacheItem *> *items = [_items copy];
    [_items removeAllObjects];
    for (TIPRenderedCacheItem *item in items) {
        if ([item strongify]) {
            anyStrongified = YES;
            [_items addObject:item];
        }
    }
    return anyStrongified;
}

#pragma mark Private

- (void)_insertEntry:(TIPImageCacheEntry *)entry
        transformerIdentifier:(nullable NSString *)transformerIdentifier
        sourceImageDimensions:(CGSize)sourceImageDimensions
{
    TIPRenderedCacheItem *item = [[TIPRenderedCacheItem alloc] initWithEntry:entry
                                                       transformerIdentifier:transformerIdentifier
                                                       sourceImageDimensions:sourceImageDimensions];
    [_items insertObject:item atIndex:0];
}

@end

@implementation TIPRenderedCacheItem
{
    id _weakifyDescriptor;
    __weak UIImage *_weakifyImage;
}

- (instancetype)initWithEntry:(TIPImageCacheEntry *)entry
        transformerIdentifier:(nullable NSString *)transformerIdentifier
        sourceImageDimensions:(CGSize)sourceDims
{
    if (self = [super init]) {
        _entry = entry;
        _transformerIdentifier = [transformerIdentifier copy];
        _sourceImageDimensions = sourceDims;
    }
    return self;
}

- (void)markDirty
{
    _dirty = YES;
}

- (void)weakify
{
    TIPImageContainer *container = _entry.completeImage;
    TIPAssert(container != nil);
    if (container) {
        _weakifyDescriptor = container.descriptor;
        _weakifyImage = container.image;
        _entry.completeImage = nil;
    }
}

- (BOOL)strongify
{
    UIImage *image = _weakifyImage;
    id descriptor = _weakifyDescriptor;
    _weakifyDescriptor = nil;
    _weakifyImage = nil;
    if (!image) {
        return NO;
    }
    TIPImageContainer *container = [TIPImageContainer imageContainerWithImage:image
                                                                   descriptor:descriptor];
    if (!container) {
        return NO;
    }

    _entry.completeImage = container;
    return YES;
}

@end

NS_ASSUME_NONNULL_END
