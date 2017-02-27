//
//  TIPGlobalConfiguration.h
//  TwitterImagePipeline
//
//  Created on 10/1/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 Default max bytes for rendered caches.
 Resolves to being the greater of `System RAM / 12` or `64 MBs`
 */
FOUNDATION_EXTERN SInt64 const TIPMaxBytesForAllRenderedCachesDefault;
/**
 Default max bytes for memory caches.
 Resolves to being the greater of `System RAM / 12` or `64 MBs`
 */
FOUNDATION_EXTERN SInt64 const TIPMaxBytesForAllMemoryCachesDefault;
//! Default max bytes for disk caches.  `128 MBs`
FOUNDATION_EXTERN SInt64 const TIPMaxBytesForAllDiskCachesDefault;
//! Default max number of concurrent image downloads.  `4`
FOUNDATION_EXTERN NSInteger const TIPMaxConcurrentImagePipelineDownloadCountDefault;
//! Default maximum estimated time for detached _HTTP/1.1_ downloads before cancel. `3.0 seconds`
FOUNDATION_EXTERN NSTimeInterval const TIPMaxEstimatedTimeRemainingForDetachedHTTPDownloadsDefault;
//! Default maximum size of a cache entry by ratio to the cache max size.  `1:6` - `1/6th` the size
FOUNDATION_EXTERN NSUInteger const TIPMaxRatioSizeOfCacheEntryDefault;

//! Default max count for all memory caches to hold. `INT16_MAX >> 6` (511)
FOUNDATION_EXTERN SInt16 const TIPMaxCountForAllMemoryCachesDefault;
//! Default max count for all rendered caches to hold. `INT16_MAX >> 6` (511)
FOUNDATION_EXTERN SInt16 const TIPMaxCountForAllRenderedCachesDefault;
//! Default max count for all disk caches to hold. `INT16_MAX >> 4` (2044)
FOUNDATION_EXTERN SInt16 const TIPMaxCountForAllDiskCachesDefault;

//! block for providing the estimated bitrate using the given _domain_
typedef int64_t(^TIPEstimatedBitrateProviderBlock)(NSString * __nonnull domain);

@protocol TIPImagePipelineObserver;
@protocol TIPImageFetchDownloadProvider;
@protocol TIPLogger;
@protocol TIPProblemObserver;

/**
 The global configuration for __Twitter Image Pipeline__ which affects all `TIPImagePipeline`
 instances.

 ## Constants

    // Equivalent to one-twelfth of the devices RAM (capped to 64 MB).
    // This is an arbitrary choice a.t.m.
    FOUNDATION_EXTERN NSUInteger const TIPMaxBytesForAllRenderedCachesDefault;

    // Equivalent to one-twelfth of the devices RAM (capped to 64 MB).
    // This is an arbitrary choice a.t.m.
    FOUNDATION_EXTERN NSUInteger const TIPMaxBytesForAllMemoryCachesDefault;

    // Equivalent to 128 MB.
    // This is an arbitrary choice a.t.m.
    FOUNDATION_EXTERN NSUInteger const TIPMaxBytesForAllDiskCachesDefault;

    // Default is 4 concurrent operations
    FOUNDATION_EXTERN NSInteger const TIPMaxConcurrentImagePipelineDownloadCountDefault;

    // Equivalent to 3 seconds.  This is an arbitrary choice a.t.m.
    FOUNDATION_EXTERN NSTimeInterval const TIPMaxEstimatedTimeRemainingForDetachedHTTPDownloadsDefault;
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
 The maximum number of bytes that all memory image caches can store in memory across all
 `TIPImagePipeline` instances.

 Negative is Default, 0 is off, positive is the specified number of bytes
 */
@property (atomic) SInt64 maxBytesForAllMemoryCaches;

/**
 The maximum number of bytes that all disk image caches can store on disk across all
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
 The maximum number of images that all memory image caches can store in memory across all
 `TIPImagePipeline` instances.

 0 is unlimited,
 positive is the specified number of images,
 Default (or negative) = `TIPMaxCountForAllMemoryCachesDefault`
 */
@property (atomic) SInt16 maxCountForAllMemoryCaches;

/**
 The maximum number of images that all disk image caches can store on disk across all
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
 Asynchronously clear the memory cache and rendered cache of all registered `TIPImagePipeline`
 instances.
 */
- (void)clearAllMemoryCaches;

#pragma mark Downloads

/**
 The maximum time (estimated) that a `TIPImagePipeline` will permit a download to continue after all
 associated `TIPImageFetchOperation` instances have been disassociated (from `cancel`).

 Since HTTP/1.1 does not support cancelling a request mid-flight without closing a connection,
 it is often more efficient to let a download complete so that the connection can be kept alive with
 its enlarged window sizes.

 Since SPDY and HTTP/2 support cancellation, if it can be detected that we are running over one of
 these modern protocols, we will always cancel the download when all associated
 `TIPImageFetchOperation` instances are disassociated (aka cancelled).

 Default == `3.0` seconds.
 `0.0` seconds (or negative) == disabled (all downloads will be cancelled and connections closed over
 HTTP/1.1)
 */
@property (atomic) NSTimeInterval maxEstimatedTimeRemainingForDetachedHTTPDownloads;

/**
 A block that will be called anytime an external opinion on the download bitrate is needed by a
 `TIPImagePipeline`.
 In particular, this block will be used to inform an image download on whether or not it should be
 cancelled or continue to download after it has disassociated from all related operations (via
 `cancel`).  It can be the case that there isn't enough information to determine the bitrate of a
 download from the bytes that have been downloaded at that point in time, so an outside opinion will
 be consulted to make the best choice.
 If the block is `NULL`, or returns a negative value, the estimated bandwidth will be treated as
 _unknown_.
 @note Reminder that bitrate is in _bits per second_ (aka _bps).
 To convert from _bytes per second_ (aka _Bps_) to _bps_, just multiply the _Bps_ by `8`.
 */
@property (atomic, copy, nullable) TIPEstimatedBitrateProviderBlock estimatedBitrateProviderBlock;

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
- (void)addImagePipelineObserver:(nonnull id<TIPImagePipelineObserver>)observer;

/**
 Remove a global observer.
 */
- (void)removeImagePipelineObserver:(nonnull id<TIPImagePipelineObserver>)observer;

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
 Details: All memory caches are cleared but only half of all rendered caches' images are cleared.
          This is to avoid flashing images in the UI on app foreground.

 Default == `NO`
 */
@property (nonatomic, readwrite, getter=isClearMemoryCachesOnApplicationBackgroundEnabled) BOOL clearMemoryCachesOnApplicationBackgroundEnabled;

#pragma mark Singleton Accessor

/**
 Accessor to the shared instance
 */
+ (nonnull instancetype)sharedInstance;

/** `NS_UNAVAILABLE` */
- (nonnull instancetype)init NS_UNAVAILABLE;
/** `NS_UNAVAILABLE` */
+ (nonnull instancetype)new NS_UNAVAILABLE;

@end

#pragma mark - TIPGlobalConfiguration extended support

@class TIPImagePipelineInspectionResult;

//! The callback providing all the inspection results for every registered `TIPImagePipeline`
typedef void(^TIPGlobalConfigurationInspectionCallback)(NSDictionary<NSString *, TIPImagePipelineInspectionResult*> * __nonnull results);

/**
 Category for inspecting all `TIPImagePipeline` instances.  See `TIPImagePipeline(Inspect)` also.
 */
@interface TIPGlobalConfiguration (Inspect)

/**
 Asynchronously inspect all `TIPImagePipeline` instances to gather information about them.

 @param callback A callback to be called with an `NSDictionary` of image pipeline identifers as keys
 and `TIPImagePipelineInspectionResult` objects as values.
 */
- (void)inspect:(nonnull TIPGlobalConfigurationInspectionCallback)callback;

@end
