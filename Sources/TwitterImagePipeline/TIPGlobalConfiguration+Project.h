//
//  TIPGlobalConfiguration+Project.h
//  TwitterImagePipeline
//
//  Created on 10/1/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPGlobalConfiguration.h"
#import "TIPImageCache.h"

@protocol TIPImageFetchDownload;
@protocol TIPImageFetchDownloadContext;

NS_ASSUME_NONNULL_BEGIN

@interface TIPGlobalConfiguration ()

// only accessible from queueForDiskCaches
@property (tip_nonatomic_direct) SInt16 internalMaxCountForAllDiskCaches;
@property (tip_nonatomic_direct) SInt64 internalMaxBytesForAllDiskCaches;
@property (tip_nonatomic_direct) SInt64 internalMaxBytesForDiskCacheEntry;
@property (tip_nonatomic_direct) SInt16 internalTotalCountForAllDiskCaches;
@property (tip_nonatomic_direct) SInt64 internalTotalBytesForAllDiskCaches;

// only accessible from queueForMemoryCaches
@property (tip_nonatomic_direct) SInt16 internalMaxCountForAllMemoryCaches;
@property (tip_nonatomic_direct) SInt64 internalMaxBytesForAllMemoryCaches;
@property (tip_nonatomic_direct) SInt64 internalMaxBytesForMemoryCacheEntry;
@property (tip_nonatomic_direct) SInt16 internalTotalCountForAllMemoryCaches;
@property (tip_nonatomic_direct) SInt64 internalTotalBytesForAllMemoryCaches;

// only accessible from main thread
@property (tip_nonatomic_direct) SInt16 internalMaxCountForAllRenderedCaches;
@property (tip_nonatomic_direct) SInt64 internalMaxBytesForAllRenderedCaches;
@property (tip_nonatomic_direct) SInt64 internalMaxBytesForRenderedCacheEntry;
@property (tip_nonatomic_direct) SInt16 internalTotalCountForAllRenderedCaches;
@property (tip_nonatomic_direct) SInt64 internalTotalBytesForAllRenderedCaches;

// shared queues
// The TIP caches can execute a LOT of Cocoa code which can pile up with autoreleases.
// Since queues don't immediately clear their autorelease pools, the time when these objects
// will be disposed is undefined and can be very long lived.
// Given the amount of large objects in TIP (images), we will be agressive with our autoreleasing
// and will use `tip_dispatch_[a]sync_autoreleasing` functions to wrap TIP cache queue block
// execution with `@autoreleasepool`.
@property (nonatomic, readonly) dispatch_queue_t queueForMemoryCaches;
@property (nonatomic, readonly) dispatch_queue_t queueForDiskCaches;
- (dispatch_queue_t)queueForCachesOfType:(TIPImageCacheType)type;

// other properties
@property (tip_atomic_direct, copy, readonly) NSArray<id<TIPImagePipelineObserver>> *allImagePipelineObservers;
@property (tip_atomic_direct, nullable, strong) id<TIPLogger> internalLogger;
@property (tip_nonatomic_direct, readonly) BOOL imageFetchDownloadProviderSupportsStubbing;

// per cache type accessors
- (SInt16)internalMaxCountForAllCachesOfType:(TIPImageCacheType)type;
- (SInt16)internalTotalCountForAllCachesOfType:(TIPImageCacheType)type;
- (SInt64)internalMaxBytesForAllCachesOfType:(TIPImageCacheType)type;
- (SInt64)internalTotalBytesForAllCachesOfType:(TIPImageCacheType)type;
- (SInt64)internalMaxBytesForCacheEntryOfType:(TIPImageCacheType)type;

// methods

- (void)enqueueImagePipelineOperation:(NSOperation *)op TIP_OBJC_DIRECT;

- (void)postProblem:(NSString *)problemName
           userInfo:(NSDictionary<NSString *, id> *)userInfo TIP_OBJC_DIRECT;
- (void)accessedCGContext:(BOOL)seriallyAccessed
                 duration:(NSTimeInterval)duration
             isMainThread:(BOOL)mainThread TIP_OBJC_DIRECT;

 // must call from correct queue (queueForMemoryCaches for memory caches, queueForDiskCaches for disk caches and main queue for rendered caches)
- (void)pruneAllCachesOfType:(TIPImageCacheType)type
           withPriorityCache:(nullable id<TIPImageCache>)priorityCache TIP_OBJC_DIRECT;
- (void)pruneAllCachesOfType:(TIPImageCacheType)type
           withPriorityCache:(nullable id<TIPImageCache>)priorityCache
            toGlobalMaxBytes:(SInt64)globalMaxBytes
            toGlobalMaxCount:(SInt16)globalMaxCount TIP_OBJC_DIRECT;

- (id<TIPImageFetchDownload>)createImageFetchDownloadWithContext:(id<TIPImageFetchDownloadContext>)context TIP_OBJC_DIRECT;

@end

NS_ASSUME_NONNULL_END
