//
//  TIPImageMemoryCache.m
//  TwitterImagePipeline
//
//  Created on 3/3/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import <UIKit/UIApplication.h>

#import "TIP_Project.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageCacheEntry.h"
#import "TIPImageMemoryCache.h"
#import "TIPImagePipeline+Project.h"
#import "TIPImagePipelineInspectionResult+Project.h"
#import "TIPLRUCache.h"

NS_ASSUME_NONNULL_BEGIN

@interface TIPImageMemoryCache () <TIPLRUCacheDelegate>
@property (tip_atomic_direct) SInt64 atomicTotalCost;
@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageMemoryCache (Private)

- (BOOL)_memoryCache_updateEntry:(TIPImageMemoryCacheEntry *)entry
                withPartialImage:(TIPPartialImage *)partialImage
                         context:(TIPPartialImageEntryContext *)context;
- (BOOL)_memoryCache_updateEntry:(TIPImageMemoryCacheEntry *)entry
           withCompleteImageData:(NSData *)completeImageData
                         context:(TIPCompleteImageEntryContext *)context;
- (void)_memoryCache_didEvictEntry:(TIPImageMemoryCacheEntry *)entry;
- (void)_memoryCache_inspect:(TIPInspectableCacheCallback)callback;
- (void)_memoryCache_updateByteCountsAdded:(UInt64)bytesAdded
                                   removed:(UInt64)bytesRemoved;

@end

@implementation TIPImageMemoryCache
{
    TIPGlobalConfiguration *_globalConfig;
    TIPLRUCache *_manifest;
}

@synthesize manifest = _manifest;

- (NSUInteger)totalCost
{
    return (NSUInteger)self.atomicTotalCost;
}

- (TIPImageCacheType)cacheType
{
    return TIPImageCacheTypeMemory;
}

- (instancetype)init
{
    if (self = [super init]) {
        _globalConfig = [TIPGlobalConfiguration sharedInstance];
        _manifest = [[TIPLRUCache alloc] initWithEntries:nil delegate:self];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_tip_memoryCache_didReceiveMemoryWarning:)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidReceiveMemoryWarningNotification
                                                  object:nil];

    // Remove the cache's total bytes from our global count of total bytes
    const SInt64 totalSize = self.atomicTotalCost;
    const SInt16 totalCount = (SInt16)_manifest.numberOfEntries;
    TIPGlobalConfiguration *config = _globalConfig;
    tip_dispatch_async_autoreleasing(config.queueForMemoryCaches, ^{
        config.internalTotalBytesForAllMemoryCaches -= totalSize;
        config.internalTotalCountForAllMemoryCaches -= totalCount;
    });
}

- (void)_tip_memoryCache_didReceiveMemoryWarning:(NSNotification *)note
{
    [self clearAllImages:NULL];
}

- (nullable TIPImageMemoryCacheEntry *)imageEntryForIdentifier:(NSString *)identifier
                                              targetDimensions:(CGSize)targetDimensions
                                             targetContentMode:(UIViewContentMode)targetContentMode
                                              decoderConfigMap:(nullable NSDictionary<NSString *,id> *)configMap
{
    TIPAssert(identifier != nil);
    if (!identifier) {
        return nil;
    }

    __block TIPImageMemoryCacheEntry *entry;
    tip_dispatch_sync_autoreleasing(_globalConfig.queueForMemoryCaches, ^{
        // Get entry
        entry = (TIPImageMemoryCacheEntry *)[self->_manifest entryWithIdentifier:identifier];
        if (entry) {

            // Validate TTL
            NSDate *now = [NSDate date];
            NSDate *lastAccess = nil;
            NSUInteger oldCost = entry.memoryCost;

            lastAccess = entry.partialImageContext.lastAccess;
            if (lastAccess && [now timeIntervalSinceDate:lastAccess] > entry.partialImageContext.TTL) {
                TIPAssert(entry.partialImageContext.TTL > 0.0);
                entry.partialImageContext = nil;
                entry.partialImage = nil;
            }
            lastAccess = entry.completeImageContext.lastAccess;
            if (lastAccess && [now timeIntervalSinceDate:lastAccess] > entry.completeImageContext.TTL) {
                TIPAssert(entry.completeImageContext.TTL > 0.0);
                entry.completeImageContext = nil;
                entry.completeImage = nil;
                entry.completeImageData = nil;
            }

            // Resolve changes to entry
            NSUInteger newCost = entry.memoryCost;
            if (!newCost) {
                [self->_manifest removeEntry:entry];
                entry = nil;
            } else {
                [self _memoryCache_updateByteCountsAdded:newCost
                                                 removed:oldCost];
                TIPAssert(newCost <= oldCost); // removing the cache image and/or partial image only ever removes bytes
            }

            // Retrieve the image based on target sizing
            if (entry.completeImageData != nil) {
                entry.completeImage = [TIPImageContainer imageContainerWithData:entry.completeImageData
                                                               targetDimensions:targetDimensions
                                                              targetContentMode:targetContentMode
                                                               decoderConfigMap:configMap
                                                                 codecCatalogue:nil];
            }

            // Update entry
            if (entry) {
                if (entry.partialImageContext.updateExpiryOnAccess) {
                    entry.partialImageContext.lastAccess = now;
                }
                if (entry.completeImageContext.updateExpiryOnAccess) {
                    entry.completeImageContext.lastAccess = now;
                }
            }
        }

        entry = [entry copy]; // return a copy for thread safety
    });

    return entry;
}

- (void)updateImageEntry:(TIPImageCacheEntry *)entry forciblyReplaceExisting:(BOOL)force
{
    TIPAssert(entry);
    if (!entry) {
        return;
    }

    tip_dispatch_async_autoreleasing(_globalConfig.queueForMemoryCaches, ^{
        if (![entry isValid:NO]) {
            return;
        }

        NSString *identifier = entry.identifier;
        TIPImageMemoryCacheEntry *currentEntry = (TIPImageMemoryCacheEntry *)[self->_manifest entryWithIdentifier:identifier];
        BOOL updatedCompleteImage = NO, updatedPartialImage = NO;

        if (currentEntry && !force) {
            if (entry.completeImage) {
                updatedCompleteImage = [self _memoryCache_updateEntry:currentEntry
                                                withCompleteImageData:entry.completeImageData
                                                              context:entry.completeImageContext];
            } else if (entry.partialImage) {
                updatedPartialImage = [self _memoryCache_updateEntry:currentEntry
                                                    withPartialImage:entry.partialImage
                                                             context:entry.partialImageContext];
            }
        } else {
            if (currentEntry) {
                [self->_manifest removeEntry:currentEntry];
                currentEntry = nil;
            }

            if (entry.completeImageData || entry.partialImage) {
                // extract entry
                currentEntry = [[TIPImageMemoryCacheEntry alloc] init];
                currentEntry.identifier = identifier;
                currentEntry.completeImageData = entry.completeImageData;
                currentEntry.completeImageContext = [entry.completeImageContext copy];
                currentEntry.completeImage = nil; // no image, just data
                currentEntry.partialImage = entry.partialImage;
                currentEntry.partialImageContext = [entry.partialImageContext copy];
                updatedPartialImage = updatedCompleteImage = YES;

                TIPGlobalConfiguration *globalConfig = [TIPGlobalConfiguration sharedInstance];

                // Cap our entry size
                BOOL didClear = NO;
                NSUInteger cost = currentEntry.memoryCost;
                const SInt64 max = [globalConfig internalMaxBytesForCacheEntryOfType:self.cacheType];
                if ((SInt64)cost > max && currentEntry.partialImageContext) {
                    currentEntry.partialImageContext = nil;
                    currentEntry.partialImage = nil;
                    didClear = YES;
                    cost = currentEntry.memoryCost;
                }
                if ((SInt64)cost > max && currentEntry.completeImageContext) {
                    currentEntry.completeImageContext = nil;
                    currentEntry.completeImage = nil;
                    didClear = YES;
                    cost = currentEntry.memoryCost;
                }

                if (cost > 0 || !didClear) {
                    globalConfig.internalTotalCountForAllMemoryCaches += 1;
                    [self _memoryCache_updateByteCountsAdded:cost
                                                     removed:0];

                    if (gTwitterImagePipelineAssertEnabled && 0 == cost) {
                        NSDictionary *info = @{
                                               @"dimension" : NSStringFromCGSize([currentEntry.completeImageContext ?: currentEntry.partialImageContext dimensions]),
                                               @"URL" : currentEntry.completeImageContext.URL ?: currentEntry.partialImageContext.URL,
                                               @"id" : currentEntry.identifier,
                                               };
                        TIPLogError(@"Cached zero cost image to memory cache %@", info);
                    }

                    [self->_manifest addEntry:currentEntry];
                    NSDate *now = [NSDate date];
                    currentEntry.partialImageContext.lastAccess = now;
                    currentEntry.completeImageContext.lastAccess = now;
                }
            }
        }

        if (updatedCompleteImage || updatedPartialImage) {
            [[TIPGlobalConfiguration sharedInstance] pruneAllCachesOfType:self.cacheType
                                                        withPriorityCache:self];
        }
    });
}

- (void)touchImageWithIdentifier:(NSString *)identifier
{
    TIPAssert(identifier != nil);
    if (!identifier) {
        return;
    }

    tip_dispatch_async_autoreleasing(_globalConfig.queueForMemoryCaches, ^{
        (void)[self->_manifest entryWithIdentifier:identifier];
    });
}

- (void)clearImageWithIdentifier:(NSString *)identifier
{
    TIPAssert(identifier != nil);
    if (!identifier) {
        return;
    }

    tip_dispatch_async_autoreleasing(_globalConfig.queueForMemoryCaches, ^{
        TIPImageMemoryCacheEntry *entry = (TIPImageMemoryCacheEntry *)[self->_manifest entryWithIdentifier:identifier];
        [self->_manifest removeEntry:entry];
    });
}

- (void)clearAllImages:(nullable void (^)(void))completion
{
    tip_dispatch_async_autoreleasing(_globalConfig.queueForMemoryCaches, ^{
        const SInt16 totalCount = (SInt16)self->_manifest.numberOfEntries;
        [self->_manifest clearAllEntries];
        [TIPGlobalConfiguration sharedInstance].internalTotalCountForAllMemoryCaches -= totalCount;
        [self _memoryCache_updateByteCountsAdded:0
                                         removed:(UInt64)self.atomicTotalCost];
        TIPLogInformation(@"Cleared all images in %@", self);
        if (completion) {
            completion();
        }
    });
}

#pragma mark Delegate

- (void)tip_cache:(TIPLRUCache *)manifest didEvictEntry:(TIPImageMemoryCacheEntry *)entry
{
    [TIPGlobalConfiguration sharedInstance].internalTotalCountForAllMemoryCaches -= 1;
    [self _memoryCache_updateByteCountsAdded:0 removed:entry.memoryCost];
    [self _memoryCache_didEvictEntry:entry];
}

#pragma mark Inspect

- (void)inspect:(TIPInspectableCacheCallback)callback
{
    tip_dispatch_async_autoreleasing(_globalConfig.queueForMemoryCaches, ^{
        [self _memoryCache_inspect:callback];
    });
}

@end

#pragma mark Private

@implementation TIPImageMemoryCache (Private)

- (void)_memoryCache_updateByteCountsAdded:(UInt64)bytesAdded
                                   removed:(UInt64)bytesRemoved
{
    TIP_UPDATE_BYTES(self.atomicTotalCost, bytesAdded, bytesRemoved, @"Memory Cache Size");
    TIP_UPDATE_BYTES([TIPGlobalConfiguration sharedInstance].internalTotalBytesForAllMemoryCaches, bytesAdded, bytesRemoved, @"All Memory Caches Size");
}

- (BOOL)_memoryCache_updateEntry:(TIPImageMemoryCacheEntry *)entry
                withPartialImage:(TIPPartialImage *)partialImage
                         context:(TIPPartialImageEntryContext *)context
{
    if (!partialImage || !context) {
        return NO;
    }

    if (context.treatAsPlaceholder) {
        return NO;
    }

    const CGSize newDimensions = context.dimensions;
    const CGSize oldDimensions = (entry.partialImageContext) ? entry.partialImageContext.dimensions : CGSizeZero;

    // IMPORTANT: We use "last in wins" logic.
    // It is easier for clients to detect larger varients matching smaller varients
    // than smaller variants matching larger variants.
    // This way, clients can load the smaller variant first, load the larger variant second and
    // (next time they access smaller or larger variant) the larger variant is cached.
    if ((newDimensions.width * newDimensions.height) < (oldDimensions.width * oldDimensions.height)) {
        return NO;
    }

    // Update
    const NSUInteger oldCost = entry.memoryCost;

    entry.partialImageContext = context;
    entry.partialImage = partialImage;

    const NSUInteger newCost = entry.memoryCost;
    [self _memoryCache_updateByteCountsAdded:newCost
                                     removed:oldCost];

    TIPAssert(entry.partialImage != nil);
    return YES;
}

- (BOOL)_memoryCache_updateEntry:(TIPImageMemoryCacheEntry *)entry
           withCompleteImageData:(NSData *)completeImageData
                         context:(TIPCompleteImageEntryContext *)context
{
    if (!completeImageData || !context) {
        return NO;
    }

    BOOL skipAhead = NO;
    if (entry.completeImageContext.treatAsPlaceholder != context.treatAsPlaceholder) {
        if (entry.completeImageContext.treatAsPlaceholder) {
            skipAhead = YES;
        } else if (context.treatAsPlaceholder) {
            return NO;
        }
    }

    const CGSize newDimensions = context.dimensions;
    CGSize oldDimensions = (entry.completeImageContext) ? entry.completeImageContext.dimensions : CGSizeZero;

    if (!skipAhead) {
        // IMPORTANT: We use "last in wins" logic.
        // It is easier for clients to detect larger varients matching smaller varients
        // than smaller variants matching larger variants.
        // This way, clients can load the smaller variant first, load the larger variant second and
        // (next time they access smaller or larger variant) the larger variant is cached.
        if ((newDimensions.width * newDimensions.height) < (oldDimensions.width * oldDimensions.height)) {
            return NO;
        }

        // Don't update if identical
        if (CGSizeEqualToSize(newDimensions, oldDimensions) && [entry.completeImageContext.URL isEqual:context.URL]) {
            return NO;
        }
    }

    // Update
    const NSUInteger oldCost = entry.memoryCost;

    entry.completeImageContext = context;
    entry.completeImageData = completeImageData;
    entry.completeImage = nil; // just keep the data, not the image

    if (skipAhead || entry.partialImageContext) {
        oldDimensions = entry.partialImageContext.dimensions;
        if (skipAhead || (oldDimensions.height * oldDimensions.width) <= (newDimensions.height * newDimensions.width)) {
            // latest is larger than partial
            entry.partialImageContext = nil;
            entry.partialImage = nil;
        }
    }

    const NSUInteger newCost = entry.memoryCost;
    [self _memoryCache_updateByteCountsAdded:newCost
                                     removed:oldCost];

    TIPAssert(entry.completeImageData != nil);
    return YES;
}

- (void)_memoryCache_didEvictEntry:(TIPImageMemoryCacheEntry *)entry
{
    TIPLogDebug(@"%@ Evicted '%@', complete:'%@', partial:'%@'", NSStringFromClass([self class]), entry.identifier, entry.completeImageContext.URL, entry.partialImageContext.URL);
}

- (void)_memoryCache_inspect:(TIPInspectableCacheCallback)callback
{
    NSMutableArray *completedEntries = [[NSMutableArray alloc] init];
    NSMutableArray *partialEntries = [[NSMutableArray alloc] init];

    for (TIPImageMemoryCacheEntry *cacheEntry in _manifest) {
        TIPImagePipelineInspectionResultEntry *entry;
        entry = [TIPImagePipelineInspectionResultEntry entryWithCacheEntry:cacheEntry
                                                                     class:[TIPImagePipelineInspectionResultCompleteMemoryEntry class]];
        if (entry) {
            [completedEntries addObject:entry];
        }

        entry = [TIPImagePipelineInspectionResultEntry entryWithCacheEntry:cacheEntry
                                                                     class:[TIPImagePipelineInspectionResultPartialMemoryEntry class]];
        if (entry) {
            [partialEntries addObject:entry];
        }
    }

    callback(completedEntries, partialEntries);
}

@end

NS_ASSUME_NONNULL_END
