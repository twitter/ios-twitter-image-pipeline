//
//  TIPGlobalConfiguration.h
//  TwitterImagePipeline
//
//  Created on 10/1/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <CoreGraphics/CGContext.h>
#import <Foundation/Foundation.h>

@class TIPImageFetchOperation;
@class TIPImageStoreOperation;

NS_ASSUME_NONNULL_BEGIN

/**
 Default max bytes for rendered caches.
 Resolves to being the lesser of `System RAM / 12` or `160 MBs`
 */
FOUNDATION_EXTERN SInt64 const TIPMaxBytesForAllRenderedCachesDefault;
//! Default max bytes for memory caches. `48 MBs`
FOUNDATION_EXTERN SInt64 const TIPMaxBytesForAllMemoryCachesDefault;
//! Default max bytes for disk caches.  `128 MBs`
FOUNDATION_EXTERN SInt64 const TIPMaxBytesForAllDiskCachesDefault;
//! Default max number of concurrent image downloads.  `4`
FOUNDATION_EXTERN NSInteger const TIPMaxConcurrentImagePipelineDownloadCountDefault;
//! Default maximum size of a cache entry by ratio to the cache max size.  `1:6` - `1/6th` the size
FOUNDATION_EXTERN NSUInteger const TIPMaxRatioSizeOfCacheEntryDefault;

//! Default max count for all memory caches to hold. `INT16_MAX >> 7` (255)
FOUNDATION_EXTERN SInt16 const TIPMaxCountForAllMemoryCachesDefault;
//! Default max count for all rendered caches to hold. `INT16_MAX >> 7` (255)
FOUNDATION_EXTERN SInt16 const TIPMaxCountForAllRenderedCachesDefault;
//! Default max count for all disk caches to hold. `INT16_MAX >> 4` (2044)
FOUNDATION_EXTERN SInt16 const TIPMaxCountForAllDiskCachesDefault;

@protocol TIPImagePipelineObserver;
@protocol TIPImageFetchDownloadProvider;
@protocol TIPLogger;
@protocol TIPProblemObserver;

/**
 The global configuration for __Twitter Image Pipeline__ which affects all `TIPImagePipeline`
 instances.

 ## Constants

    // Equivalent to one-twelfth of the devices RAM (capped to 160 MB).
    // This is an arbitrary choice a.t.m.
    FOUNDATION_EXTERN NSUInteger const TIPMaxBytesForAllRenderedCachesDefault;

    // Equivalent to 48 MB.
    // This is an arbitrary choice a.t.m.
    FOUNDATION_EXTERN NSUInteger const TIPMaxBytesForAllMemoryCachesDefault;

    // Equivalent to 128 MB.
    // This is an arbitrary choice a.t.m.
    FOUNDATION_EXTERN NSUInteger const TIPMaxBytesForAllDiskCachesDefault;

    // Default is 4 concurrent operations
    FOUNDATION_EXTERN NSInteger const TIPMaxConcurrentImagePipelineDownloadCountDefault;
 */
@interface TIPGlobalConfiguration : NSObject

#pragma mark Caches

/**
 The maximum number of bytes that all rendered image caches can store in memory across all
 `TIPImagePipeline` instances.

 Negative is Default, 0 is off, positive is the specified number of bytes
 */
@property (atomic) SInt64 maxBytesForAllRenderedCaches;

/**
 The maximum number of bytes that all in-memory image data caches can store in memory across all
 `TIPImagePipeline` instances.

 Negative is Default, 0 is off, positive is the specified number of bytes
 */
@property (atomic) SInt64 maxBytesForAllMemoryCaches;

/**
 The maximum number of bytes that all on-disk image data caches can store on disk across all
 `TIPImagePipeline` instances.

 Negative is Default, 0 is off, positive is the specified number of bytes
 */
@property (atomic) SInt64 maxBytesForAllDiskCaches;

/**
 The maximum number of images that all rendered image caches can store in memory across all
 `TIPImagePipeline` instances.

 0 is unlimited,
 positive is the specified number of images,
 Default (or negative) = `TIPMaxCountForAllRenderedCachesDefault`
 */
@property (atomic) SInt16 maxCountForAllRenderedCaches;

/**
 The maximum number of images that all in-memory image data caches can store in memory across all
 `TIPImagePipeline` instances.

 0 is unlimited,
 positive is the specified number of images,
 Default (or negative) = `TIPMaxCountForAllMemoryCachesDefault`
 */
@property (atomic) SInt16 maxCountForAllMemoryCaches;

/**
 The maximum number of images that all on-disk image data caches can store on disk across all
 `TIPImagePipeline` instances.

 0 is unlimited,
 positive is the specified number of images,
 Default (or negative) = `TIPMaxCountForAllDiskCachesDefault`
 */
@property (atomic) SInt16 maxCountForAllDiskCaches;

/**
 The maximum ratio size of an entry in its respective cache.
 The ratio is `1 / x` where `x` is `maxRatioSizeOfCacheEntry` and the ratio is applied to the cache.
 For example: if a cache has a maximum number of bytes at 64 MBs,
 then a `maxRatioSizeOfCacheEntry` set to `8` will equate to _64 / 8 = 8 MBs_ max per entry in that
 cache.

 Negative is Default, `0` or `1` indicate no maximum.
 Default is `6` (so max size is _1/6th_ of the max cache size).
 */
@property (atomic) NSInteger maxRatioSizeOfCacheEntry;

/** Total bytes across all `TIPImagePipeline` rendered caches */
@property (atomic, readonly) SInt64 totalBytesForAllRenderedCaches;
/** Total bytes across all `TIPImagePipeline` memory caches */
@property (atomic, readonly) SInt64 totalBytesForAllMemoryCaches;
/** Total bytes across all `TIPImagePipeline` disk caches */
@property (atomic, readonly) SInt64 totalBytesForAllDiskCaches;

/**
 Asynchronously clear the disk cache of all registered `TIPImagePipeline` instances.
 */
- (void)clearAllDiskCaches;

/**
 Asynchronously clear the in-memory image data cache and rendered cache of all registered
 `TIPImagePipeline` instances.
 */
- (void)clearAllMemoryCaches;

/**
 Clear the rendered cache of all registered `TIPImagePipeline` instances. Synchronously if called
 from the main thread, asynchronously otherwise.
 */
- (void)clearAllRenderedMemoryCaches;

/** Quickly purge a specific rendered image */
- (void)clearAllRenderedMemoryCacheImagesWithIdentifier:(NSString *)identifier;

/** Mark a specific rendered image as dirty */
- (void)dirtyAllRenderedMemoryCacheImagesWithIdentifier:(NSString *)identifier;

#pragma mark Downloads

/**
 The `TIPImageFetchDownloadProvider` to use with __TIP__.
 By default, __TIP__ will use an internal implementation, that will vend `TIPImageFetchDownload`
 instances built using `NSURLSession`.
 Provide a custom `TIPImageFetchDownloadProvider` that vends custom `TIPImageFetchDownload`
 instances to override the downloading behavior of images with __TIP__.
 Provide a custom `TIPImageFetchDownloadProviderWithStubbingSupport` if stubbing is desired.
 See `TIPImageFetchDownload.h`
 @note Not thread safe, consumer should always call from the same thread.
 */
@property (nonatomic, null_resettable) id<TIPImageFetchDownloadProvider> imageFetchDownloadProvider;

/**
 Maximum number of concurrent network downloads that all `TIPImagePipeline` instances can run
 */
@property (atomic) NSInteger maxConcurrentImagePipelineDownloadCount;

#pragma mark Observing

/**
 Add a global observer to all image pipelines.  Observers are weakly held.

 Callbacks are not synchronized, that is the responsibility of the observer.
 */
- (void)addImagePipelineObserver:(id<TIPImagePipelineObserver>)observer;

/**
 Remove a global observer.
 */
- (void)removeImagePipelineObserver:(id<TIPImagePipelineObserver>)observer;

#pragma mark Runtime Configuration

/**
 Configure the delegate for log messages within the *TwitterImagePipeline*

 Default == `nil`
 */
@property (atomic, readwrite, nullable) id<TIPLogger> logger;

/**
 Configure the delegate for problems that are encountered within *TwitterImagePipeline*

 Default == `nil`
 */
@property (atomic, readwrite, nullable) id<TIPProblemObserver> problemObserver;

/**
 Configure whether or not to execute asserts within the *TwitterImagePipeline*

 Default == `YES`
 */
@property (nonatomic, readwrite, getter=areAssertsEnabled) BOOL assertsEnabled;

/**
 Configure whether or not methods in `UIImage+TIPAdditions.h` will serialize all CGContext access to
 a queue. Doing this helps reduce race conditions where multiple access to do heavy CoreGraphics
 work leads to memory pressure that can cause a memory access signal (crash) or a complete
 out-of-memory termination of the app.  Disable this feature to increase paralellism while taking on
 the risks of increased memory utilization.

 The queue can be accessed for convenience, such as with custom codecs, via
 `TIPExecuteCGContextBlock`
 Default == `YES`
 */
@property (nonatomic, readwrite) BOOL serializeCGContextAccess;

/**
 Configure whether or not to clear memory caches in *TIP* on app being backgrounded.
 Details: All memory caches are cleared.
          Any render cache images that persist (are not deallocated) via separate references
          (such as a view with a strong reference to it) will be repopulated to the rendered cache
          on app foreground - this will balance memory purging with keeping the UI correct on app resume.

 Default == `NO`
 */
@property (nonatomic, readwrite, getter=isClearMemoryCachesOnApplicationBackgroundEnabled) BOOL clearMemoryCachesOnApplicationBackgroundEnabled;

/**
 The default `CGInterpolationQuality` when scaling an image if a quality was not provided.
 Default == `CGInterpolationQualityDefault`
 */
@property (nonatomic, readwrite) CGInterpolationQuality defaultInterpolationQuality;

/**
 Configure whether the default codecs in TIPImageCodecCatalogue are loaded synchronously by
 the calling thread (which can incur long pauses as it makes XPC calls) or are loaded asynchronously.
 */
@property (nonatomic, readwrite) BOOL loadCodecsAsync;

#pragma mark Singleton Accessor

/**
 Accessor to the shared instance
 */
+ (instancetype)sharedInstance;

/** `NS_UNAVAILABLE` */
- (instancetype)init NS_UNAVAILABLE;
/** `NS_UNAVAILABLE` */
+ (instancetype)new NS_UNAVAILABLE;

@end

#pragma mark - TIPGlobalConfiguration extended support

@class TIPImagePipelineInspectionResult;

//! The callback providing all the inspection results for every registered `TIPImagePipeline`
typedef void(^TIPGlobalConfigurationInspectionCallback)(NSDictionary<NSString *, TIPImagePipelineInspectionResult*> *results);

/**
 Category for inspecting all `TIPImagePipeline` instances.  See `TIPImagePipeline(Inspect)` also.
 */
@interface TIPGlobalConfiguration (Inspect)

/**
 Asynchronously inspect all `TIPImagePipeline` instances to gather information about them.

 @param callback A callback to be called with an `NSDictionary` of image pipeline identifers as keys
 and `TIPImagePipelineInspectionResult` objects as values.
 */
- (void)inspect:(TIPGlobalConfigurationInspectionCallback)callback;

/**
 Get all the running TIP operations.  Provide `NULL` to skip an output.
 */
- (void)getAllFetchOperations:(out NSArray<TIPImageFetchOperation *> * __nullable * __nullable)fetchOpsOut
           allStoreOperations:(out NSArray<TIPImageStoreOperation *> * __nullable * __nullable)storeOpsOut;

@end

NS_ASSUME_NONNULL_END
