//
//  TIPGlobalConfiguration.m
//  TwitterImagePipeline
//
//  Created on 10/1/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#include <pthread.h>
#include <objc/runtime.h>

#import <UIKit/UITraitCollection.h>

#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageCache.h"
#import "TIPImageDiskCache.h"
#import "TIPImageFetchDownloadInternal.h"
#import "TIPImageFetchOperation.h"
#import "TIPImageMemoryCache.h"
#import "TIPImagePipeline+Project.h"
#import "TIPImageRenderedCache.h"
#import "TIPImageStoreAndMoveOperations.h"

NS_ASSUME_NONNULL_BEGIN

SInt64 const TIPMaxBytesForAllRenderedCachesDefault = -1;
SInt64 const TIPMaxBytesForAllMemoryCachesDefault = -1;
SInt64 const TIPMaxBytesForAllDiskCachesDefault = -1;
SInt16 const TIPMaxCountForAllMemoryCachesDefault = INT16_MAX >> 7;
SInt16 const TIPMaxCountForAllRenderedCachesDefault = INT16_MAX >> 7;
SInt16 const TIPMaxCountForAllDiskCachesDefault = INT16_MAX >> 4;
NSInteger const TIPMaxConcurrentImagePipelineDownloadCountDefault = 4;
NSUInteger const TIPMaxRatioSizeOfCacheEntryDefault = 6;

// Cap the default max memory bytes at 160MB (to be split equally betweet Rendered and Memory caches) -- a reasonable limit for devices with lots of RAM since iOS still enforces memory warnings even if the device has much more RAM available
#define DEFAULT_MAX_RENDERED_BYTES_CAP      (160ull * 1024ull * 1024ull)
// Default the max bytes for in memory caching to 1/12th the devices RAM (to be split equally betweet Rendered and Memory caches)
#define DEFAULT_MAX_RENDERED_BYTES_DIVISOR  (12ull)
// Arbitrarily default the max bytes for on disk caching to 128MBs (roughly 64 large images or 1,600 small images or 32,000 73x73 avatars)
#define DEFAULT_MAX_DISK_BYTES              (128ull * 1024ull * 1024ull)

NS_INLINE SInt64 _MaxBytesForAllRenderedCachesDefaultValue()
{
    return (SInt64)MIN([[NSProcessInfo processInfo] physicalMemory] / DEFAULT_MAX_RENDERED_BYTES_DIVISOR, DEFAULT_MAX_RENDERED_BYTES_CAP) / 2;
}

NS_INLINE SInt64 _MaxBytesForAllMemoryCachesDefaultValue()
{
    return (SInt64)48ull * 1024ull * 1024ull;
}

NS_INLINE SInt64 _MaxBytesForAllDiskCachesDefaultValue()
{
    return (SInt64)DEFAULT_MAX_DISK_BYTES;
}

@implementation TIPGlobalConfiguration
{
    NSOperationQueue *_sharedImagePipelineQueue;
    dispatch_queue_t _globalObserversQueue;
    dispatch_queue_t _queueForMemoryCaches;
    dispatch_queue_t _queueForDiskCaches;
    NSHashTable<id<TIPImagePipelineObserver>> *_globalObservers;
}

@synthesize imageFetchDownloadProvider = _imageFetchDownloadProvider;

- (void)setInternalTotalBytesForAllDiskCaches:(SInt64)internalTotalBytesForAllDiskCaches
{
    TIPAssert(internalTotalBytesForAllDiskCaches >= 0);
    _internalTotalBytesForAllDiskCaches = internalTotalBytesForAllDiskCaches;
}

- (void)setInternalTotalBytesForAllMemoryCaches:(SInt64)internalTotalBytesForAllMemoryCaches
{
    TIPAssert(internalTotalBytesForAllMemoryCaches >= 0);
    _internalTotalBytesForAllMemoryCaches = internalTotalBytesForAllMemoryCaches;
}

- (void)setInternalTotalBytesForAllRenderedCaches:(SInt64)internalTotalBytesForAllRenderedCaches
{
    TIPAssert(internalTotalBytesForAllRenderedCaches >= 0);
    _internalTotalBytesForAllRenderedCaches = internalTotalBytesForAllRenderedCaches;
}

- (void)setInternalMaxCountForAllDiskCaches:(SInt16)internalMaxCountForAllDiskCaches
{
    TIPAssert(internalMaxCountForAllDiskCaches >= 0);
    _internalMaxCountForAllDiskCaches = internalMaxCountForAllDiskCaches;
}

- (void)setInternalMaxCountForAllMemoryCaches:(SInt16)internalMaxCountForAllMemoryCaches
{
    TIPAssert(internalMaxCountForAllMemoryCaches >= 0);
    _internalMaxCountForAllMemoryCaches = internalMaxCountForAllMemoryCaches;
}

- (void)setInternalMaxCountForAllRenderedCaches:(SInt16)internalMaxCountForAllRenderedCaches
{
    TIPAssert(internalMaxCountForAllRenderedCaches >= 0);
    _internalMaxCountForAllRenderedCaches = internalMaxCountForAllRenderedCaches;
}

- (nonnull instancetype)initInternal
{
    if (self = [super init]) {
        _internalMaxBytesForAllDiskCaches = _MaxBytesForAllDiskCachesDefaultValue();
        _internalMaxBytesForAllMemoryCaches = _MaxBytesForAllMemoryCachesDefaultValue();
        _internalMaxBytesForAllRenderedCaches = _MaxBytesForAllRenderedCachesDefaultValue();

        _internalMaxCountForAllDiskCaches = TIPMaxCountForAllDiskCachesDefault;
        _internalMaxCountForAllMemoryCaches = TIPMaxCountForAllMemoryCachesDefault;
        _internalMaxCountForAllRenderedCaches = TIPMaxCountForAllRenderedCachesDefault;

        _maxConcurrentImagePipelineDownloadCount = TIPMaxConcurrentImagePipelineDownloadCountDefault;
        _maxRatioSizeOfCacheEntry = TIPMaxRatioSizeOfCacheEntryDefault;
        _clearMemoryCachesOnApplicationBackgroundEnabled = NO;
        _serializeCGContextAccess = YES;

        _queueForDiskCaches = dispatch_queue_create("tip.global.disk.cache.queue", DISPATCH_QUEUE_SERIAL);
        _queueForMemoryCaches = dispatch_queue_create("tip.global.memory.cache.queue", DISPATCH_QUEUE_SERIAL);
        _globalObserversQueue = dispatch_queue_create("tip.global.obervers.accessor.queue", DISPATCH_QUEUE_CONCURRENT);

        _sharedImagePipelineQueue = [[NSOperationQueue alloc] init];
        _sharedImagePipelineQueue.name = @"tip.global.image.pipeline.operation.queue";
        _sharedImagePipelineQueue.qualityOfService = NSQualityOfServiceUtility;

        // Don't let TIP get overwhelmed with fetch requests
#if __LP64__
        _sharedImagePipelineQueue.maxConcurrentOperationCount = 6;
#else
        _sharedImagePipelineQueue.maxConcurrentOperationCount = 4;
#endif

        _globalObservers = [NSHashTable<id<TIPImagePipelineObserver>> weakObjectsHashTable];
        self.imageFetchDownloadProvider = nil;

        (void)TIPIsExtension(); // cache if we're an extension
    }
    return self;
}

+ (instancetype)sharedInstance
{
    static TIPGlobalConfiguration *sConfig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sConfig = [[TIPGlobalConfiguration alloc] initInternal];
    });
    return sConfig;
}

- (void)setMaxBytesForAllRenderedCaches:(SInt64)maxBytes
{
    if ([NSThread isMainThread]) {
        self.internalMaxBytesForAllRenderedCaches = (maxBytes >= 0ll) ? maxBytes : _MaxBytesForAllRenderedCachesDefaultValue();
        [self pruneAllCachesOfType:TIPImageCacheTypeRendered withPriorityCache:nil];
    } else {
        tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            self.maxBytesForAllRenderedCaches = maxBytes;
        });
    }
}

- (SInt64)maxBytesForAllRenderedCaches
{
    if (![NSThread isMainThread]) {
        TIPLogWarning(@"Read %@ from %@ off the main thread!", NSStringFromSelector(_cmd), NSStringFromClass([self class]));
    }
    return self.internalMaxBytesForAllRenderedCaches;
}

- (void)setMaxCountForAllRenderedCaches:(SInt16)maxCount
{
    if ([NSThread isMainThread]) {
        self.internalMaxCountForAllRenderedCaches = (maxCount >= 0) ? maxCount : TIPMaxCountForAllRenderedCachesDefault;
        [self pruneAllCachesOfType:TIPImageCacheTypeRendered withPriorityCache:nil];
    } else {
        tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            self.maxCountForAllRenderedCaches = maxCount;
        });
    }
}

- (SInt16)maxCountForAllRenderedCaches
{
    if (![NSThread isMainThread]) {
        TIPLogWarning(@"Read %@ from %@ off the main thread!", NSStringFromSelector(_cmd), NSStringFromClass([self class]));
    }
    return self.internalMaxCountForAllRenderedCaches;
}

- (void)setMaxBytesForAllMemoryCaches:(SInt64)maxBytes
{
    tip_dispatch_async_autoreleasing(_queueForMemoryCaches, ^{
        self.internalMaxBytesForAllMemoryCaches = (maxBytes >= 0ll) ? maxBytes : _MaxBytesForAllMemoryCachesDefaultValue();
        [self pruneAllCachesOfType:TIPImageCacheTypeMemory withPriorityCache:nil];
    });
}

- (SInt64)maxBytesForAllMemoryCaches
{
    __block SInt64 maxBytes;
    dispatch_sync(_queueForMemoryCaches, ^{
        maxBytes = self.internalMaxBytesForAllMemoryCaches;
    });
    return maxBytes;
}

- (void)setMaxCountForAllMemoryCaches:(SInt16)maxCount
{
    tip_dispatch_async_autoreleasing(_queueForMemoryCaches, ^{
        self.internalMaxCountForAllMemoryCaches = (maxCount >= 0) ? maxCount : TIPMaxCountForAllMemoryCachesDefault;
        [self pruneAllCachesOfType:TIPImageCacheTypeMemory withPriorityCache:nil];
    });
}

- (SInt16)maxCountForAllMemoryCaches
{
    __block SInt16 maxCount;
    dispatch_sync(_queueForMemoryCaches, ^{
        maxCount = self.internalMaxCountForAllMemoryCaches;
    });
    return maxCount;
}

- (void)setMaxBytesForAllDiskCaches:(SInt64)maxBytes
{
    tip_dispatch_async_autoreleasing(_queueForDiskCaches, ^{
        self.internalMaxBytesForAllDiskCaches = (maxBytes >= 0ll) ? maxBytes : _MaxBytesForAllDiskCachesDefaultValue();
        [self pruneAllCachesOfType:TIPImageCacheTypeDisk withPriorityCache:nil];
    });
}

- (SInt64)maxBytesForAllDiskCaches
{
    __block SInt64 maxBytes;
    tip_dispatch_sync_autoreleasing(_queueForDiskCaches, ^{
        maxBytes = self.internalMaxBytesForAllDiskCaches;
    });
    return maxBytes;
}

- (void)setMaxCountForAllDiskCaches:(SInt16)maxCount
{
    tip_dispatch_async_autoreleasing(_queueForDiskCaches, ^{
        self.internalMaxCountForAllDiskCaches = (maxCount >= 0) ? maxCount : TIPMaxCountForAllDiskCachesDefault;
        [self pruneAllCachesOfType:TIPImageCacheTypeDisk withPriorityCache:nil];
    });
}

- (SInt16)maxCountForAllDiskCaches
{
    __block SInt16 maxCount;
    dispatch_sync(_queueForDiskCaches, ^{
        maxCount = self.internalMaxCountForAllDiskCaches;
    });
    return maxCount;
}

- (SInt64)totalBytesForAllRenderedCaches
{
    if (![NSThread isMainThread]) {
        TIPLogWarning(@"Read %@ from %@ off the main thread!", NSStringFromSelector(_cmd), NSStringFromClass([self class]));

    }
    return self.internalTotalBytesForAllRenderedCaches;
}

- (SInt16)totalCountForAllRenderedCaches
{
    if (![NSThread isMainThread]) {
        TIPLogWarning(@"Read %@ from %@ off the main thread!", NSStringFromSelector(_cmd), NSStringFromClass([self class]));

    }
    return self.internalTotalCountForAllRenderedCaches;
}

- (SInt64)totalBytesForAllMemoryCaches
{
    __block SInt64 totalBytes;
    dispatch_sync(_queueForMemoryCaches, ^{
        totalBytes = self.internalTotalBytesForAllMemoryCaches;
    });
    return totalBytes;
}

- (SInt16)totalCountForAllMemoryCaches
{
    __block SInt16 totalCount;
    dispatch_sync(_queueForMemoryCaches, ^{
        totalCount = self.internalTotalCountForAllMemoryCaches;
    });
    return totalCount;
}

- (SInt64)totalBytesForAllDiskCaches
{
    __block SInt64 totalBytes;
    dispatch_sync(_queueForDiskCaches, ^{
        totalBytes = self.internalTotalBytesForAllDiskCaches;
    });
    return totalBytes;
}

- (SInt16)totalCountForAllDiskCaches
{
    __block SInt16 totalCount;
    dispatch_sync(_queueForDiskCaches, ^{
        totalCount = self.internalTotalCountForAllDiskCaches;
    });
    return totalCount;
}

#pragma mark Instance Methods

- (void)clearAllDiskCaches
{
    [[TIPImagePipeline allRegisteredImagePipelines] enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, TIPImagePipeline * _Nonnull pipeline, BOOL * _Nonnull stop) {
        [pipeline clearDiskCache];
    }];
}

- (void)clearAllMemoryCaches
{
    [[TIPImagePipeline allRegisteredImagePipelines] enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, TIPImagePipeline * _Nonnull pipeline, BOOL * _Nonnull stop) {
        [pipeline clearMemoryCaches];
    }];
}

- (void)clearAllRenderedMemoryCaches
{
    [[TIPImagePipeline allRegisteredImagePipelines] enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, TIPImagePipeline * _Nonnull pipeline, BOOL * _Nonnull stop) {
        [pipeline.renderedCache clearAllImages:NULL];
    }];
}

- (void)clearAllRenderedMemoryCacheImagesWithIdentifier:(NSString *)identifier
{
    [[TIPImagePipeline allRegisteredImagePipelines] enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, TIPImagePipeline * _Nonnull pipeline, BOOL * _Nonnull stop) {
        [pipeline clearRenderedMemoryCacheImageWithIdentifier:identifier];
    }];
}

- (void)dirtyAllRenderedMemoryCacheImagesWithIdentifier:(NSString *)identifier
{
    [[TIPImagePipeline allRegisteredImagePipelines] enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, TIPImagePipeline * _Nonnull pipeline, BOOL * _Nonnull stop) {
        [pipeline dirtyRenderedMemoryCacheImageWithIdentifier:identifier];
    }];
}

#pragma mark Observing

- (void)addImagePipelineObserver:(id<TIPImagePipelineObserver>)observer
{
    tip_dispatch_barrier_async_autoreleasing(_globalObserversQueue, ^{
        [self->_globalObservers addObject:observer];
    });
}

- (void)removeImagePipelineObserver:(id<TIPImagePipelineObserver>)observer
{
    tip_dispatch_barrier_async_autoreleasing(_globalObserversQueue, ^{
        [self->_globalObservers removeObject:observer];
    });
}

- (NSArray<id<TIPImagePipelineObserver>> *)allImagePipelineObservers
{
    __block NSArray<id<TIPImagePipelineObserver>> *observers;
    tip_dispatch_sync_autoreleasing(_globalObserversQueue, ^{
        observers = self->_globalObservers.allObjects;
    });
    return observers;
}

#pragma mark Project Dispatch Methods

- (dispatch_queue_t)queueForCachesOfType:(TIPImageCacheType)type
{
    switch (type) {
        case TIPImageCacheTypeMemory:
            return _queueForMemoryCaches;
        case TIPImageCacheTypeDisk:
            return _queueForDiskCaches;
        case TIPImageCacheTypeRendered:
        default:
            return dispatch_get_main_queue();
    }
}

#pragma mark Project Instance Methods

- (SInt16)internalMaxCountForAllCachesOfType:(TIPImageCacheType)type
{
    switch (type) {
        case TIPImageCacheTypeRendered:
            return self.internalMaxCountForAllRenderedCaches;
        case TIPImageCacheTypeMemory:
            return self.internalMaxCountForAllMemoryCaches;
        case TIPImageCacheTypeDisk:
            return self.internalMaxCountForAllDiskCaches;
    }
    return 0;
}

- (SInt16)internalTotalCountForAllCachesOfType:(TIPImageCacheType)type
{
    switch (type) {
        case TIPImageCacheTypeRendered:
            return self.internalTotalCountForAllRenderedCaches;
        case TIPImageCacheTypeMemory:
            return self.internalTotalCountForAllMemoryCaches;
        case TIPImageCacheTypeDisk:
            return self.internalTotalCountForAllDiskCaches;
    }
    return 0;
}

- (SInt64)internalMaxBytesForAllCachesOfType:(TIPImageCacheType)type
{
    switch (type) {
        case TIPImageCacheTypeRendered:
            return self.internalMaxBytesForAllRenderedCaches;
        case TIPImageCacheTypeMemory:
            return self.internalMaxBytesForAllMemoryCaches;
        case TIPImageCacheTypeDisk:
            return self.internalMaxBytesForAllDiskCaches;
    }
    return 0;
}

- (SInt64)internalTotalBytesForAllCachesOfType:(TIPImageCacheType)type
{
    switch (type) {
        case TIPImageCacheTypeRendered:
            return self.internalTotalBytesForAllRenderedCaches;
        case TIPImageCacheTypeMemory:
            return self.internalTotalBytesForAllMemoryCaches;
        case TIPImageCacheTypeDisk:
            return self.internalTotalBytesForAllDiskCaches;
    }
    return 0;
}

- (SInt64)internalMaxBytesForCacheEntryOfType:(TIPImageCacheType)type
{
    const SInt64 maxBytes = [self internalMaxBytesForAllCachesOfType:type];
    if (maxBytes < 0) {
        // negative == unlimited
        return INT64_MAX;
    }

    // if on the main thread, accept potentially stale max ratio size by using nonatomic access
    NSInteger ratio = [NSThread isMainThread] ? _maxRatioSizeOfCacheEntry : self.maxRatioSizeOfCacheEntry;

    if (ratio < 0) {
        // negative == use default
        ratio = TIPMaxRatioSizeOfCacheEntryDefault;
    }

    if (ratio <= 1) {
        // 0 or 1 == no maximium ratio, aka, no max bytes
        return INT64_MAX;
    }

    return maxBytes / (SInt64)ratio;
}

- (void)enqueueImagePipelineOperation:(NSOperation *)op
{
    [_sharedImagePipelineQueue addOperation:op];
}

- (void)postProblem:(NSString *)problemName userInfo:(NSDictionary<NSString *, id> *)userInfo
{
    id<TIPProblemObserver> observer = self.problemObserver;
    if (observer && [observer respondsToSelector:@selector(tip_problemWasEncountered:userInfo:)]) {
        [observer tip_problemWasEncountered:problemName userInfo:userInfo];
    }
}

- (void)accessedCGContext:(BOOL)seriallyAccessed duration:(NSTimeInterval)duration isMainThread:(BOOL)mainThread
{
    id<TIPProblemObserver> observer = self.problemObserver;
    if (observer && [observer respondsToSelector:@selector(tip_CGContextAccessed:serially:fromMainThread:)]) {
        [observer tip_CGContextAccessed:duration serially:seriallyAccessed fromMainThread:mainThread];
    }
}

#pragma mark Max Bytes

- (SInt64)internalMaxBytesForDiskCacheEntry
{
    return [self internalMaxBytesForCacheEntryOfType:TIPImageCacheTypeDisk];
}

- (SInt64)internalMaxBytesForMemoryCacheEntry
{
    return [self internalMaxBytesForCacheEntryOfType:TIPImageCacheTypeMemory];
}

- (SInt64)internalMaxBytesForRenderedCacheEntry
{
    return [self internalMaxBytesForCacheEntryOfType:TIPImageCacheTypeRendered];
}

#pragma mark Project Class Methods

- (void)pruneAllCachesOfType:(TIPImageCacheType)type withPriorityCache:(nullable id<TIPImageCache>)priorityCache
{
    const SInt64 globalMaxBytes = [self internalMaxBytesForAllCachesOfType:type];
    const SInt16 globalMaxCount = [self internalMaxCountForAllCachesOfType:type];
    [self pruneAllCachesOfType:type
             withPriorityCache:priorityCache
              toGlobalMaxBytes:globalMaxBytes
              toGlobalMaxCount:globalMaxCount];
}

- (void)pruneAllCachesOfType:(TIPImageCacheType)type
           withPriorityCache:(nullable id<TIPImageCache>)priorityCache
            toGlobalMaxBytes:(SInt64)globalMaxBytes
            toGlobalMaxCount:(SInt16)globalMaxCount
{
    @autoreleasepool {
        switch (type) {
            case TIPImageCacheTypeRendered:
            case TIPImageCacheTypeMemory:
            case TIPImageCacheTypeDisk:
                break;
            default:
                TIPAssertNever();
                return;
        }

        TIPAssert(globalMaxBytes >= 0);
        TIPAssert(globalMaxCount >= 0);

        // max bytes of 0 == disable the cache
        if (globalMaxBytes == 0) {
            // leave as 0
        }

        // max count of 0 == unlimited
        if (globalMaxCount == 0) {
            globalMaxCount = INT16_MAX;
        }

        NSArray<TIPImagePipeline *> *allPipelines = nil;
        NSInteger knownTotalEntries = -1;
        NSInteger knownPriorityEntries = 0;
        if (priorityCache) {
            TIPLRUCache *manifest = (TIPImageCacheTypeDisk == type) ? [(TIPImageDiskCache *)priorityCache diskCache_syncAccessManifest] : priorityCache.manifest;
            knownPriorityEntries = (NSInteger)manifest.numberOfEntries;
        }

        // Remove entries from the non-priority caches to alleviate memory pressure
        while (([self internalTotalBytesForAllCachesOfType:type] > globalMaxBytes || [self internalTotalCountForAllCachesOfType:type] > globalMaxCount) && knownTotalEntries != knownPriorityEntries) {

            if (!allPipelines) {
                // lazy load
                allPipelines = [[TIPImagePipeline allRegisteredImagePipelines] allValues];
            }

            // Only load knownTotalEntries once
            const BOOL getKnownTotalEntries = knownTotalEntries < 0;
            if (getKnownTotalEntries) {
                knownTotalEntries = 0;
            }

            // Ditch the oldest entry for all non-priority caches
            for (TIPImagePipeline *pipeline in allPipelines) {
                id<TIPImageCache> cache = [pipeline cacheOfType:type];
                if (cache) {
                    TIPLRUCache *manifest = (TIPImageCacheTypeDisk == type) ? [(TIPImageDiskCache *)cache diskCache_syncAccessManifest] : cache.manifest;
                    if (getKnownTotalEntries) {
                        knownTotalEntries += manifest.numberOfEntries;
                    }

                    if (cache != priorityCache) {
                        if ([manifest removeTailEntry]) {
                            knownTotalEntries--;
                        }
                    }
                }
            }

        }

        // If we still have too much data being consumed, start removing entries from the priority cache
        while (([self internalTotalBytesForAllCachesOfType:type] > globalMaxBytes || [self internalTotalCountForAllCachesOfType:type] > globalMaxCount) && knownPriorityEntries > 0) {
            [priorityCache.manifest removeTailEntry];
            knownPriorityEntries--;
        }

#if DEBUG
        if ([self internalTotalBytesForAllCachesOfType:type] > globalMaxBytes || [self internalTotalCountForAllCachesOfType:type] > globalMaxCount) {
            NSString *typeStr = nil;
            switch (type) {
                case TIPImageCacheTypeRendered:
                    typeStr = @"Rendered Cache";
                    break;
                case TIPImageCacheTypeMemory:
                    typeStr = @"Memory Cache";
                    break;
                case TIPImageCacheTypeDisk:
                    typeStr = @"Disk Cache";
                    break;
            }
            TIPLogWarning(@"We cleared as many entries from %@s as we could and still are over the cap", typeStr);
        }
#endif
    }
}

#pragma mark Runtime Methods

- (void)setAssertsEnabled:(BOOL)assertsEnabled
{
    gTwitterImagePipelineAssertEnabled = assertsEnabled;
}

- (BOOL)areAssertsEnabled
{
    return gTwitterImagePipelineAssertEnabled;
}

- (void)setLogger:(nullable id<TIPLogger>)logger
{
    gTIPLogger = logger;
    self.internalLogger = logger;
}

- (nullable id<TIPLogger>)logger
{
    return self.internalLogger;
}

#pragma mark Download Methods

- (id<TIPImageFetchDownload>)createImageFetchDownloadWithContext:(id<TIPImageFetchDownloadContext>)context
{
    id<TIPImageFetchDownloadProvider> imageFetchDownloadProvider = self.imageFetchDownloadProvider;
    TIPAssert(imageFetchDownloadProvider != nil);
    id<TIPImageFetchDownload> download = [imageFetchDownloadProvider imageFetchDownloadWithContext:context];
    if (context != download.context) {
        NSDictionary *userInfo;
        if (imageFetchDownloadProvider) {
            userInfo = @{ @"className" :  NSStringFromClass([imageFetchDownloadProvider class]) };
        }
        @throw [NSException exceptionWithName:TIPImageFetchDownloadConstructorExceptionName
                                       reason:@"TIPImageFetchDownload did not adhere to protocol requirements!"
                                     userInfo:userInfo];
    }
    return download;
}

- (void)setImageFetchDownloadProvider:(nullable id<TIPImageFetchDownloadProvider>)imageFetchDownloadProvider
{
    if (!imageFetchDownloadProvider) {
        if ([_imageFetchDownloadProvider class] == [TIPImageFetchDownloadProviderInternal class]) {
            imageFetchDownloadProvider = _imageFetchDownloadProvider;
        } else {
            imageFetchDownloadProvider = [[TIPImageFetchDownloadProviderInternal alloc] init];
        }
    }
    TIPAssert([imageFetchDownloadProvider conformsToProtocol:@protocol(TIPImageFetchDownloadProvider)]);

    if (_imageFetchDownloadProvider == imageFetchDownloadProvider) {
        return;
    }

    const BOOL supportsStubbing = [imageFetchDownloadProvider respondsToSelector:@selector(setDownloadStubbingEnabled:)] && [imageFetchDownloadProvider conformsToProtocol:@protocol(TIPImageFetchDownloadProviderWithStubbingSupport)];

    if (_imageFetchDownloadProviderSupportsStubbing) {
        [(id<TIPImageFetchDownloadProviderWithStubbingSupport>)_imageFetchDownloadProvider removeAllDownloadStubs];
        [(id<TIPImageFetchDownloadProviderWithStubbingSupport>)_imageFetchDownloadProvider setDownloadStubbingEnabled:NO];
    }

    if (supportsStubbing) {
        [(id<TIPImageFetchDownloadProviderWithStubbingSupport>)imageFetchDownloadProvider removeAllDownloadStubs];
        [(id<TIPImageFetchDownloadProviderWithStubbingSupport>)imageFetchDownloadProvider setDownloadStubbingEnabled:YES];
    }

    _imageFetchDownloadProviderSupportsStubbing = NO;
    _imageFetchDownloadProvider = imageFetchDownloadProvider;
    _imageFetchDownloadProviderSupportsStubbing = supportsStubbing;
}

@end

@implementation TIPGlobalConfiguration (Inspect)

- (void)getAllFetchOperations:(out NSArray<TIPImageFetchOperation *> * __nullable * __nullable)fetchOpsOut
           allStoreOperations:(out NSArray<TIPImageStoreOperation *> * __nullable * __nullable)storeOpsOut
{
    NSMutableArray<TIPImageFetchOperation *> *fetchOps = [[NSMutableArray alloc] init];
    NSMutableArray<TIPImageStoreOperation *> *storeOps = [[NSMutableArray alloc] init];

    for (NSOperation *op in _sharedImagePipelineQueue.operations) {
        if ([op isKindOfClass:[TIPImageFetchOperation class]]) {
            [fetchOps addObject:(id)op];
        } else if ([op isKindOfClass:[TIPImageStoreOperation class]]) {
            [storeOps addObject:(id)op];
        }
    }

    if (fetchOpsOut) {
        *fetchOpsOut = [fetchOps copy];
    }
    if (storeOpsOut) {
        *storeOpsOut = [storeOps copy];
    }
}

- (void)inspect:(TIPGlobalConfigurationInspectionCallback)callback
{
    NSMutableDictionary<NSString *, TIPImagePipeline *> *pipelines = [[TIPImagePipeline allRegisteredImagePipelines] mutableCopy];
    NSMutableDictionary<NSString *, TIPImagePipelineInspectionResult *> *results = [NSMutableDictionary dictionaryWithCapacity:pipelines.count];

    _Inspect(pipelines, results, callback);
}

static void _Inspect(NSMutableDictionary<NSString *, TIPImagePipeline *> *remainingPipelines,
                     NSMutableDictionary<NSString *, TIPImagePipelineInspectionResult *> *gatheredResults,
                     TIPGlobalConfigurationInspectionCallback callback)
{
    NSString *identifier = remainingPipelines.allKeys.firstObject;
    if (!identifier) {
        callback(gatheredResults);
        return;
    }

    TIPImagePipeline *pipeline = remainingPipelines[identifier];
    [remainingPipelines removeObjectForKey:identifier];
    [pipeline inspect:^(TIPImagePipelineInspectionResult *result) {
        if (result) {
            gatheredResults[identifier] = result;
        }
        _Inspect(remainingPipelines,
                 gatheredResults,
                 callback);
    }];
}

@end

NS_ASSUME_NONNULL_END
