//
//  TIPImageDiskCache.m
//  TwitterImagePipeline
//
//  Created on 3/3/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#include <pthread.h>

#import "NSOperationQueue+TIPSafety.h"
#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPFileUtils.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageCacheEntry.h"
#import "TIPImageDiskCache.h"
#import "TIPImageDiskCacheTemporaryFile.h"
#import "TIPImagePipelineInspectionResult+Project.h"
#import "TIPPartialImage.h"
#import "TIPTiming.h"

NS_ASSUME_NONNULL_BEGIN

static NSString * const kPartialImageExtension = @"tmp";

static NSString * const kXAttributeContextTTLKey = @"TTL";
static NSString * const kXAttributeContextUpdateTLLOnAccessKey = @"uTTL";
static NSString * const kXAttributeContextTreatAsPlaceholderKey = @"pl";
static NSString * const kXAttributeContextURLKey = @"URL";
static NSString * const kXAttributeContextLastAccessKey = @"LAD";
static NSString * const kXAttributeContextLastModifiedKey = @"LMD";
static NSString * const kXAttributeContextExpectedSizeKey = @"clen";
static NSString * const kXAttributeContextDimensionXKey = @"dX";
static NSString * const kXAttributeContextDimensionYKey = @"dY";
static NSString * const kXAttributeContextAnimated = @"ANI";

static NSDictionary<NSString *, Class> *TIPXAttributesKeysToKindsMap(void);
static NSDictionary<NSString *, Class> *TIPXAttributesKeysToKindsMap()
{
    static NSDictionary *sMap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sMap = @{
                 kXAttributeContextTTLKey : [NSNumber class],
                 kXAttributeContextUpdateTLLOnAccessKey : [NSNumber class], // BOOL
                 kXAttributeContextTreatAsPlaceholderKey : [NSNumber class], // BOOL
                 kXAttributeContextURLKey : [NSURL class],
                 kXAttributeContextLastAccessKey : [NSDate class],
                 kXAttributeContextLastModifiedKey : [NSString class],
                 kXAttributeContextExpectedSizeKey : [NSNumber class],
                 kXAttributeContextDimensionXKey : [NSNumber class],
                 kXAttributeContextDimensionYKey : [NSNumber class],
                 kXAttributeContextAnimated : [NSNumber class], // BOOL
                 };
    });
    return sMap;
}

#define kXAttributeContextKeys() [TIPXAttributesKeysToKindsMap() allKeys]

static NSDictionary * __nullable TIPXAttributesFromContext(TIPImageCacheEntryContext * __nullable context);
static TIPImageCacheEntryContext * __nullable TIPContextFromXAttributes(NSDictionary *xattrs,
                                                                        BOOL notYetComplete);
static NSOperation *TIPImageDiskCacheManifestLoadOperation(NSMutableDictionary<NSString *, TIPImageDiskCacheEntry *> *manifest, NSMutableArray<NSString *> *falseEntryPaths, NSMutableArray<TIPImageDiskCacheEntry *> *entries, unsigned long long *totalSizeInOut, NSString *path, NSString *cachePath, NSDate *timestamp, NSOperationQueue *manifestCacheQueue, NSOperation *finalCacheOperation);
static BOOL TIPUpdateImageConditionTest(const BOOL force, const BOOL oldWasPlaceholder, const BOOL newIsPlaceholder, const BOOL extraCondition, const CGSize newDimensions, const CGSize oldDimensions, NSURL * __nullable oldURL, NSURL * __nullable newURL);
static void TIPSortEntries(NSMutableArray<TIPImageDiskCacheEntry *> *entries);

NS_INLINE NSString *TIPCreateTempFilePath()
{
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
}

static NSOperationQueue *TIPImageDiskCacheManifestCacheQueue(void); // serial
static NSOperationQueue *TIPImageDiskCacheManifestIOQueue(void); // concurrent
static dispatch_queue_t TIPImageDiskCacheManifestAccessQueue(void); // serial

@interface TIPImageDiskCache () <TIPLRUCacheDelegate>
@property (atomic) SInt64 atomicTotalSize;
- (NSString *)filePathForSafeIdentifier:(NSString *)safeIdentifier;
@end

@interface TIPImageDiskCache (Background)

- (nullable NSString *)_tip_diskCache_copyImageEntryFileForUnsafeIdentifier:(NSString *)identifier error:(out NSError * __nullable * __nullable)error;
- (nullable TIPImageDiskCacheEntry *)_tip_diskCache_imageEntryForUnsafeIdentifier:(NSString *)identifier options:(TIPImageDiskCacheFetchOptions)options decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap;
- (nullable TIPImageDiskCacheEntry *)_tip_diskCache_imageEntryDirectlyFromDiskWithUnsafeIdentifier:(NSString *)identifier options:(TIPImageDiskCacheFetchOptions)options decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap;
- (nullable TIPImageDiskCacheEntry *)_tip_diskCache_imageEntryFromManifestWithUnsafeIdentifier:(NSString *)identifier options:(TIPImageDiskCacheFetchOptions)options decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap;
- (void)_tip_diskCache_updateImageEntry:(TIPImageCacheEntry *)entry forciblyReplaceExisting:(BOOL)force safeIdentifier:(NSString *)safeIdentifier;
- (BOOL)_tip_diskCache_touchImageWithSafeIdentifier:(NSString *)imageIdentifier forced:(BOOL)forced;
- (void)_tip_diskCache_finalizeTemporaryFile:(TIPImageDiskCacheTemporaryFile *)tempFile withContext:(TIPImageCacheEntryContext *)context;
- (void)_tip_diskCache_clearAllImages;
- (void)_tip_diskCache_ensureCacheDirectoryExists;
- (void)_tip_diskCache_addByteCount:(UInt64)bytesAdded removeByteCount:(UInt64)bytesRemoved;
- (BOOL)_tip_diskCache_renameImageEntryWithIdentifier:(NSString *)oldIdentifier toIdentifier:(NSString *)newIdentifier error:(NSError * __nullable * __nullable)error;

- (void)_tip_diskCache_populateCompleteImageForEntry:(TIPImageDiskCacheEntry *)entry decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap;
- (void)_tip_diskCache_populatePartialImageForEntry:(TIPImageDiskCacheEntry *)entry decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap;
- (void)_tip_diskCache_populateTemporaryFileForEntry:(TIPImageDiskCacheEntry *)entry;

- (void)_tip_diskCache_inspect:(TIPInspectableCacheCallback)callback;

@end

typedef void(^TIPImageDiskCacheManifestPopulateEntriesCompletionBlock)(unsigned long long totalSize, NSArray<TIPImageDiskCacheEntry *> * __nullable entries, NSArray<NSString *> * __nullable falseEntryPaths);

@interface TIPImageDiskCache (Manifest)
- (void)manifest_populateManifest:(NSString *)cachePath;
- (void)manifest_populateEntriesFromCachePath:(NSString *)cachePath completion:(TIPImageDiskCacheManifestPopulateEntriesCompletionBlock)completionBlock;
- (void)manifest_finalizePopulateManifest:(NSArray<TIPImageDiskCacheEntry *> *)entries totalSize:(unsigned long long)totalSize;
@end

@implementation TIPImageDiskCache
{
    TIPGlobalConfiguration *_globalConfig;
    dispatch_queue_t _manifestQueue;

    UInt64 _earlyRemovedBytesSize;
    TIPLRUCache *_manifest;
    pthread_mutex_t _manifestMutex;
    struct {
        BOOL manifestIsLoading:1;
    } _diskCache_flags;
}

- (TIPLRUCache *)manifest
{
    __block TIPLRUCache *manifest = nil;

    // Perform a thread safe double-NULL check.
    // This should keep perf up for the common case
    // with a slowdown in the rare case of accessing
    // manifest while it is still loading.

    // 1) thread safe get the manfiest
    dispatch_sync(_manifestQueue, ^{
        manifest = self->_manifest;
    });

    // nil manifest?
    if (!manifest) {

        // 2) thread safe wait until the loading completes via mutex
        //
        // This mutex will be locked by manifest loading which is
        // kicked of at "init" time and always ends with the mutex
        // being unlocked.
        // Performing a lock/unlock here ensures we wait for the manifest
        // before continuing
        pthread_mutex_lock(&_manifestMutex);
        pthread_mutex_unlock(&_manifestMutex);

        // 3) loading completed, thread safe get the non-nil manifest
        //    (unless there was an error, then we'll have an invalid disk cache w/ nil manifest)
        dispatch_sync(_manifestQueue, ^{
            manifest = self->_manifest;
        });
    }

    TIPAssert(manifest != nil);
    return manifest;
}

- (NSUInteger)totalCost
{
    return (NSUInteger)self.atomicTotalSize;
}

- (TIPImageCacheType)cacheType
{
    return TIPImageCacheTypeDisk;
}

- (instancetype)initWithPath:(NSString *)cachePath
{
    if (self = [super init]) {
        TIPAssert(cachePath != nil);
        _cachePath = [cachePath copy];
        _globalConfig = [TIPGlobalConfiguration sharedInstance];
        _manifestQueue = TIPImageDiskCacheManifestAccessQueue();
        _diskCache_flags.manifestIsLoading = YES;
        pthread_mutex_init(&_manifestMutex, NULL);
        pthread_mutex_lock(&_manifestMutex);

        cachePath = _cachePath; // reassign local var to immutable ivar for async usage
        tip_dispatch_async_autoreleasing(_manifestQueue, ^{
            [self manifest_populateManifest:cachePath];
        });
    }
    return self;
}

- (void)dealloc
{
    pthread_mutex_destroy(&_manifestMutex);

    // Don't delete the on disk cache, but do remove the cache's total bytes from our global count of total bytes
    const SInt64 totalSize = self.atomicTotalSize;
    const SInt16 totalCount = (SInt16)_manifest.numberOfEntries;
    TIPGlobalConfiguration *config = _globalConfig;
    dispatch_async(config.queueForDiskCaches, ^{
        config.internalTotalBytesForAllDiskCaches -= totalSize;
        config.internalTotalCountForAllDiskCaches -= totalCount;
    });
}

- (BOOL)renameImageEntryWithIdentifier:(NSString *)oldIdentifier toIdentifier:(NSString *)newIdentifier error:(NSError * __nullable * __nullable)error
{
    __block BOOL success = NO;
    __block NSError *outerError;
    tip_dispatch_sync_autoreleasing(_globalConfig.queueForDiskCaches, ^{
        NSError *innerError;
        success = [self _tip_diskCache_renameImageEntryWithIdentifier:oldIdentifier toIdentifier:newIdentifier error:&innerError];
        outerError = innerError;
    });
    if (error) {
        *error = outerError;
    }
    return success;
}

- (nullable NSString *)copyImageEntryFileForIdentifier:(NSString *)identifier error:(out NSError * __autoreleasing __nullable * __nullable)error
{
    TIPAssert(identifier != nil);
    if (!identifier) {
        return nil;
    }

    __block NSError *outerError;
    __block NSString *tempFilePath;
    tip_dispatch_sync_autoreleasing(_globalConfig.queueForDiskCaches, ^{
        NSError *innerError;
        tempFilePath = [self _tip_diskCache_copyImageEntryFileForUnsafeIdentifier:identifier error:&innerError];
        outerError = innerError;
    });
    if (error) {
        *error = outerError;
    }

    return tempFilePath;
}

- (nullable TIPImageDiskCacheEntry *)imageEntryForIdentifier:(NSString *)identifier options:(TIPImageDiskCacheFetchOptions)options decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
{
    if (!identifier) {
        return nil;
    }

    __block TIPImageDiskCacheEntry *entry;
    tip_dispatch_sync_autoreleasing(_globalConfig.queueForDiskCaches, ^{
        entry = [self _tip_diskCache_imageEntryForUnsafeIdentifier:identifier options:options decoderConfigMap:decoderConfigMap];
    });
    return entry;
}

- (void)updateImageEntry:(TIPImageCacheEntry *)entry forciblyReplaceExisting:(BOOL)force
{
    TIPAssert(entry.identifier != nil);
    if (!entry.identifier) {
        return;
    }

    tip_dispatch_async_autoreleasing(_globalConfig.queueForDiskCaches, ^{
        [self _tip_diskCache_updateImageEntry:entry forciblyReplaceExisting:force safeIdentifier:TIPSafeFromRaw(entry.identifier)];
    });
}

- (void)clearImageWithIdentifier:(NSString *)identifier
{
    if (!identifier) {
        return;
    }

    tip_dispatch_async_autoreleasing(_globalConfig.queueForDiskCaches, ^{
        TIPLRUCache *manifest = [self diskCache_syncAccessManifest];
        TIPImageDiskCacheEntry *entry = (TIPImageDiskCacheEntry *)[manifest entryWithIdentifier:TIPSafeFromRaw(identifier)];
        [manifest removeEntry:entry];
    });
}

- (void)clearAllImages:(nullable void (^)(void))completion
{
    tip_dispatch_async_autoreleasing(_globalConfig.queueForDiskCaches, ^{
        [self _tip_diskCache_clearAllImages];
        if (completion) {
            completion();
        }
    });
}

- (void)prune
{
    tip_dispatch_async_autoreleasing(_globalConfig.queueForDiskCaches, ^{
        [self->_globalConfig pruneAllCachesOfType:self.cacheType withPriorityCache:nil];
    });
}

- (void)touchImageWithIdentifier:(NSString *)imageIdentifier orSaveImageEntry:(nullable TIPImageDiskCacheEntry *)entry
{
    if (entry) {
        TIPAssert(entry && [imageIdentifier isEqualToString:entry.identifier]);
        if (![imageIdentifier isEqualToString:entry.identifier]) {
            return;
        }
    } else {
        TIPAssert(!entry && imageIdentifier != nil);
        if (!imageIdentifier) {
            return;
        }
    }

    tip_dispatch_async_autoreleasing(_globalConfig.queueForDiskCaches, ^{
        NSString *safeIdentifier = TIPSafeFromRaw(imageIdentifier);
        if (![self _tip_diskCache_touchImageWithSafeIdentifier:safeIdentifier forced:NO] && entry) {
            [self _tip_diskCache_updateImageEntry:entry forciblyReplaceExisting:NO safeIdentifier:safeIdentifier];
        }
    });
}

- (TIPImageDiskCacheTemporaryFile *)openTemporaryFileForImageIdentifier:(NSString *)imageIdentifier
{
    TIPAssert(imageIdentifier != nil);
    if (!imageIdentifier) {
        return nil;
    }

    TIPImageDiskCacheTemporaryFile *tempFile = [[TIPImageDiskCacheTemporaryFile alloc] initWithIdentifier:imageIdentifier temporaryPath:TIPCreateTempFilePath() finalPath:[self filePathForSafeIdentifier:TIPSafeFromRaw(imageIdentifier)] diskCache:self];
    return tempFile;
}

- (void)finalizeTemporaryFile:(TIPImageDiskCacheTemporaryFile *)tempFile withContext:(TIPImageCacheEntryContext *)context
{
    TIPAssert(tempFile.imageIdentifier != nil);
    if (!tempFile.imageIdentifier) {
        return;
    }

    tip_dispatch_async_autoreleasing(_globalConfig.queueForDiskCaches, ^{
        [self _tip_diskCache_finalizeTemporaryFile:tempFile withContext:context];
    });
}

- (void)clearTemporaryFilePath:(NSString *)filePath
{
    if (!filePath) {
        return;
    }

    tip_dispatch_async_autoreleasing(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL];
    });
}

- (NSString *)filePathForSafeIdentifier:(NSString *)safeIdentifier
{
    TIPAssert(safeIdentifier != nil);
    if (!safeIdentifier) {
        return nil;
    }

    TIPAssert(_cachePath != nil);
    return [_cachePath stringByAppendingPathComponent:safeIdentifier];
}

#pragma mark TIPLRUCacheDelegate

- (void)tip_cache:(TIPLRUCache *)manifest didEvictEntry:(TIPImageDiskCacheEntry *)entry
{
    const NSUInteger size = entry.completeFileSize + entry.partialFileSize;
    _globalConfig.internalTotalCountForAllDiskCaches -= 1;
    [self _tip_diskCache_addByteCount:0 removeByteCount:size];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *filePath = [self filePathForSafeIdentifier:entry.safeIdentifier];
    NSString *partialFilePath = [filePath stringByAppendingPathExtension:kPartialImageExtension];
    [fm removeItemAtPath:filePath error:NULL];
    [fm removeItemAtPath:partialFilePath error:NULL];

    TIPLogDebug(@"%@ Evicted '%@', complete:'%@', partial:'%@'", NSStringFromClass([self class]), entry.safeIdentifier, entry.completeImageContext.URL, entry.partialImageContext.URL);
}

#pragma mark Inspect

- (void)inspect:(TIPInspectableCacheCallback)callback
{
    tip_dispatch_async_autoreleasing(_globalConfig.queueForDiskCaches, ^{
        [self _tip_diskCache_inspect:callback];
    });
}

@end

@implementation TIPImageDiskCache (Background)

- (void)_tip_diskCache_addByteCount:(UInt64)bytesAdded removeByteCount:(UInt64)bytesRemoved
{
    // are we decrementing our byte count before the manifest has finished loading?
    if (bytesRemoved > bytesAdded && _diskCache_flags.manifestIsLoading) {

        // this would cause the manifest to become negative
        // instead, delay the decrement until later and just deal with the increment

        _earlyRemovedBytesSize += bytesRemoved;

        TIPLogWarning(@"Decrementing disk cache size before the Manifest finished loading!  It's OK though, we'll delay the subtracting until later.  Added: %llu, Sub'd: %llu", bytesAdded, bytesRemoved);

        bytesRemoved = 0;
    }

    TIP_UPDATE_BYTES(self.atomicTotalSize, bytesAdded, bytesRemoved, @"Disk Cache Size");
    TIP_UPDATE_BYTES(_globalConfig.internalTotalBytesForAllDiskCaches, bytesAdded, bytesRemoved, @"All Disk Caches Size");
}

- (void)_tip_diskCache_ensureCacheDirectoryExists
{
    [[NSFileManager defaultManager] createDirectoryAtPath:_cachePath withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (nullable NSString *)_tip_diskCache_copyImageEntryFileForUnsafeIdentifier:(NSString *)identifier error:(out NSError * __autoreleasing __nullable * __nullable)error
{
    NSString *temporaryFilePath = nil;
    NSError *fileCopyError = nil;
    NSString *filePath = [self diskCache_imageEntryFilePathForIdentifier:identifier hitShouldMoveEntryToHead:YES context:NULL];

    if (filePath) {
        NSFileManager *fm = [NSFileManager defaultManager];
        temporaryFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        [fm createDirectoryAtPath:temporaryFilePath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:NULL error:NULL];
        if (![fm copyItemAtPath:filePath toPath:temporaryFilePath error:&fileCopyError]) {
            temporaryFilePath = nil;
        }
    }

    if (!temporaryFilePath && !fileCopyError) {
        fileCopyError = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil];
    }

    if (error) {
        *error = fileCopyError;
    }
    return temporaryFilePath;
}

- (nullable NSString *)diskCache_imageEntryFilePathForIdentifier:(NSString *)identifier hitShouldMoveEntryToHead:(BOOL)hitToHead context:(out TIPImageCacheEntryContext * __autoreleasing __nullable * __nullable)contextOut
{
    TIPCompleteImageEntryContext *context = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *safeIdentifer = TIPSafeFromRaw(identifier);
    NSString *filePath = [self filePathForSafeIdentifier:safeIdentifer];

    if (_diskCache_flags.manifestIsLoading) {
        if ([fm fileExistsAtPath:filePath]) {
            const NSUInteger size = TIPFileSizeAtPath(filePath, NULL);
            if (size) {
                context = (id)TIPContextFromXAttributes(TIPGetXAttributesForFile(filePath, TIPXAttributesKeysToKindsMap()), NO);
                if (![context isKindOfClass:[TIPCompleteImageEntryContext class]]) {
                    context = nil;
                }
            }
        }
    } else {
        TIPImageCacheEntry *entry = (TIPImageCacheEntry *)[_manifest entryWithIdentifier:safeIdentifer canMutate:hitToHead];
        context = [entry.completeImageContext copy];
    }

    if (!context) {
        filePath = nil;
    }

    if (contextOut) {
        *contextOut = context;
    }
    return filePath;
}

- (nullable TIPImageDiskCacheEntry *)_tip_diskCache_imageEntryForUnsafeIdentifier:(NSString *)identifier options:(TIPImageDiskCacheFetchOptions)options decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
{
    TIPImageDiskCacheEntry *entry = nil;
    if (_diskCache_flags.manifestIsLoading) {
        entry = [self _tip_diskCache_imageEntryDirectlyFromDiskWithUnsafeIdentifier:identifier options:options decoderConfigMap:decoderConfigMap];
    } else {
        entry = [self _tip_diskCache_imageEntryFromManifestWithUnsafeIdentifier:identifier options:options decoderConfigMap:decoderConfigMap];
    }

    return entry;
}

- (nullable TIPImageDiskCacheEntry *)diskCache_imageEntryForIdentifier:(NSString *)identifier options:(TIPImageDiskCacheFetchOptions)options decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
{
    return [self _tip_diskCache_imageEntryForUnsafeIdentifier:identifier options:options decoderConfigMap:decoderConfigMap];
}

- (nullable TIPImageDiskCacheEntry *)_tip_diskCache_imageEntryDirectlyFromDiskWithUnsafeIdentifier:(NSString *)identifier options:(TIPImageDiskCacheFetchOptions)options decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
{
    TIPImageDiskCacheEntry *entry = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *safeIdentifer = TIPSafeFromRaw(identifier);
    NSString *filePath = [self filePathForSafeIdentifier:safeIdentifer];
    if ([fm fileExistsAtPath:filePath]) {
        const NSUInteger size = TIPFileSizeAtPath(filePath, NULL);
        if (size) {
            TIPImageCacheEntryContext *context = TIPContextFromXAttributes(TIPGetXAttributesForFile(filePath, TIPXAttributesKeysToKindsMap()), NO);
            if ([context isKindOfClass:[TIPCompleteImageEntryContext class]]) {
                entry = [[TIPImageDiskCacheEntry alloc] init];
                entry.identifier = identifier;
                entry.completeImageContext = (id)context;
                entry.completeFileSize = size;
                if (TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageDiskCacheFetchOptionCompleteImage)) {
                    TIPImageContainer *image = [TIPImageContainer imageContainerWithFilePath:filePath decoderConfigMap:decoderConfigMap codecCatalogue:nil memoryMap:context.isAnimated];
                    if (image) {
                        entry.completeImage = image;
                    } else {
                        entry = nil;
                    }
                }
            }
        }
    }
    return entry;
}

- (nullable TIPImageDiskCacheEntry *)_tip_diskCache_imageEntryFromManifestWithUnsafeIdentifier:(NSString *)identifier options:(TIPImageDiskCacheFetchOptions)options decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
{
    TIPLRUCache *manifest = [self diskCache_syncAccessManifest];
    NSString *safeIdentifer = TIPSafeFromRaw(identifier);
    TIPImageDiskCacheEntry *entry = (TIPImageDiskCacheEntry *)[manifest entryWithIdentifier:safeIdentifer];
    if (entry) {
        // Validate TTL
        NSDate *now = [NSDate date];
        NSDate *lastAccess = nil;
        const NSUInteger oldCost = entry.completeFileSize + entry.partialFileSize;

        lastAccess = entry.partialImageContext.lastAccess;
        if (lastAccess && [now timeIntervalSinceDate:lastAccess] > entry.partialImageContext.TTL) {
            entry.partialImageContext = nil;
            entry.partialImage = nil;
            entry.partialFileSize = 0;
        }
        lastAccess = entry.completeImageContext.lastAccess;
        if (lastAccess && [now timeIntervalSinceDate:lastAccess] > entry.completeImageContext.TTL) {
            entry.completeImageContext = nil;
            entry.completeImage = nil;
            entry.completeFileSize = 0;
        }

        // Resolve changes to entry
        const NSUInteger newCost = entry.completeFileSize + entry.partialFileSize;
        if (!newCost) {
            [manifest removeEntry:entry];
            entry = nil;
        } else {
            [self _tip_diskCache_addByteCount:newCost removeByteCount:oldCost];
            TIPAssert(newCost <= oldCost); // removing the cache image and/or partial image only ever removes bytes
        }

        if (entry) {
            // Update entry
            if (![entry.identifier isEqualToString:identifier]) {
                // Entries read from disk can have hashed identifiers.
                // If the safe identifiers match but the unsafe ones don't,
                // we can safely update the existing entry's identifier.
                entry.identifier = identifier;
            }
            [self _tip_diskCache_touchImageWithSafeIdentifier:safeIdentifer forced:NO];

            // Mutate and return a copy
            entry = [entry copy];

            if (TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageDiskCacheFetchOptionCompleteImage)) {
                [self _tip_diskCache_populateCompleteImageForEntry:entry decoderConfigMap:decoderConfigMap];
            }

            if (TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageDiskCacheFetchOptionPartialImage) || (TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageDiskCacheFetchOptionPartialImageIfNoCompleteImage) && !entry.completeImageContext)) {
                [self _tip_diskCache_populatePartialImageForEntry:entry decoderConfigMap:decoderConfigMap];
            }

            if (TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageDiskCacheFetchOptionTemporaryFile) || (TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageDiskCacheFetchOptionTemporaryFileIfNoCompleteImage) && !entry.completeImageContext)) {
                [self _tip_diskCache_populateTemporaryFileForEntry:entry];
            }
        }
    }

    return entry;
}

- (void)_tip_diskCache_populateCompleteImageForEntry:(TIPImageDiskCacheEntry *)entry decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
{
    if (entry.completeImageContext) {
        NSString *filePath = [self filePathForSafeIdentifier:entry.safeIdentifier];
        TIPAssertMessage(filePath != nil, @"entry.identifier = %@", entry.identifier);
        if (filePath) {
            TIPImageContainer *image = [TIPImageContainer imageContainerWithFilePath:filePath decoderConfigMap:decoderConfigMap codecCatalogue:nil memoryMap:entry.completeImageContext.isAnimated];
            entry.completeImage = image;
        }
    }
}

- (void)_tip_diskCache_populatePartialImageForEntry:(TIPImageDiskCacheEntry *)entry decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
{
    if (entry.partialImageContext) {
        NSString *filePath = [self filePathForSafeIdentifier:entry.safeIdentifier];
        filePath = [filePath stringByAppendingPathExtension:kPartialImageExtension];
        TIPAssertMessage(filePath != nil, @"entry.identifier = %@", entry.identifier);
        if (filePath) {
            NSData *data = [NSData dataWithContentsOfFile:filePath];
            if (data.length > 0) {
                TIPPartialImage *partialImage = [[TIPPartialImage alloc] initWithExpectedContentLength:entry.partialImageContext.expectedContentLength];
                [partialImage updateDecoderConfigMap:decoderConfigMap];
                [partialImage appendData:data final:NO];
                entry.partialImage = partialImage;
            }
        }
    }
}

- (void)_tip_diskCache_populateTemporaryFileForEntry:(TIPImageDiskCacheEntry *)entry
{
    if (entry.partialImageContext) {
        NSString *finalPath = [self filePathForSafeIdentifier:entry.safeIdentifier];
        NSString *partialPath = [finalPath stringByAppendingPathExtension:kPartialImageExtension];
        NSString *tempPath = TIPCreateTempFilePath();
        TIPAssertMessage(tempPath != nil, @"entry.identifier = %@", entry.identifier);
        TIPAssertMessage(partialPath != nil, @"entry.identifier = %@", entry.identifier);
        if (tempPath && partialPath && [[NSFileManager defaultManager] copyItemAtPath:partialPath toPath:tempPath error:NULL]) {
            TIPImageDiskCacheTemporaryFile *tempFile = [[TIPImageDiskCacheTemporaryFile alloc] initWithIdentifier:entry.identifier temporaryPath:tempPath finalPath:finalPath diskCache:self];
            entry.tempFile = tempFile;
        }
    }
}

- (void)diskCache_updateImageEntry:(TIPImageCacheEntry *)entry forciblyReplaceExisting:(BOOL)force
{
    @autoreleasepool {
        [self _tip_diskCache_updateImageEntry:entry forciblyReplaceExisting:force safeIdentifier:TIPSafeFromRaw(entry.identifier)];
    }
}

- (void)_tip_diskCache_updateImageEntry:(TIPImageCacheEntry *)entry forciblyReplaceExisting:(BOOL)force safeIdentifier:(NSString *)safeIdentifier
{
    // Validate entry first
    if (!entry.identifier) {
        return;
    }
    if (!entry.partialImageContext ^ !entry.partialImage) {
        return;
    }
    if (!entry.completeImageContext ^ (!entry.completeImage && !entry.completeImageData && !entry.completeImageFilePath)) {
        return;
    }

    [self _tip_diskCache_ensureCacheDirectoryExists];

    // Get the "existing" entry
    TIPLRUCache *manifest = [self diskCache_syncAccessManifest];
    TIPImageDiskCacheEntry *existingEntry = (TIPImageDiskCacheEntry *)[manifest entryWithIdentifier:safeIdentifier];
    const BOOL hasPreviousEntry = (existingEntry != nil);
    if (!existingEntry && (force || entry.completeImageContext || entry.partialImageContext)) {
        existingEntry = [[TIPImageDiskCacheEntry alloc] init];
        existingEntry.identifier = entry.identifier;
    } else if (existingEntry && ![existingEntry.identifier isEqualToString:entry.identifier]) {
        // Entries read from disk can have hashed identifiers.
        // If the safe identifiers match but the unsafe ones don't,
        // we can safely update the existing entry's identifier.
        existingEntry.identifier = entry.identifier;
    }

    // Set up variables
    BOOL didChangePartial = NO, didChangeComplete = NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *filePath = [self filePathForSafeIdentifier:safeIdentifier];
    NSString *partialFilePath = [filePath stringByAppendingPathExtension:kPartialImageExtension];

    // Check file path was generated
    if (!filePath) {
        NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
        if (entry.identifier) {
            userInfo[TIPProblemInfoKeyImageIdentifier] = entry.identifier;
        }
        if (safeIdentifier) {
            userInfo[TIPProblemInfoKeySafeImageIdentifier] = safeIdentifier;
        }
        NSURL *contextURL = entry.completeImageContext.URL ?: entry.partialImageContext.URL;
        if (contextURL) {
            userInfo[TIPProblemInfoKeyImageURL] = contextURL;
        }
        if (_cachePath) {
            // Context is helpful, but needn't expose it with a constant.
            userInfo[@"cachePath"] = _cachePath;
        }
        [_globalConfig postProblem:TIPProblemDiskCacheUpdateImageEntryCouldNotGenerateFileName userInfo:userInfo];
    }

    const NSUInteger oldCost = existingEntry.partialFileSize + existingEntry.completeFileSize;
    CGSize oldDimensions;
    CGSize newDimensions;
    BOOL oldWasPlaceholder;
    BOOL newIsPlaceholder;
    BOOL conditionMetToUpdate;

    // Update complete image
    oldDimensions = existingEntry.completeImageContext.dimensions;
    newDimensions = entry.completeImageContext.dimensions;
    oldWasPlaceholder = existingEntry.completeImageContext.treatAsPlaceholder;
    newIsPlaceholder = entry.completeImageContext.treatAsPlaceholder;

    conditionMetToUpdate = TIPUpdateImageConditionTest(force, oldWasPlaceholder, newIsPlaceholder, NO /*extra*/, newDimensions, oldDimensions, existingEntry.completeImageContext.URL, entry.completeImageContext.URL);

    if (conditionMetToUpdate) {
        existingEntry.completeImageContext = nil;
        existingEntry.completeFileSize = 0;
        if (filePath) {
            [fm removeItemAtPath:filePath error:NULL];
        }
        if (entry.completeImage || entry.completeImageData || entry.completeImageFilePath) {
            BOOL success = NO;
            NSError *error = nil;
            if (filePath) {
                if (entry.completeImage) {
                    success = [entry.completeImage saveToFilePath:filePath type:entry.completeImageContext.imageType codecCatalogue:nil options:TIPImageEncodingNoOptions quality:kTIPAppleQualityValueRepresentingJFIFQuality85 atomic:YES error:&error];
                } else if (entry.completeImageData) {
                    success = [entry.completeImageData writeToFile:filePath options:NSDataWritingAtomic error:&error];
                } else {
                    success = [fm copyItemAtPath:entry.completeImageFilePath toPath:filePath error:&error];
                }
            }

            if (success) {
                existingEntry.completeImageContext = [entry.completeImageContext copy];
                existingEntry.completeFileSize = (NSUInteger)TIPFileSizeAtPath(filePath, NULL);

                // Clear partial on new entry since we set the complete image
                entry.partialImage = nil;
                entry.partialImageContext = nil;
            } else {
                NSString *key = nil;
                id value = nil;
                if (entry.completeImage) {
                    key = @"image";
                    value = entry.completeImage;
                } else if (entry.completeImageData) {
                    key = @"imageData";
                    value = [NSString stringWithFormat:@"<Data: length=%tu>", entry.completeImageData.length];
                } else {
                    key = @"imageFilePath";
                    value = entry.completeImageFilePath;
                }
                TIPLogWarning(@"Failed to update disk cache entry! %@", @{
                                                                          @"filePath" : (filePath) ?: @"<null>",
                                                                          key : value,
                                                                          @"URL" : entry.completeImageContext.URL,
                                                                          @"id" : entry.identifier,
                                                                          @"error" : (error) ?: @"???"
                                                                          });
            }
        }
        didChangeComplete = YES;
    }

    // Update partial image
    oldDimensions = existingEntry.partialImageContext.dimensions;
    oldWasPlaceholder = existingEntry.partialImageContext.treatAsPlaceholder;
    newIsPlaceholder = entry.partialImageContext.treatAsPlaceholder;
    if (!didChangeComplete) {
        newDimensions = entry.partialImageContext.dimensions;
    }

    conditionMetToUpdate = NO;
    if (existingEntry.partialImageContext != nil || entry.partialImageContext != nil) {
        // only both if there is a partial image to care about
        conditionMetToUpdate = TIPUpdateImageConditionTest(force, oldWasPlaceholder, newIsPlaceholder, (oldWasPlaceholder && didChangeComplete) /*extra*/, newDimensions, oldDimensions, existingEntry.partialImageContext.URL, entry.partialImageContext.URL);
    }

    if (conditionMetToUpdate) {
        existingEntry.partialImageContext = nil;
        existingEntry.partialFileSize = 0;
        if (partialFilePath) {
            [fm removeItemAtPath:partialFilePath error:NULL];

            if (entry.partialImage && !newIsPlaceholder) {
                NSError *error = nil;
                if ([entry.partialImage.data writeToFile:partialFilePath options:NSDataWritingAtomic error:&error]) {
                    existingEntry.partialImageContext = [entry.partialImageContext copy];
                    existingEntry.partialFileSize = entry.partialImage.byteCount;
                } else {
                    TIPLogError(@"Failed to write partial image! %@", @{ @"data.length" : @(entry.partialImage.data.length), @"filePath" : partialFilePath, @"error" : (error) ?: @"???" });
                }
            }
        }
        didChangePartial = YES;
    }

    // Nothing changed
    if (!didChangePartial && !didChangeComplete) {
        return;
    }

    // Cap our entry size
    const SInt64 max = [_globalConfig internalMaxBytesForCacheEntryOfType:self.cacheType];
    if (existingEntry && (SInt64)existingEntry.partialFileSize > max) {

        NSDictionary *userInfo = @{
                                   TIPProblemInfoKeyImageIdentifier : existingEntry.identifier,
                                   TIPProblemInfoKeySafeImageIdentifier : existingEntry.safeIdentifier,
                                   TIPProblemInfoKeyImageURL : existingEntry.partialImageContext.URL,
                                   TIPProblemInfoKeyImageDimensions : [NSValue valueWithCGSize:existingEntry.partialImageContext.dimensions],
                                   @"expectedSize" : @(existingEntry.partialImageContext.expectedContentLength),
                                   @"partialSize" : @(existingEntry.partialFileSize),
                                   };
        [_globalConfig postProblem:TIPProblemImageTooLargeToStoreInDiskCache userInfo:userInfo];

        [fm removeItemAtPath:partialFilePath error:NULL];
        existingEntry.partialImage = nil;
        existingEntry.partialImageContext = nil;
        existingEntry.partialFileSize = 0;
        didChangePartial = YES;
    }
    if (existingEntry && (SInt64)existingEntry.completeFileSize > max) {

        NSDictionary *userInfo = @{
                                   TIPProblemInfoKeyImageIdentifier : existingEntry.identifier,
                                   TIPProblemInfoKeySafeImageIdentifier : existingEntry.safeIdentifier,
                                   TIPProblemInfoKeyImageURL : existingEntry.completeImageContext.URL,
                                   TIPProblemInfoKeyImageDimensions : [NSValue valueWithCGSize:existingEntry.completeImageContext.dimensions],
                                   @"size" : @(existingEntry.completeFileSize),
                                   };
        [_globalConfig postProblem:TIPProblemImageTooLargeToStoreInDiskCache userInfo:userInfo];

        [fm removeItemAtPath:filePath error:NULL];
        existingEntry.completeImage = nil;
        existingEntry.completeImageContext = nil;
        existingEntry.completeFileSize = 0;
        didChangeComplete = YES;
    }

    // Update xattrs and LRU
    const NSUInteger newCost = existingEntry.partialFileSize + existingEntry.completeFileSize;
    [self _tip_diskCache_addByteCount:newCost removeByteCount:oldCost];
    if (!hasPreviousEntry && existingEntry) {
        _globalConfig.internalTotalCountForAllDiskCaches += 1;
    }

    if (gTwitterImagePipelineAssertEnabled) {
        if (existingEntry.partialImageContext && 0 == existingEntry.partialFileSize) {
            NSDictionary *info = @{
                                   @"dimension" : NSStringFromCGSize(existingEntry.partialImageContext.dimensions),
                                   @"URL" : existingEntry.partialImageContext.URL,
                                   @"id" : existingEntry.identifier,
                                   };
            TIPLogError(@"Cached zero cost partial image to disk cache %@", info);
        }
        if (existingEntry.completeImageContext && 0 == existingEntry.completeFileSize) {
            NSDictionary *info = @{
                                   @"dimension" : NSStringFromCGSize(existingEntry.completeImageContext.dimensions),
                                   @"URL" : existingEntry.completeImageContext.URL,
                                   @"id" : existingEntry.identifier,
                                   };
            TIPLogError(@"Cached zero cost complete image to disk cache %@", info);
        }
    }

    [manifest addEntry:existingEntry];
    if (didChangePartial) {
        [self _tip_diskCache_touchEntry:existingEntry forced:force partial:YES];
    }
    if (didChangeComplete) {
        [self _tip_diskCache_touchEntry:existingEntry forced:force partial:NO];
    }

    [_globalConfig pruneAllCachesOfType:self.cacheType withPriorityCache:self];
}

- (BOOL)_tip_diskCache_touchImageWithSafeIdentifier:(NSString *)identifier forced:(BOOL)forced
{
    TIPLRUCache *manifest = [self diskCache_syncAccessManifest];
    TIPImageDiskCacheEntry *entry = (TIPImageDiskCacheEntry *)[manifest entryWithIdentifier:identifier];
    if (entry) {
        [self _tip_diskCache_touchEntry:entry forced:forced partial:YES];
        [self _tip_diskCache_touchEntry:entry forced:forced partial:NO];
    }
    return entry != nil;
}

- (void)_tip_diskCache_touchEntry:(nullable TIPImageDiskCacheEntry *)entry forced:(BOOL)forced partial:(BOOL)partial
{
    TIPImageCacheEntryContext *context = (partial) ? entry.partialImageContext : entry.completeImageContext;
    if (!context) {
        return;
    }

    if (context.updateExpiryOnAccess || !context.lastAccess) {
        context.lastAccess = [NSDate date];
    } else if (!forced) {
        return;
    }

    NSDictionary *xattrs = TIPXAttributesFromContext(context);
    NSString *filePath = [self filePathForSafeIdentifier:entry.safeIdentifier];
    if (partial) {
        filePath = [filePath stringByAppendingPathExtension:kPartialImageExtension];
    }

    TIPAssertMessage(filePath != nil, @"entry.identifier = %@", entry.identifier);
    if (!filePath) {
        return;
    }

    const NSUInteger numberOfSetXAttributes = TIPSetXAttributesForFile(xattrs, filePath);
    if (numberOfSetXAttributes != xattrs.count) {
        NSDictionary *info = @{
                               @"filePath" : filePath,
                               @"id" : entry.identifier,
                               @"safeId" : entry.safeIdentifier,
                               @"xattrs" : xattrs
                               };
        TIPLogError(@"Error writing xattrs! (wrote %tu of %tu)\n%@", numberOfSetXAttributes, xattrs.count, info);
    }

#if DEBUG
    NSDictionary *xattrsRoundTrip = TIPGetXAttributesForFile(filePath, TIPXAttributesKeysToKindsMap());
    TIPAssertMessage([xattrs isEqualToDictionary:xattrsRoundTrip], @"xattrs differ!\nSet: %@\nGet: %@", xattrs, xattrsRoundTrip);
#endif
}

- (void)_tip_diskCache_clearAllImages
{
    TIPStartMethodScopedBackgroundTask();
    TIPLRUCache *manifest = [self diskCache_syncAccessManifest];
    const SInt16 totalCount = (SInt16)manifest.numberOfEntries;
    [manifest clearAllEntries];
    [self _tip_diskCache_addByteCount:0 removeByteCount:(UInt64)self.atomicTotalSize];
    _globalConfig.internalTotalCountForAllDiskCaches -= totalCount;
    [[NSFileManager defaultManager] removeItemAtPath:_cachePath error:NULL];
    TIPLogInformation(@"Cleared all images in %@", self);
}

- (void)_tip_diskCache_finalizeTemporaryFile:(TIPImageDiskCacheTemporaryFile * const)tempFile withContext:(TIPImageCacheEntryContext *)context
{
    NSString * const finalPath = tempFile.finalPath;
    if (!finalPath) {
        NSString *message = [NSString stringWithFormat:@"%@ has a nil finalPath.  identifier: %@", NSStringFromClass([tempFile class]), tempFile.imageIdentifier];
        TIPAssertMessage(finalPath != nil, @"%@", message);
        TIPLogError(@"%@", message);
        return;
    }

    NSString * const tempPath = tempFile.temporaryPath;
    if (!tempPath) {
        NSString *message = [NSString stringWithFormat:@"%@ has a nil temporaryPath.  identifier: %@", NSStringFromClass([tempFile class]), tempFile.imageIdentifier];
        TIPAssertMessage(tempPath != nil, @"%@", message);
        TIPLogError(@"%@", message);
        return;
    }

    NSString * const partialPath = [finalPath stringByAppendingPathExtension:kPartialImageExtension];
    NSString * const safeIdentifier = [finalPath lastPathComponent];
    TIPAssert([safeIdentifier isEqualToString:TIPSafeFromRaw(tempFile.imageIdentifier)]);

    [self _tip_diskCache_ensureCacheDirectoryExists];

    BOOL const isPartial = [context isKindOfClass:[TIPPartialImageEntryContext class]];
    if (!isPartial) {
        if (![context isKindOfClass:[TIPCompleteImageEntryContext class]]) {
            TIPAssertMessage(NO, @"Invalid or nil context provided!");
            return;
        }
    }

    if (isPartial && context.treatAsPlaceholder) {
        // don't cache incomplete placeholders
        [self clearTemporaryFilePath:tempFile.temporaryPath];
        return;
    }

    NSUInteger const size = (NSUInteger)TIPFileSizeAtPath(tempFile.temporaryPath, NULL);
    if (!size) {
        [self clearTemporaryFilePath:tempFile.temporaryPath];
        return;
    }

    NSFileManager * const fm = [NSFileManager defaultManager];
    TIPLRUCache * const manifest = [self diskCache_syncAccessManifest];
    TIPImageDiskCacheEntry *entry = (TIPImageDiskCacheEntry *)[manifest entryWithIdentifier:safeIdentifier];
    TIPImageCacheEntryContext * const oldPartialContext = entry.partialImageContext;
    TIPImageCacheEntryContext * const oldCompleteContext = entry.completeImageContext;
    CGSize const newDimensions = context.dimensions;
    CGSize const oldPartialDimensions = oldPartialContext.dimensions;
    CGSize const oldCompleteDimensions = oldCompleteContext.dimensions;

    // 1) Remove lowest fidelity entries where appropriate

    if (entry) {
        if (!isPartial) {
            // This is a complete entry...

            if (oldPartialContext) {
                if ((oldPartialDimensions.width * oldPartialDimensions.height) <= (newDimensions.width * newDimensions.height)) {
                    // if the old partial image is smaller (or equal), remove it
                    [self _tip_diskCache_addByteCount:0 removeByteCount:entry.partialFileSize];
                    entry.partialFileSize = 0;
                    entry.partialImageContext = nil;
                    [fm removeItemAtPath:partialPath error:NULL];
                }
            }

            if (oldCompleteContext) {
                const BOOL oldSizeTooSmall = (oldCompleteDimensions.width * oldCompleteDimensions.height) < (newDimensions.width * newDimensions.height);
                if (oldSizeTooSmall || oldCompleteContext.treatAsPlaceholder) {
                    // if the old complete image is smaller, remove it
                    [self _tip_diskCache_addByteCount:0 removeByteCount:entry.completeFileSize];
                    entry.completeFileSize = 0;
                    entry.completeImageContext = nil;
                    [fm removeItemAtPath:finalPath error:NULL];
                } else {
                    // otherwise, clear ourself
                    [self clearTemporaryFilePath:tempFile.temporaryPath];
                    return;
                }
            }
        } else {
            // This is a partial entry...

            if (oldPartialContext) {
                if ((oldPartialDimensions.width * oldPartialDimensions.height) <= (newDimensions.width * newDimensions.height)) {
                    // if the old partial image is smaller (or equal), remove it
                    [self _tip_diskCache_addByteCount:0 removeByteCount:entry.partialFileSize];
                    entry.partialFileSize = 0;
                    entry.partialImageContext = nil;
                    [fm removeItemAtPath:partialPath error:NULL];
                }
            }

            if (oldCompleteContext) {
                if ((oldCompleteDimensions.width * oldCompleteDimensions.height) >= (newDimensions.width * newDimensions.height)) {
                    // if the old complete image is larger (or equal), clear ourselves
                    [self clearTemporaryFilePath:tempFile.temporaryPath];
                    return;
                }
            }
        }
    }

    // 2) Move our new bytes into the disk cache

    NSError *error;
    if ([fm moveItemAtPath:tempFile.temporaryPath toPath:(isPartial) ? partialPath : finalPath error:&error]) {
        context = [context copy];

        const BOOL newEntry = !entry;
        if (!entry) {
            entry = [[TIPImageDiskCacheEntry alloc] init];
            entry.identifier = tempFile.imageIdentifier;
        }

        if (isPartial) {
            entry.partialFileSize = size;
            entry.partialImageContext = (id)context;
        } else {
            entry.completeFileSize = size;
            entry.completeImageContext = (id)context;
        }

        [self _tip_diskCache_addByteCount:size removeByteCount:0];
        if (newEntry) {
            _globalConfig.internalTotalCountForAllDiskCaches += 1;
        }

        if (gTwitterImagePipelineAssertEnabled) {
            if (entry.partialImageContext && 0 == entry.partialFileSize) {
                TIPLogError(@"Cached zero cost partial image to disk cache %@", @{
                                                                                  @"dimension" : NSStringFromCGSize(entry.partialImageContext.dimensions),
                                                                                  @"URL" : entry.partialImageContext.URL,
                                                                                  @"id" : entry.identifier,
                                                                                  });
            }
            if (entry.completeImageContext && 0 == entry.completeFileSize) {
                TIPLogError(@"Cached zero cost complete image to disk cache %@", @{
                                                                                   @"dimension" : NSStringFromCGSize(entry.completeImageContext.dimensions),
                                                                                   @"URL" : entry.completeImageContext.URL,
                                                                                   @"id" : entry.identifier,
                                                                                   });
            }
        }

        [manifest addEntry:entry];
        [self _tip_diskCache_touchEntry:entry forced:YES partial:isPartial];
        [_globalConfig pruneAllCachesOfType:self.cacheType withPriorityCache:self];
    } else {
        TIPLogWarning(@"%@", error);
    }
}

- (void)_tip_diskCache_inspect:(TIPInspectableCacheCallback)callback
{
    NSMutableArray *completedEntries = [[NSMutableArray alloc] init];
    NSMutableArray *partialEntries = [[NSMutableArray alloc] init];

    TIPLRUCache *manifest = [self diskCache_syncAccessManifest];
    for (TIPImageDiskCacheEntry *cacheEntry in manifest) {
        TIPImagePipelineInspectionResultEntry *entry;

        entry = [TIPImagePipelineInspectionResultEntry entryWithCacheEntry:cacheEntry class:[TIPImagePipelineInspectionResultCompleteDiskEntry class]];
        if (entry) {
            [completedEntries addObject:entry];
        }

        entry = [TIPImagePipelineInspectionResultEntry entryWithCacheEntry:cacheEntry class:[TIPImagePipelineInspectionResultPartialDiskEntry class]];
        if (entry) {
            [partialEntries addObject:entry];
        }
    }

    callback(completedEntries, partialEntries);
}

- (BOOL)_tip_diskCache_renameImageEntryWithIdentifier:(NSString *)oldIdentifier toIdentifier:(NSString *)newIdentifier error:(NSError * __nullable * __nullable)errorOut
{
    NSString *oldSafeID = TIPSafeFromRaw(oldIdentifier);
    TIPLRUCache *manifest = [self diskCache_syncAccessManifest];
    TIPImageDiskCacheEntry *oldEntry = (TIPImageDiskCacheEntry *)[manifest entryWithIdentifier:oldSafeID canMutate:NO];
    if (!oldEntry) {
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil];
        }
        return NO;
    }

    NSString *newSafeID = TIPSafeFromRaw(newIdentifier);
    TIPCompleteImageEntryContext *completeContext = oldEntry.completeImageContext;
    NSString *oldCompleteFilePath = (completeContext) ? [self filePathForSafeIdentifier:oldSafeID] : nil;
    TIPPartialImageEntryContext *partialContext = oldEntry.partialImageContext;
    NSString *oldPartialFilePath = (partialContext) ? [[self filePathForSafeIdentifier:oldSafeID] stringByAppendingPathExtension:kPartialImageExtension] : nil;

    NSError *error = nil;
    BOOL fail = NO;
    if (oldCompleteFilePath) {
        NSString *newCompleteFilePath = [self filePathForSafeIdentifier:newSafeID];
        fail = ![[NSFileManager defaultManager] moveItemAtPath:oldCompleteFilePath toPath:newCompleteFilePath error:&error];
    }

    if (!fail && oldPartialFilePath) {
        NSString *newPartialFilePath = [[self filePathForSafeIdentifier:newSafeID] stringByAppendingPathExtension:kPartialImageExtension];
        fail = ![[NSFileManager defaultManager] moveItemAtPath:oldPartialFilePath toPath:newPartialFilePath error:&error];
        if (fail) {
            if (oldCompleteFilePath) {
                // complete images take precedence over partial
                fail = NO;
                error = nil;
                [[NSFileManager defaultManager] removeItemAtPath:oldPartialFilePath error:NULL];
            }
        }
    }

    if (!fail) {
        TIPImageDiskCacheEntry *newEntry = [oldEntry copy];
        newEntry.identifier = newIdentifier;
        [manifest removeEntry:oldEntry];
        [manifest addEntry:newEntry];
        [self _tip_diskCache_addByteCount:newEntry.completeFileSize + newEntry.partialFileSize removeByteCount:0];
        _globalConfig.internalTotalCountForAllDiskCaches += 1;
    }

    TIPAssert(fail ^ !error);
    if (errorOut) {
        *errorOut = error;
    }
    return !fail;
}

- (TIPLRUCache *)diskCache_syncAccessManifest
{
    if (!_diskCache_flags.manifestIsLoading) {
        // quick - unsynchronized...
        // ...safe since _diskCache_flags.manifestIsLoading is sync'd on diskCache queue
        return _manifest;
    }

    // slow - synchronized
    return [self manifest];
}

@end

@implementation TIPImageDiskCache (Manifest)

- (void)manifest_populateManifest:(NSString *)cachePath
{
    const uint64_t machStart = mach_absolute_time();
    [self manifest_populateEntriesFromCachePath:cachePath completion:^(unsigned long long totalSize, NSArray<TIPImageDiskCacheEntry *> *entries, NSArray<NSString *> *falseEntryPaths) {

        // remove files on background queue BEFORE updating the manifest
        // to avoid race condition with earily read path
        NSFileManager *fm = [NSFileManager defaultManager];
        tip_dispatch_async_autoreleasing(self->_globalConfig.queueForDiskCaches, ^{
            for (NSString *falseEntryPath in falseEntryPaths) {
                [fm removeItemAtPath:falseEntryPath error:NULL];
            }
        });

        [self manifest_finalizePopulateManifest:entries totalSize:totalSize];

        const uint64_t machEnd = mach_absolute_time();
        TIPLogInformation(@"%@('%@') took %.3fs to populate its manifest", NSStringFromClass([self class]), self.cachePath.lastPathComponent, TIPComputeDuration(machStart, machEnd));

        [self prune]; // goes to the background queue
    }];
}

- (void)manifest_populateEntriesFromCachePath:(NSString *)cachePath completion:(TIPImageDiskCacheManifestPopulateEntriesCompletionBlock)completionBlock
{
    tip_dispatch_async_autoreleasing(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSError *error;
        NSArray *entryPaths = cachePath ? TIPContentsAtPath(cachePath, &error) : nil;
        if (!entryPaths) {
            TIPLogError(@"%@ could not load its cache entries from path '%@'. %@", NSStringFromClass([self class]), cachePath, error);
            tip_dispatch_async_autoreleasing(self->_manifestQueue, ^{
                completionBlock(0, nil, nil);
            });
            return;
        }

        __block unsigned long long totalSize = 0;
        NSDate *now = [NSDate date];

        NSMutableArray<TIPImageDiskCacheEntry *> *entries = [[NSMutableArray alloc] init];
        NSMutableArray<NSString *> *falseEntryPaths = [[NSMutableArray alloc] init];
        NSMutableDictionary<NSString *, TIPImageDiskCacheEntry *> *manifest = [[NSMutableDictionary alloc] initWithCapacity:entryPaths.count];
        NSOperationQueue *manifestCacheQueue = TIPImageDiskCacheManifestCacheQueue();
        NSOperationQueue *manifestIOQueue = TIPImageDiskCacheManifestIOQueue();
        dispatch_queue_t manifestAccessQueue = self->_manifestQueue;
        __block TIPImageDiskCacheManifestPopulateEntriesCompletionBlock clearableCompletionBlock = [completionBlock copy];

        NSOperation *finalIOOperation = [NSBlockOperation blockOperationWithBlock:^{
            // nothing, just an operation for dependency ordering
        }];
        NSOperation *finalCacheOperation = [NSBlockOperation blockOperationWithBlock:^{

            // sort entries
            TIPSortEntries(entries);

            // assert that we don't dupe entries
            if (gTwitterImagePipelineAssertEnabled) {
                NSSet *entrySet = [NSSet setWithArray:entries];
                TIPAssertMessage(entrySet.count == entries.count, @"Manifest load yielded the same entry (or entries) to be counted more than once!!!");
            }

            tip_dispatch_async_autoreleasing(manifestAccessQueue, ^{

                // Call the completion block
                clearableCompletionBlock(totalSize, entries, falseEntryPaths);

                // MUST clear the block since not clearing it can lead to a retain cycle
                clearableCompletionBlock = nil;

            });
        }];
        [finalCacheOperation addDependency:finalIOOperation];

        for (NSString *entryPath in entryPaths) {
            // putting the construction of the operation to load a manifest entry
            // in a function to avoid risking capturing self which can lead to a
            // retain cycle.
            NSOperation *ioOp = TIPImageDiskCacheManifestLoadOperation(manifest,
                                                                       falseEntryPaths,
                                                                       entries,
                                                                       &totalSize,
                                                                       entryPath,
                                                                       cachePath,
                                                                       now,
                                                                       manifestCacheQueue,
                                                                       finalCacheOperation);
            [finalIOOperation addDependency:ioOp];
            [manifestIOQueue tip_safeAddOperation:ioOp];
        }

        [manifestIOQueue tip_safeAddOperation:finalIOOperation];
        [manifestCacheQueue tip_safeAddOperation:finalCacheOperation];
    });
}

- (void)manifest_finalizePopulateManifest:(NSArray<TIPImageDiskCacheEntry *> *)entries totalSize:(unsigned long long)totalSize
{
    const BOOL didLoadEntries = entries != nil;
    const SInt16 count = (didLoadEntries) ? (SInt16)entries.count : 0;
    _manifest = (didLoadEntries) ? [[TIPLRUCache alloc] initWithEntries:entries delegate:self] : nil;
    pthread_mutex_unlock(&_manifestMutex);
    tip_dispatch_async_autoreleasing(_globalConfig.queueForDiskCaches, ^{
        self->_diskCache_flags.manifestIsLoading = NO;
        if (didLoadEntries) {
            const UInt64 removeSize = self->_earlyRemovedBytesSize;
            self->_earlyRemovedBytesSize = 0;
            self->_globalConfig.internalTotalCountForAllDiskCaches += count;
            [self _tip_diskCache_addByteCount:totalSize removeByteCount:removeSize];
        }
    });
}

@end

static NSDictionary * __nullable TIPXAttributesFromContext(TIPImageCacheEntryContext * __nullable context)
{
    if (!context || !context.URL) {
        return nil;
    }

    if (!context.lastAccess) {
        context.lastAccess = [NSDate date];
    }

    NSMutableDictionary *d = [[NSMutableDictionary alloc] initWithCapacity:TIPXAttributesKeysToKindsMap().count];

    TIPAssert(context.TTL > 0.0);

    // Alwasy set ALL values
    d[kXAttributeContextURLKey] = context.URL;
    d[kXAttributeContextLastAccessKey] = context.lastAccess;
    d[kXAttributeContextTTLKey] =  @(context.TTL);
    d[kXAttributeContextUpdateTLLOnAccessKey] = @(context.updateExpiryOnAccess);
    d[kXAttributeContextDimensionXKey] = @(context.dimensions.width);
    d[kXAttributeContextDimensionYKey] = @(context.dimensions.height);
    d[kXAttributeContextAnimated] = @(context.isAnimated);

    if ([context isKindOfClass:[TIPPartialImageEntryContext class]]) {
        TIPPartialImageEntryContext *partialContext = (id)context;
        d[kXAttributeContextLastModifiedKey] = partialContext.lastModified ?: @"!";
        d[kXAttributeContextExpectedSizeKey] = @(partialContext.expectedContentLength);
    } else {
        d[kXAttributeContextLastModifiedKey] = @"!";
        d[kXAttributeContextExpectedSizeKey] = @0;
    }

    if (context.treatAsPlaceholder) {
        d[kXAttributeContextTreatAsPlaceholderKey] = @YES;
    }

    return d;
}

static TIPImageCacheEntryContext * __nullable TIPContextFromXAttributes(NSDictionary *xattrs, BOOL notYetComplete)
{
    id val;
    TIPImageCacheEntryContext *context = nil;
    if (!notYetComplete) {
        context = [[TIPCompleteImageEntryContext alloc] init];
    } else {
        context = [[TIPPartialImageEntryContext alloc] init];
        TIPPartialImageEntryContext *partialContext = (id)context;
        val = xattrs[kXAttributeContextLastModifiedKey];
        partialContext.lastModified = [(NSString *)val length] < 4 ? nil : val;
        val = xattrs[kXAttributeContextExpectedSizeKey];
        partialContext.expectedContentLength = [(NSNumber *)val unsignedIntegerValue];
    }

    val = xattrs[kXAttributeContextURLKey];
    if (!val) {
        return nil;
    }
    context.URL = val;

    val = xattrs[kXAttributeContextLastAccessKey];
    if (!val) {
        return nil;
    }
    context.lastAccess = val;

    val = xattrs[kXAttributeContextTTLKey];
    if (!val) {
        return nil;
    }
    context.TTL = [(NSNumber *)val doubleValue];

    val = xattrs[kXAttributeContextAnimated];
    if (!val) {
        // Don't fail on missing "animated" property
        val = @NO;
    }
    context.animated = [(NSNumber *)val boolValue];

    CGSize dimensions = CGSizeZero;
    dimensions.width = (CGFloat)[xattrs[kXAttributeContextDimensionXKey] doubleValue];
    dimensions.height = (CGFloat)[xattrs[kXAttributeContextDimensionYKey] doubleValue];
    if (dimensions.width < 1.0 || dimensions.height < 1.0) {
        return nil;
    }
    context.dimensions = dimensions;

    val = xattrs[kXAttributeContextUpdateTLLOnAccessKey];
    context.updateExpiryOnAccess = [val boolValue];

    val = xattrs[kXAttributeContextTreatAsPlaceholderKey];
    context.treatAsPlaceholder = [val boolValue];

    return context;
}

static NSOperation *TIPImageDiskCacheManifestLoadOperation(NSMutableDictionary<NSString *, TIPImageDiskCacheEntry *> *manifest, NSMutableArray<NSString *> *falseEntryPaths, NSMutableArray<TIPImageDiskCacheEntry *> *entries, unsigned long long *totalSizeInOut, NSString *path, NSString *cachePath, NSDate *timestamp, NSOperationQueue *manifestCacheQueue, NSOperation *finalCacheOperation)
{
    __weak typeof(finalCacheOperation) weakFinalCacheOperation = finalCacheOperation;
    return [NSBlockOperation blockOperationWithBlock:^{
        TIPImageCacheEntryContext *context = nil;
        NSString *rawIdentifier = nil;
        NSError *error = nil;
        const BOOL isTmp = [[path pathExtension] isEqualToString:kPartialImageExtension];
        NSString * const safeIdentifier = isTmp ? [path stringByDeletingPathExtension] : path;
        NSString *entryPath = [cachePath stringByAppendingPathComponent:path];

        const NSUInteger size = TIPFileSizeAtPath(entryPath, &error);
        if (!size) {
            TIPLogError(@"Could not get stat() of '%@': %@", entryPath, error);
        } else {
            rawIdentifier = TIPRawFromSafe(safeIdentifier);
            context = (rawIdentifier) ? TIPContextFromXAttributes(TIPGetXAttributesForFile(entryPath, TIPXAttributesKeysToKindsMap()), isTmp) : nil;
            if (isTmp && ![context isKindOfClass:[TIPPartialImageEntryContext class]]) {
                context = nil;
            } else if (!isTmp && [context isKindOfClass:[TIPPartialImageEntryContext class]]) {
                context = nil;
            }
        }

        NSBlockOperation *cacheOp = [NSBlockOperation blockOperationWithBlock:^{
            if (!context || ([timestamp timeIntervalSinceDate:context.lastAccess] > context.TTL)) {
                [falseEntryPaths addObject:entryPath];
                return;
            }

            BOOL manifestCacheHit = NO;
            TIPImageDiskCacheEntry *entry = nil;

            entry = manifest[safeIdentifier];
            if (!entry) {
                entry = [[TIPImageDiskCacheEntry alloc] init];
                entry.identifier = rawIdentifier;
                manifest[safeIdentifier] = entry;
                [entries addObject:entry];
            } else {
                manifestCacheHit = YES;
            }

            if (manifestCacheHit) {
                TIPAssertMessage([entry.identifier isEqualToString:rawIdentifier], @"\n\tentry.identifier = %@\n\trawIdentifier = %@", entry.identifier, rawIdentifier);
            }

            if (isTmp) {
                TIPAssertMessage(!entry.partialImageContext, @"\n\tentry.identifier = %@\n\trawIdentifier = %@", entry.identifier, rawIdentifier);
                entry.partialImageContext = (id)context;
                entry.partialFileSize = size;
            } else {
                TIPAssertMessage(!entry.completeImageContext, @"\n\tentry.identifier = %@\n\trawIdentifier = %@", entry.identifier, rawIdentifier);
                entry.completeImageContext = (id)context;
                entry.completeFileSize = size;
            }
            *totalSizeInOut = *totalSizeInOut + size;

            if (entry.partialImageContext && entry.completeImageContext) {
                const CGSize partialDimensions = entry.partialImageContext.dimensions;
                const CGSize completeDimensions = entry.completeImageContext.dimensions;

                if ((partialDimensions.width * partialDimensions.height) <= (completeDimensions.width * completeDimensions.height)) {
                    // We have a partial image that is lower fidelity than a completed image...
                    // remove the partial image from our disk cache

                    NSString * const partialEntryPath = [entryPath stringByAppendingPathExtension:kPartialImageExtension];

                    *totalSizeInOut = *totalSizeInOut - entry.partialFileSize;
                    entry.partialFileSize = 0;
                    entry.partialImageContext = nil;

                    TIPLogWarning(@"Partial image in disk cache is lower fidelity than complete image counterpart, removing: %@", partialEntryPath);

                    [falseEntryPaths addObject:partialEntryPath];
                }
            }
        }];

        [weakFinalCacheOperation addDependency:cacheOp];
        [manifestCacheQueue tip_safeAddOperation:cacheOp];
    }];
}

static BOOL TIPUpdateImageConditionTest(const BOOL force, const BOOL oldWasPlaceholder, const BOOL newIsPlaceholder, const BOOL extraCondition, const CGSize newDimensions, const CGSize oldDimensions, NSURL * __nullable oldURL, NSURL * __nullable newURL)
{
    if (force) {
        // forced
        return YES;
    }
    if (oldWasPlaceholder && !newIsPlaceholder) {
        // are we replacing a placeholder w/ a non-placeholder?
        return YES;
    }
    if (extraCondition) {
        // extra condition
        return YES;
    }
    if (oldWasPlaceholder != newIsPlaceholder) {
        // placeholderness missmatch
        return NO;
    }

    // IMPORTANT: We use "last in wins" logic.
    // It is easier for clients to detect larger varients matching smaller varients
    // than smaller variants matching larger variants.
    // This way, clients can load the smaller variant first, load the larger variant second and
    // (next time they access smaller or larger variant) the larger variant is cached.

    if ((newDimensions.width * newDimensions.height) >= (oldDimensions.width * oldDimensions.height)) {
        // we're replacing based on size, is the image identical?
        // Be sure we aren't replacing the identical image (by URL)
        const BOOL isIdenticalImage = CGSizeEqualToSize(oldDimensions, newDimensions) && [oldURL isEqual:newURL];
        if (!isIdenticalImage) {
            return YES;
        }
    }

    return NO;
}

static NSOperationQueue *TIPImageDiskCacheManifestCacheQueue()
{
    static NSOperationQueue *sQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sQueue = [[NSOperationQueue alloc] init];
        sQueue.name = @"com.twitter.tip.disk.manifest.cache.queue";
        sQueue.maxConcurrentOperationCount = 1;
    });
    return sQueue;
}

static NSOperationQueue *TIPImageDiskCacheManifestIOQueue()
{
    static NSOperationQueue *sQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sQueue = [[NSOperationQueue alloc] init];
        sQueue.name = @"com.twitter.tip.disk.manifest.io.queue";
        sQueue.maxConcurrentOperationCount = 4; // parallelized
    });
    return sQueue;
}

static dispatch_queue_t TIPImageDiskCacheManifestAccessQueue()
{
    static dispatch_queue_t sQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sQueue = dispatch_queue_create("com.twitter.tip.disk.manifest.access.queue", DISPATCH_QUEUE_SERIAL);
    });
    return sQueue;
}

static void TIPSortEntries(NSMutableArray<TIPImageDiskCacheEntry *> *entries)
{
    [entries sortUsingComparator:^NSComparisonResult(TIPImageDiskCacheEntry *entry1, TIPImageDiskCacheEntry *entry2) {
        NSDate *lastAccess1 = entry1.mostRecentAccess;
        NSDate *lastAccess2 = entry2.mostRecentAccess;

        // Simple check if both are nil (or identical)
        if (lastAccess1 == lastAccess2) {
            return NSOrderedSame;
        }

        // Put the missing access at the end
        if (!lastAccess1) {
            return NSOrderedDescending;
        } else if (!lastAccess2) {
            return NSOrderedAscending;
        }

        // Full compare
        return [lastAccess2 compare:lastAccess1];
    }];
}

NS_ASSUME_NONNULL_END
