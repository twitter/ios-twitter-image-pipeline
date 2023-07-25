//
//  TIPImageFetchOperation.m
//  TwitterImagePipeline
//
//  Created on 3/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#include <objc/runtime.h>
#include <stdatomic.h>

#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageCacheEntry.h"
#import "TIPImageDiskCache.h"
#import "TIPImageDiskCacheTemporaryFile.h"
#import "TIPImageDownloader.h"
#import "TIPImageFetchDelegate.h"
#import "TIPImageFetchDownload.h"
#import "TIPImageFetchMetrics+Project.h"
#import "TIPImageFetchOperation+Project.h"
#import "TIPImageFetchProgressiveLoadingPolicies.h"
#import "TIPImageFetchRequest.h"
#import "TIPImageFetchTransformer.h"
#import "TIPImageMemoryCache.h"
#import "TIPImagePipeline+Project.h"
#import "TIPImageRenderedCache.h"
#import "TIPPartialImage.h"
#import "TIPTiming.h"
#import "UIImage+TIPAdditions.h"

NSErrorDomain const TIPImageFetchErrorDomain = @"TIPImageFetchErrorDomain";
NSErrorDomain const TIPImageStoreErrorDomain = @"TIPImageStoreErrorDomain";
NSErrorDomain const TIPErrorDomain = @"TIPErrorDomain";
TIPErrorInfoKey TIPErrorInfoHTTPStatusCodeKey = @"httpStatusCode";

NS_ASSUME_NONNULL_BEGIN

typedef void(^TIPBoolBlock)(BOOL boolVal);
typedef void(^TIPImageFetchDelegateWorkBlock)(id<TIPImageFetchDelegate> __nullable  delegate);

static NSQualityOfService ConvertNSOperationQueuePriorityToQualityOfService(NSOperationQueuePriority pri);

#if __LP64__ || (TARGET_OS_EMBEDDED && !TARGET_OS_IPHONE) || TARGET_OS_WIN32 || NS_BUILD_32_LIKE_64
#define TIPImageFetchOperationState_Unaligned_AtomicT volatile atomic_int_fast64_t
#define TIPImageFetchOperationState_AtomicT TIPImageFetchOperationState_Unaligned_AtomicT __attribute__((aligned(8)))
#else
#define TIPImageFetchOperationState_Unaligned_AtomicT volatile atomic_int_fast32_t
#define TIPImageFetchOperationState_AtomicT TIPImageFetchOperationState_Unaligned_AtomicT __attribute__((aligned(4)))
#endif

@interface TIPImageFetchDownloadRequest : NSObject <TIPImageDownloadRequest>

// Populated on init
@property (nonatomic, readonly, nullable) NSURL *imageDownloadURL;
@property (nonatomic, copy, readonly, nullable) NSString *imageDownloadIdentifier;

// Manually set (set once)
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *imageDownloadHeaders;
@property (nonatomic) TIPImageFetchOptions imageDownloadOptions;
@property (nonatomic) NSTimeInterval imageDownloadTTL;
@property (nonatomic, nullable, copy) TIPImageFetchHydrationBlock imageDownloadHydrationBlock;
@property (nonatomic, nullable, copy) TIPImageFetchAuthorizationBlock imageDownloadAuthorizationBlock;
@property (nonatomic, nullable, copy) NSDictionary<NSString *, id> *decoderConfigMap;
@property (nonatomic) CGSize targetDimensions;
@property (nonatomic) UIViewContentMode targetContentMode;

// Manually set
@property (atomic, nullable, copy) NSString *imageDownloadLastModified;
@property (atomic, nullable) TIPPartialImage *imageDownloadPartialImageForResuming;
@property (atomic, nullable) TIPImageDiskCacheTemporaryFile *imageDownloadTemporaryFileForResuming;
@property (nonatomic) NSOperationQueuePriority imageDownloadPriority;

// init
- (instancetype)initWithRequest:(id<TIPImageFetchRequest>)fetchRequest;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

TIP_OBJC_FINAL TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageFetchDelegateDeallocHandler : NSObject
- (instancetype)initWithFetchOperation:(TIPImageFetchOperation *)operation
                              delegate:(id<TIPImageFetchDelegate>)delegate;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (void)invalidate;
@end

TIP_OBJC_FINAL TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageFetchOperationNetworkStepContext : NSObject
@property (nonatomic, nullable) TIPImageFetchDownloadRequest *imageDownloadRequest;
@property (nonatomic, nullable) id<TIPImageDownloadContext> imageDownloadContext;
@end

@interface TIPImageFetchResultInternal : NSObject <TIPImageFetchResult>
+ (nullable TIPImageFetchResultInternal *)resultWithImageContainer:(nullable TIPImageContainer *)imageContainer
                                                        identifier:(nullable NSString *)identifier
                                                        loadSource:(TIPImageLoadSource)source
                                                               URL:(nullable NSURL *)URL
                                                originalDimensions:(CGSize)originalDimensions
                                                       placeholder:(BOOL)placeholder
                                                       transformed:(BOOL)transformed TIP_OBJC_DIRECT;
@end

@implementation TIPImageFetchOperationNetworkStepContext
@end

@interface TIPImageFetchOperation () <TIPImageDownloadDelegate>

@property (atomic, nullable, weak) id<TIPImageFetchDelegate> delegate;
#pragma twitter startignorestylecheck
@property (tip_atomic_direct, nullable, strong) id<TIPImageFetchDelegate> strongDelegate;
#pragma twitter endignorestylecheck
@property (tip_atomic_direct, nullable, weak) TIPImageFetchDelegateDeallocHandler *delegateHandler;
@property (nonatomic) TIPImageFetchOperationState state;

@property (nonatomic) float progress;
@property (tip_nonatomic_direct, nullable) NSError *operationError;

@property (tip_nonatomic_direct, nullable) id<TIPImageFetchResult> previewResult;
@property (tip_nonatomic_direct, nullable) id<TIPImageFetchResult> progressiveResult;
@property (tip_nonatomic_direct, nullable) id<TIPImageFetchResult> finalResult;

@property (tip_nonatomic_direct, nullable) TIPImageContainer *previewImageContainerRaw;
@property (tip_nonatomic_direct, nullable) TIPImageContainer *finalImageContainerRaw;

@property (nonatomic, nullable) NSError *error;
@property (nonatomic, nullable, copy) NSString *networkLoadImageType;
@property (nonatomic) CGSize networkImageOriginalDimensions;

// Private
- (void)_extractBasicRequestInfo TIP_OBJC_DIRECT;
- (void)_initializeDelegate:(nullable id<TIPImageFetchDelegate>)delegate TIP_OBJC_DIRECT;
- (void)_clearDelegateHandler TIP_OBJC_DIRECT;
- (void)_hydrateNewContext:(TIPImageCacheEntryContext *)context
                  imageURL:(NSURL *)imageURL
               placeholder:(BOOL)placeholder TIP_OBJC_DIRECT;

@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageFetchOperation (Background)

// Start/Abort
- (void)_background_start;
- (BOOL)_background_shouldAbort;

// Generate State
- (void)_background_extractObservers;
- (void)_background_extractAdvancedRequestInfo;
- (void)_background_extractTargetInfo;
- (void)_background_extractStorageInfo;
- (void)_background_validateProgressiveSupportWithPartialImage:(TIPPartialImage *)partialImage;
- (void)_background_clearNetworkContextVariables;
- (void)_background_setFinalStateAfterFlushingDelegate:(TIPImageFetchOperationState)state;

// Load
- (void)_background_dispatchLoadStarted:(TIPImageLoadSource)source;
- (void)_background_loadFromNextSource;
- (void)_background_loadFromMemory;
- (void)_background_loadFromDisk;
- (void)_background_loadFromOtherPipelineDisk;
- (void)_background_loadFromAdditional;
- (void)_background_loadFromNextAdditionalCache:(NSMutableArray<id<TIPImageAdditionalCache>> *)caches
                                       imageURL:(NSURL *)imageURL;
- (void)_background_loadFromNetwork;

// Update
- (void)_background_updateFailureToLoadFinalImage:(NSError *)error
                                    updateMetrics:(BOOL)updateMetrics;
- (void)_background_updateProgress:(float)progress;
- (void)_background_updateFinalImage:(TIPImageContainer *)image
                           imageData:(nullable NSData *)imageData
                       renderLatency:(NSTimeInterval)imageRenderLatency
                                 URL:(NSURL *)URL
                          loadSource:(TIPImageLoadSource)source
                    networkImageType:(nullable NSString *)networkImageType
                    networkByteCount:(NSUInteger)networkByteCount
                         placeholder:(BOOL)placeholder;
- (void)_background_updatePreviewImageWithCacheEntry:(TIPImageCacheEntry *)cacheEntry
                                          loadSource:(TIPImageLoadSource)source;
- (void)_background_updateProgressiveImage:(UIImage *)image
                               transformed:(BOOL)transformed
                             renderLatency:(NSTimeInterval)imageRenderLatency
                                       URL:(NSURL *)URL
                                  progress:(float)progress
                        sourcePartialImage:(TIPPartialImage *)sourcePartialImage
                                loadSource:(TIPImageLoadSource)source;
- (void)_background_updateFirstAnimatedImageFrame:(UIImage *)image
                                    renderLatency:(NSTimeInterval)imageRenderLatency
                                              URL:(NSURL *)URL
                                         progress:(float)progress
                               sourcePartialImage:(TIPPartialImage *)sourcePartialImage
                                       loadSource:(TIPImageLoadSource)source;
- (void)_background_handleCompletedMemoryEntry:(TIPImageMemoryCacheEntry *)entry;
- (void)_background_handlePartialMemoryEntry:(TIPImageMemoryCacheEntry *)entry;
- (void)_background_handleCompletedDiskEntry:(TIPImageDiskCacheEntry *)entry;
- (void)_background_handlePartialDiskEntry:(TIPImageDiskCacheEntry *)entry
        tryOtherPipelineDiskCachesIfNeeded:(BOOL)tryOtherPipelineDiskCachesIfNeeded;

// Render Progress
- (void)_background_processContinuedPartialEntry:(TIPPartialImage *)partialImage
                                             URL:(NSURL *)URL
                                      loadSource:(TIPImageLoadSource)source;
- (nullable UIImage *)_background_getNextProgressiveImageWithAppendResult:(TIPImageDecoderAppendResult)appendResult
                                                             partialImage:(TIPPartialImage *)partialImage
                                                              renderCount:(NSUInteger)renderCount;
- (nullable UIImage *)_background_getFirstFrameOfAnimatedImageIfNotYetProvided:(TIPPartialImage *)partialImage;
- (UIImage *)_background_transformAndScaleImage:(UIImage *)image
                                       progress:(float)progress
                                   didTransform:(nonnull out BOOL *)transformedOut;
- (TIPImageContainer *)_background_transformAndScaleImageContainer:(TIPImageContainer *)imageContainer
                                                          progress:(float)progress
                                                      didTransform:(nonnull out BOOL *)transformedOut;

// Create Cache Entry
- (nullable TIPImageCacheEntry *)_background_createCacheEntryUsingRawImage:(BOOL)useRawImage
                                                     permitPreviewFallback:(BOOL)permitPreviewFallback
                                                               didFallback:(nullable out BOOL *)didFallbackToPreviewOut;
- (nullable TIPImageCacheEntry *)_background_createCacheEntryFromPartialImage:(TIPPartialImage *)partialImage
                                                                 lastModified:(NSString *)lastModified
                                                                     imageURL:(NSURL *)imageURL;

// Cache propagation
- (void)_background_propagateFinalImageData:(nullable NSData *)imageData
                                 loadSource:(TIPImageLoadSource)source;
- (void)_background_propagateFinalRenderedImage:(TIPImageLoadSource)source;
- (void)_background_propagatePartialImage:(TIPPartialImage *)partialImage
                             lastModified:(NSString *)lastModified
                               wasResumed:(BOOL)wasResumed; // source is always the network
- (void)_background_propagatePreviewImage:(TIPImageLoadSource)source;

// Notifications
- (void)_background_postDidStart;
- (void)_background_postDidFinish;
- (void)_background_postDidStartDownload;
- (void)_background_postDidFinishDownloadingImageOfType:(NSString *)imageType
                                            sizeInBytes:(NSUInteger)sizeInBytes;

// Execute
- (void)_background_executeDelegateWork:(TIPImageFetchDelegateWorkBlock)block;
- (void)_executeBackgroundWork:(dispatch_block_t)block;

@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageFetchOperation (DiskCache)

- (void)_diskCache_loadFromOtherPipelines:(NSArray<TIPImagePipeline *> *)pipelines
                            startMachTime:(uint64_t)startMachTime;
- (BOOL)_diskCache_attemptLoadFromOtherPipelineDisk:(TIPImagePipeline *)nextPipeline
                                      startMachTime:(uint64_t)startMachTime;
- (void)_diskCache_completeLoadFromOtherPipelineDisk:(nullable TIPImagePipeline *)pipeline
                                      imageContainer:(nullable TIPImageContainer *)imageContainer
                                                 URL:(nullable NSURL *)URL
                                             latency:(NSTimeInterval)latency
                                         placeholder:(BOOL)placeholder;

@end

// If this fails, the atomic ivar will no longer be valid
TIPStaticAssert(sizeof(TIPImageFetchOperationState_Unaligned_AtomicT) == sizeof(TIPImageFetchOperationState), enum_size_missmatch);

@implementation TIPImageFetchOperation
{
    // iVars
    dispatch_queue_t _backgroundQueue;
    TIPImageFetchMetrics *_metricsInternal;
    TIPImageFetchOperationState_AtomicT _state;
    uint64_t _enqueueTime;
    uint64_t _startTime;
    uint64_t _finishTime;

    // Fetch info
    CGSize _targetDimensions;
    UIViewContentMode _targetContentMode;
    TIPImageFetchLoadingSources _loadingSources;
    NSDictionary<NSString *, id<TIPImageFetchProgressiveLoadingPolicy>> *_progressiveLoadingPolicies;
    id<TIPImageFetchProgressiveLoadingPolicy> _progressiveLoadingPolicy;
    id<TIPImageFetchTransformer> _transformer;
    NSString *_transfomerIdentifier;
    NSArray<id<TIPImagePipelineObserver>> *_observers;
    NSDictionary<NSString *, id> *_decoderConfigMap;

    // Network
    TIPImageFetchOperationNetworkStepContext *_networkContext;
    NSUInteger _progressiveRenderCount;

    // Priority
    NSOperationQueuePriority _enqueuedPriority;

    // Flags
    struct {
        BOOL cancelled:1;
        BOOL isEarlyCompletion:1;
        BOOL invalidRequest:1;
        BOOL wasEnqueued:1;
        BOOL didStart:1;
        BOOL didReceiveFirstByte:1;
        BOOL shouldJumpToResumingDownload:1;
        BOOL wasResumedDownload:1;
        BOOL progressivePermissionValidated:1;
        BOOL permitsProgressiveLoading:1;
        BOOL delegateSupportsAttemptWillStartCallbacks:1;
        BOOL didExtractStorageInfo:1;
        BOOL didExtractTargetInfo:1;
        BOOL didReceiveFirstAnimatedFrame:1;
        BOOL transitioningToFinishedState:1;
        BOOL progressiveImageWasTransformed:1;
        BOOL previewImageWasTransformed:1;
        BOOL finalImageWasTransformed:1;
        BOOL shouldSkipRenderedCacheStore:1;
    } _flags;
}

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (instancetype)initWithImagePipeline:(TIPImagePipeline *)pipeline
                              request:(id<TIPImageFetchRequest>)request
                             delegate:(id<TIPImageFetchDelegate>)delegate
{
    if (self = [super init]) {
        _imagePipeline = pipeline;
        _request = request;
        _metricsInternal = [[TIPImageFetchMetrics alloc] initProject];
        _targetContentMode = UIViewContentModeCenter;

        _backgroundQueue = dispatch_queue_create("image.fetch.queue", DISPATCH_QUEUE_SERIAL);
        atomic_init(&_state, TIPImageFetchOperationStateIdle);
        _networkContext = [[TIPImageFetchOperationNetworkStepContext alloc] init];

        [self _initializeDelegate:delegate];
        [self _extractBasicRequestInfo];
    }
    return self;
}

- (void)_initializeDelegate:(nullable id<TIPImageFetchDelegate>)delegate
{
    _delegate = delegate;
    _flags.delegateSupportsAttemptWillStartCallbacks = ([delegate respondsToSelector:@selector(tip_imageFetchOperation:willAttemptToLoadFromSource:)] != NO);
    if (!delegate) {
        // nil delegate, just let the operation happen
    } else if ([delegate isKindOfClass:[TIPSimpleImageFetchDelegate class]]) {
        _strongDelegate = delegate;
    } else {
        // associate an object to perform the cancel on dealloc of the delegate
        TIPImageFetchDelegateDeallocHandler *handler;
        handler = [[TIPImageFetchDelegateDeallocHandler alloc] initWithFetchOperation:self
                                                                             delegate:delegate];
        if (handler) {
            _delegateHandler = handler;
            // Use the reference as the unique key since a delegate could have multiple operations
            objc_setAssociatedObject(delegate, (__bridge const void *)(handler), handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

- (void)_clearDelegateHandler
{
    TIPImageFetchDelegateDeallocHandler *handler = self.delegateHandler;
    if (handler) {
        [handler invalidate];
        self.delegateHandler = nil;
        id<TIPImageFetchDelegate> delegate = self.delegate;
        if (delegate) {
            objc_setAssociatedObject(delegate, (__bridge const void *)(handler), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

- (void)_extractBasicRequestInfo
{
    _networkContext.imageDownloadRequest = [[TIPImageFetchDownloadRequest alloc] initWithRequest:_request];
    _loadingSources = [_request respondsToSelector:@selector(loadingSources)] ?
                        [_request loadingSources] :
                        TIPImageFetchLoadingSourcesAll;
    _decoderConfigMap = _networkContext.imageDownloadRequest.decoderConfigMap;
    _transformer = [_request respondsToSelector:@selector(transformer)] ? _request.transformer : nil;
    if ([_transformer respondsToSelector:@selector(tip_transformerIdentifier)]) {
        _transfomerIdentifier = [[_transformer tip_transformerIdentifier] copy];
        TIPAssert(_transfomerIdentifier.length > 0);
    }

    if (!self.imageURL || self.imageIdentifier.length == 0) {
        TIPLogError(@"Cannot fetch request, it is invalid.  URL = '%@', Identifier = '%@'", self.imageURL, self.imageIdentifier);
        _flags.invalidRequest = 1;
    }
}

#pragma mark State

- (nullable NSString *)transformerIdentifier
{
    return _transfomerIdentifier;
}

- (nullable NSString *)imageIdentifier
{
    return _networkContext.imageDownloadRequest.imageDownloadIdentifier;
}

- (nullable NSURL *)imageURL
{
    return _networkContext.imageDownloadRequest.imageDownloadURL;
}

- (NSTimeInterval)timeSpentIdleInQueue
{
    __block NSTimeInterval ti;
    dispatch_sync(_backgroundQueue, ^{
        if (!self->_enqueueTime) {
            ti = 0;
        } else if (!self->_startTime) {
            ti = TIPComputeDuration(self->_enqueueTime, mach_absolute_time());
        } else {
            ti = TIPComputeDuration(self->_enqueueTime, self->_startTime);
        }
    });
    return ti;
}

- (NSTimeInterval)timeSpentExecuting
{
    __block NSTimeInterval ti;
    dispatch_sync(_backgroundQueue, ^{
        if (!self->_startTime) {
            ti = 0;
        } else if (!self->_finishTime) {
            ti = TIPComputeDuration(self->_startTime, mach_absolute_time());
        } else {
            ti = TIPComputeDuration(self->_startTime, self->_finishTime);
        }
    });
    return ti;
}

- (TIPImageFetchOperationState)state
{
    return atomic_load(&_state);
}

- (void)setState:(const TIPImageFetchOperationState)state
{
    // There are only 2 ways that the state is modified
    // 1) from the background thread during an async operation
    // 2) from the main thread on early completion
    // Since the mutation will never happen on multiple threads,
    // this method is not going to synchronize everything that is
    // executing (that is automatic by the nature of being called serially
    // from known threads); rather, just the setting of the _state will
    // be made atomic with atomic_store.
    // This will eliminate inconsistencies by ensuring exposed reads are
    // thread safe with atomic_load.

    TIPAssert(!!_flags.isEarlyCompletion == !![NSThread isMainThread]);
    const TIPImageFetchOperationState oldState = atomic_load(&_state);

    if (oldState == state) {
        return;
    }

    // Never go backwards
    if (state >= 0) {
        TIPAssert(state > oldState);
        if (state < oldState) {
            return;
        }
    }

    const BOOL finished = TIPImageFetchOperationStateIsFinished(state) != self.isFinished;
    const BOOL active = TIPImageFetchOperationStateIsActive(state) != self.isExecuting;
    const BOOL cancelled = (TIPImageFetchOperationStateCancelled == state) != self.isCancelled;

    if (finished) {
        [self willChangeValueForKey:@"isFinished"];
    }
    if (active) {
        [self willChangeValueForKey:@"isExecuting"];
    }
    if (cancelled) {
        [self willChangeValueForKey:@"isCancelled"];
    }
    atomic_store(&_state, state);
    if (cancelled) {
        [self didChangeValueForKey:@"isCancelled"];
    }
    if (active) {
        [self didChangeValueForKey:@"isExecuting"];
    }
    if (finished) {
        [self didChangeValueForKey:@"isFinished"];
        TIPLogDebug(@"Metrics: %@", self.metrics);

        // completion cleanup
        _transformer = nil; // leave _transformerIdentifier
        [self _clearDelegateHandler];
    }
}

- (void)setQueuePriority:(NSOperationQueuePriority)queuePriority
{
    // noop
}

- (NSOperationQueuePriority)queuePriority
{
    return _flags.wasEnqueued ? _enqueuedPriority : self.priority;
}

- (void)setQualityOfService:(NSQualityOfService)qualityOfService
{
    // noop
}

- (NSQualityOfService)qualityOfService
{
    return ConvertNSOperationQueuePriorityToQualityOfService(_flags.wasEnqueued ? _enqueuedPriority : self.priority);
}

- (void)setPriority:(NSOperationQueuePriority)priority
{
    if (_networkContext.imageDownloadRequest.imageDownloadPriority != priority) {

        const BOOL wasEnqueued = _flags.wasEnqueued; // cannot modify other NSOperation priorities if we've already been enqueued
        if (!wasEnqueued) {
            [self willChangeValueForKey:@"queuePriority"];
            [self willChangeValueForKey:@"qualityOfService"];
        }

        _networkContext.imageDownloadRequest.imageDownloadPriority = priority;

        if (!wasEnqueued) {
            [self didChangeValueForKey:@"qualityOfService"];
            [self didChangeValueForKey:@"queuePriority"];
        }

        [_imagePipeline.downloader updatePriorityOfContext:_networkContext.imageDownloadContext];
    }
}

- (NSOperationQueuePriority)priority
{
    return _networkContext.imageDownloadRequest.imageDownloadPriority;
}

#pragma mark Cancel

- (void)discardDelegate
{
    [self _clearDelegateHandler];
    self.delegate = nil;
    self.strongDelegate = nil;
}

- (void)cancel
{
    [self _executeBackgroundWork:^{
        if (!self->_flags.cancelled) {
            self->_flags.cancelled = 1;
            [self->_imagePipeline.downloader removeDelegate:self forContext:self->_networkContext.imageDownloadContext];
        }
    }];
}

- (void)cancelAndDiscardDelegate
{
    [self discardDelegate];
    [self cancel];
}

#pragma mark NSOperation

- (BOOL)isFinished
{
    return TIPImageFetchOperationStateIsFinished(atomic_load(&_state));
}

- (BOOL)isExecuting
{
    return TIPImageFetchOperationStateIsActive(atomic_load(&_state));
}

- (BOOL)isCancelled
{
    return TIPImageFetchOperationStateCancelled == atomic_load(&_state);
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isAsynchronous
{
    return YES;
}

- (void)start
{
    [self _executeBackgroundWork:^{
        if (!self->_flags.didStart) {
            self->_flags.didStart = 1;
            [self _background_start];
        }
    }];
}

- (void)completeOperationEarlyWithImageEntry:(TIPImageCacheEntry *)entry
                                 transformed:(BOOL)transformed
                       sourceImageDimensions:(CGSize)sourceDims
{
    TIPAssert([NSThread isMainThread]);
    TIPAssert(!_flags.didStart);
    TIPAssert(entry.completeImage != nil);
    TIPAssert(_metrics == nil);
    TIPAssert(_metricsInternal != nil);

    if (CGSizeEqualToSize(CGSizeZero, sourceDims)) {
        sourceDims = entry.completeImage.dimensions;
    }

    [self willEnqueue];
    _flags.didStart = 1;
    _flags.isEarlyCompletion = 1;
    TIPLogDebug(@"%@ %@, id=%@", NSStringFromSelector(_cmd), entry.completeImage, entry.identifier);

    _startTime = mach_absolute_time();
    self.state = TIPImageFetchOperationStateLoadingFromMemory;
    [self _executeBackgroundWork:^{
        [self _background_extractObservers];
        [self _background_postDidStart];
    }];
    id<TIPImageFetchDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_imageFetchOperationDidStart:)]) {
        [delegate tip_imageFetchOperationDidStart:self];
    }

    [_metricsInternal startWithSource:TIPImageLoadSourceMemoryCache];

    _networkContext = nil;
    self.finalImageContainerRaw = entry.completeImage;
    id<TIPImageFetchResult> finalResult = [TIPImageFetchResultInternal resultWithImageContainer:entry.completeImage
                                                                                     identifier:entry.identifier
                                                                                     loadSource:TIPImageLoadSourceMemoryCache
                                                                                            URL:entry.completeImageContext.URL
                                                                             originalDimensions:sourceDims
                                                                                    placeholder:entry.completeImageContext.treatAsPlaceholder
                                                                                    transformed:transformed];
    self.finalResult = finalResult;

    [_imagePipeline.memoryCache touchImageWithIdentifier:entry.identifier];
    [_imagePipeline.diskCache touchImageWithIdentifier:entry.identifier orSaveImageEntry:nil];

    [_metricsInternal finalWasHit:0.0 synchronously:YES];
    [_metricsInternal endSource];
    _metrics = _metricsInternal;
    _metricsInternal = nil;
    _finishTime = mach_absolute_time();

    TIPAssert(finalResult != nil);
    if (finalResult && [delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFinalImage:)]) {
        [delegate tip_imageFetchOperation:self didLoadFinalImage:finalResult];
    }
    [self _executeBackgroundWork:^{
        [self _background_postDidFinish];
    }];
    self.state = TIPImageFetchOperationStateSucceeded;
}

- (void)handleEarlyLoadOfDirtyImageEntry:(TIPImageCacheEntry *)entry
                             transformed:(BOOL)transformed
                   sourceImageDimensions:(CGSize)sourceDims
{
    TIPAssert([NSThread isMainThread]);
    TIPAssert(!_flags.didStart);
    TIPAssert(entry.completeImage != nil);
    TIPAssert(_metrics == nil);
    TIPAssert(_metricsInternal != nil);

    TIPLogDebug(@"%@ %@, id=%@", NSStringFromSelector(_cmd), entry.completeImage, entry.identifier);

    id<TIPImageFetchDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadDirtyPreviewImage:)]) {
        id<TIPImageFetchResult> result = [TIPImageFetchResultInternal resultWithImageContainer:entry.completeImage
                                                                                    identifier:entry.identifier
                                                                                    loadSource:TIPImageLoadSourceMemoryCache
                                                                                           URL:entry.completeImageContext.URL
                                                                            originalDimensions:sourceDims
                                                                                   placeholder:entry.completeImageContext.treatAsPlaceholder
                                                                                   transformed:transformed];
        [delegate tip_imageFetchOperation:self didLoadDirtyPreviewImage:result];
    }
}

- (void)willEnqueue
{
    TIPAssert(!_flags.wasEnqueued);
    _flags.wasEnqueued = 1;
    _enqueuedPriority = self.priority;
    _enqueueTime = mach_absolute_time();
}

- (BOOL)supportsLoadingFromRenderedCache
{
    if (_transformer && !_transfomerIdentifier) {
        return NO;
    }
    return [self supportsLoadingFromSource:TIPImageLoadSourceMemoryCache];
}

- (BOOL)supportsLoadingFromSource:(TIPImageLoadSource)source
{
    if (TIPImageLoadSourceUnknown == source) {
        return YES;
    }

    return TIP_BITMASK_HAS_SUBSET_FLAGS(_loadingSources, (1 << source));
}

#pragma mark Wait

- (void)waitUntilFinished
{
    [super waitUntilFinished];
}

- (void)waitUntilFinishedWithoutBlockingRunLoop
{
    // Default implementation is to block the thread until the execution completes.
    // This can deadlock if the caller is not careful and the completion queue or callback queue
    // are the same thread that waitUntilFinished are called from.
    // In this method, we'll pump the run loop until we're finished as a way to provide an alternative.

    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    if (!runLoop) {
        return [self waitUntilFinished];
    }

    while (!self.isFinished) {
        [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    }
}

#pragma mark Downloader Delegate

- (nullable dispatch_queue_t)imageDownloadDelegateQueue
{
    return _backgroundQueue;
}

- (id<TIPImageDownloadRequest>)imageDownloadRequest
{
    return _networkContext.imageDownloadRequest;
}

- (TIPImageDiskCacheTemporaryFile *)regenerateImageDownloadTemporaryFileForImageDownload:(id<TIPImageDownloadContext>)context
{
    TIPImageDiskCacheTemporaryFile *tempFile = [_imagePipeline.diskCache openTemporaryFileForImageIdentifier:self.imageIdentifier];
    TIPAssert(tempFile != nil);
    _networkContext.imageDownloadRequest.imageDownloadTemporaryFileForResuming = tempFile;
    return (TIPImageDiskCacheTemporaryFile * _Nonnull)tempFile; // TIPAssert() performed 2 lines above
}

- (void)imageDownloadDidStart:(id<TIPImageDownloadContext>)context
{
    [self _background_postDidStartDownload];
    const TIPPartialImage *partialImage = _networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming;
    const float progress = partialImage ? partialImage.progress : 0.0f;
    [self _background_updateProgress:progress];
}

- (void)imageDownload:(id<TIPImageDownloadContext>)context didResetFromPartialImage:(TIPPartialImage *)oldPartialImage
{
    TIPAssert(!_flags.didReceiveFirstByte);
    [self _background_clearNetworkContextVariables];
    if ([self supportsLoadingFromSource:TIPImageLoadSourceNetwork]) {
        [self _background_updateProgress:0.0f];
    } else {
        // Not configured to do a normal network load, fail
        NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                             code:TIPImageFetchErrorCodeCouldNotLoadImage
                                         userInfo:nil];
        [self _background_updateFailureToLoadFinalImage:error updateMetrics:YES];
        [_imagePipeline.downloader removeDelegate:self forContext:context];
    }
}

- (void)imageDownload:(id<TIPImageDownloadContext>)context
       didAppendBytes:(NSUInteger)byteCount
       toPartialImage:(TIPPartialImage *)partialImage
               result:(TIPImageDecoderAppendResult)result
{
    if ([self _background_shouldAbort]) {
        return;
    }

    if (!_flags.didReceiveFirstByte) {
        _flags.didReceiveFirstByte = 1;
        if (partialImage.byteCount > byteCount) {
            _flags.wasResumedDownload = YES;
            [_metricsInternal convertNetworkMetricsToResumedNetworkMetrics];
        }
    }

    _progressiveFrameCount = partialImage.frameCount;
    uint64_t startMachTime = mach_absolute_time();

    if (partialImage.type) {
        self.networkLoadImageType = partialImage.type;
    }

    if (TIPSizeEqualToZero(_networkImageOriginalDimensions) && !TIPSizeEqualToZero(partialImage.dimensions)) {
        self.networkImageOriginalDimensions = partialImage.dimensions;
    }

    // Progress

    const float progress = partialImage.progress;
    if (partialImage.isAnimated) {
        UIImage *image = [self _background_getFirstFrameOfAnimatedImageIfNotYetProvided:partialImage];
        const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
        if (image) {
            // First frame progress
            [self _background_updateFirstAnimatedImageFrame:image
                                              renderLatency:latency
                                                        URL:self.imageURL
                                                   progress:progress
                                         sourcePartialImage:partialImage
                                                 loadSource:(_flags.wasResumedDownload) ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork];
        }
    } else if (partialImage.isProgressive) {
        UIImage *image = [self _background_getNextProgressiveImageWithAppendResult:result
                                                                      partialImage:partialImage
                                                                       renderCount:_progressiveRenderCount];
        if (image) {
            // Progressive image progress
            BOOL transformed = NO;
            image = [self _background_transformAndScaleImage:image
                                                    progress:progress
                                                didTransform:&transformed];
            const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
            _progressiveRenderCount++;
            [self _background_updateProgressiveImage:image
                                         transformed:transformed
                                       renderLatency:latency
                                                 URL:self.imageURL
                                            progress:progress
                                  sourcePartialImage:partialImage
                                          loadSource:(_flags.wasResumedDownload) ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork];
        }
    }

    // Always update the plain ol' progress
    [self _background_updateProgress:progress];
}

- (void)imageDownload:(id<TIPImageDownloadContext>)context
        didCompleteWithPartialImage:(nullable TIPPartialImage *)partialImage
        lastModified:(nullable NSString *)lastModified
        byteSize:(NSUInteger)bytes
        imageType:(nullable NSString *)imageType
        image:(nullable TIPImageContainer *)image
        imageData:(nullable NSData *)imageData
        imageRenderLatency:(NSTimeInterval)latency
        statusCode:(NSInteger)statusCode
        error:(nullable NSError *)error
{
    const BOOL wasResuming = (_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming != nil);
    [self _background_clearNetworkContextVariables];
    _networkContext.imageDownloadContext = nil;

    id<TIPImageFetchDownload> download = (id<TIPImageFetchDownload>)context;
    [_metricsInternal addNetworkMetrics:[download respondsToSelector:@selector(downloadMetrics)] ? download.downloadMetrics : nil
                             forRequest:download.finalURLRequest
                              imageType:imageType
                       imageSizeInBytes:bytes
                        imageDimensions:(image) ? image.dimensions : partialImage.dimensions];

    if (partialImage && !image) {
        [self _background_propagatePartialImage:partialImage
                                   lastModified:lastModified
                                     wasResumed:wasResuming];
    }

    if ([self _background_shouldAbort]) {
        return;
    }

    if (image) {

        if (partialImage.hasGPSInfo) {
            // we should NEVER encounter an image with GPS info,
            // that would be a MAJOR security risk
            [[TIPGlobalConfiguration sharedInstance] postProblem:TIPProblemImageDownloadedHasGPSInfo
                                                        userInfo:@{ TIPProblemInfoKeyImageURL : self.imageURL }];
        }

        const BOOL placeholder = TIP_BITMASK_HAS_SUBSET_FLAGS(_networkContext.imageDownloadRequest.imageDownloadOptions, TIPImageFetchTreatAsPlaceholder);
        [self _background_updateFinalImage:image
                                 imageData:imageData // TODO: is this too much?  Could defer the caching of the data to memory until next disk cache hit
                             renderLatency:latency
                                       URL:self.imageURL
                                loadSource:(_flags.wasResumedDownload) ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork
                          networkImageType:imageType
                          networkByteCount:bytes
                               placeholder:placeholder];
    } else {
        TIPAssert(error != nil);

        if (wasResuming && 416 /* Requested range not satisfiable */ == statusCode) {
            TIPAssert(!_flags.wasResumedDownload);
            if (!_flags.wasResumedDownload) {
                TIPLogWarning(@"Network resume yielded HTTP 416... retrying with full network load: %@", _networkContext.imageDownloadRequest.imageDownloadURL);
                [self _background_loadFromNetwork];
                return;
            }
        }

        if (!error) {
            error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                        code:TIPImageFetchErrorCodeUnknown
                                    userInfo:nil];
        }

        [self _background_updateFailureToLoadFinalImage:error updateMetrics:YES];
    }
}

#pragma mark Helpers

- (void)_hydrateNewContext:(TIPImageCacheEntryContext *)context
                  imageURL:(NSURL *)imageURL
               placeholder:(BOOL)placeholder
{
    if (!imageURL) {
        imageURL = self.imageURL;
    }

    const TIPImageFetchOptions options = _networkContext.imageDownloadRequest.imageDownloadOptions;
    context.updateExpiryOnAccess = TIP_BITMASK_EXCLUDES_FLAGS(options, TIPImageFetchDoNotResetExpiryOnAccess);
    context.treatAsPlaceholder = placeholder;
    context.TTL = _networkContext.imageDownloadRequest.imageDownloadTTL;
    context.URL = imageURL;
    context.lastAccess = [NSDate date];
    if (context.TTL <= 0.0) {
        context.TTL = TIPTimeToLiveDefault;
    }
}

@end

@implementation TIPImageFetchOperation (Background)

#pragma mark Start / Abort

- (void)_background_start
{
    _startTime = mach_absolute_time();
    if ([self _background_shouldAbort]) {
        return;
    }

    self.state = TIPImageFetchOperationStateStarting;

    [self _background_extractObservers];

    [self _background_postDidStart];
    [self _background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate){
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperationDidStart:)]) {
            [delegate tip_imageFetchOperationDidStart:self];
        }
    }];

    [self _background_extractTargetInfo]; // now that we decode to the target sizing, extract early
    [self _background_extractAdvancedRequestInfo];
    [self _background_loadFromNextSource];
}

- (BOOL)_background_shouldAbort
{
    if (self.isFinished || _flags.transitioningToFinishedState) {
        return YES;
    }

    if (_flags.cancelled) {
        NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                             code:TIPImageFetchErrorCodeCancelled
                                         userInfo:nil];
        [self _background_updateFailureToLoadFinalImage:error updateMetrics:YES];
        return YES;
    }

    if (_flags.invalidRequest) {
        NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                             code:TIPImageFetchErrorCodeInvalidRequest
                                         userInfo:nil];
        [self _background_updateFailureToLoadFinalImage:error updateMetrics:NO];
        return YES;
    }

    return NO;
}

#pragma mark Generate State

- (void)_background_extractObservers
{
    _observers = [TIPGlobalConfiguration sharedInstance].allImagePipelineObservers;
    id<TIPImagePipelineObserver> pipelineObserver = self.imagePipeline.observer;
    if (pipelineObserver) {
        if (!_observers) {
            _observers = @[pipelineObserver];
        } else {
            _observers = [_observers arrayByAddingObject:pipelineObserver];
        }
    }
}

- (void)_background_extractStorageInfo
{
    if (_flags.didExtractStorageInfo) {
        return;
    }

    NSTimeInterval TTL = [_request respondsToSelector:@selector(timeToLive)] ?
                                [_request timeToLive] :
                                -1.0;
    if (TTL <= 0.0) {
        TTL = TIPTimeToLiveDefault;
    }
    _networkContext.imageDownloadRequest.imageDownloadTTL = TTL;

    const TIPImageFetchOptions options = [_request respondsToSelector:@selector(options)] ?
                                                [_request options] :
                                                TIPImageFetchNoOptions;
    _networkContext.imageDownloadRequest.imageDownloadOptions = options;
    _flags.shouldSkipRenderedCacheStore = TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageFetchSkipStoringToRenderedCache);

    _flags.didExtractStorageInfo = 1;
}

- (void)_background_extractAdvancedRequestInfo
{
    _networkContext.imageDownloadRequest.targetDimensions = _targetDimensions;
    _networkContext.imageDownloadRequest.targetContentMode = _targetContentMode;
    _networkContext.imageDownloadRequest.imageDownloadHydrationBlock = [_request respondsToSelector:@selector(imageRequestHydrationBlock)] ? _request.imageRequestHydrationBlock : nil;
    _networkContext.imageDownloadRequest.imageDownloadAuthorizationBlock = [_request respondsToSelector:@selector(imageRequestAuthorizationBlock)] ? _request.imageRequestAuthorizationBlock : nil;
    _progressiveLoadingPolicies = nil;
    id<TIPImageFetchDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:)]) {
        // could support progressive, prep the policy
        _progressiveLoadingPolicies = [_request respondsToSelector:@selector(progressiveLoadingPolicies)] ?
                                        [[_request progressiveLoadingPolicies] copy] :
                                        nil;
    }
}

- (void)_background_extractTargetInfo
{
    if (_flags.didExtractTargetInfo) {
        return;
    }

    _targetDimensions = [_request respondsToSelector:@selector(targetDimensions)] ?
                            [_request targetDimensions] :
                            CGSizeZero;
    _targetContentMode = [_request respondsToSelector:@selector(targetContentMode)] ?
                            [_request targetContentMode] :
                            UIViewContentModeCenter;

    _flags.didExtractTargetInfo = 1;
}

- (void)_background_validateProgressiveSupportWithPartialImage:(TIPPartialImage *)partialImage
{
    if (!_flags.progressivePermissionValidated) {
        if (partialImage.state > TIPPartialImageStateLoadingHeaders) {
            id<TIPImageFetchDelegate> delegate = self.delegate;
            if (partialImage.progressive && [delegate respondsToSelector:@selector(tip_imageFetchOperation:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:)]) {
                TIPAssert(partialImage.type != nil);
                _progressiveLoadingPolicy = _progressiveLoadingPolicies[partialImage.type ?: @""];
                if (!_progressiveLoadingPolicy) {
                    _progressiveLoadingPolicy = TIPImageFetchProgressiveLoadingPolicyDefaultPolicies()[partialImage.type ?: @""];
                }
                if (_progressiveLoadingPolicy) {
                    const BOOL shouldLoad = [delegate tip_imageFetchOperation:self
                                        shouldLoadProgressivelyWithIdentifier:self.imageIdentifier
                                                                          URL:self.imageURL
                                                                    imageType:partialImage.type
                                                           originalDimensions:partialImage.dimensions];
                    if (shouldLoad) {
                        _flags.permitsProgressiveLoading = 1;
                    }
                }
            }

            _flags.progressivePermissionValidated = 1;
        }
    }
}

- (void)_background_clearNetworkContextVariables
{
    _networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming = nil;
    _networkContext.imageDownloadRequest.imageDownloadLastModified = nil;
    _networkContext.imageDownloadRequest.imageDownloadTemporaryFileForResuming = nil;
    _progressiveRenderCount = 0;
}

- (void)_background_setFinalStateAfterFlushingDelegate:(TIPImageFetchOperationState)state
{
    TIPAssert(TIPImageFetchOperationStateIsFinished(state));
    _flags.transitioningToFinishedState = 1;
    [self _background_executeDelegateWork:^(id<TIPImageFetchDelegate> __unused delegate) {
        [self _executeBackgroundWork:^{
            self.state = state;
            self->_flags.transitioningToFinishedState = 0;
        }];
    }];
}

#pragma mark Load

- (void)_background_dispatchLoadStarted:(TIPImageLoadSource)source
{
    if (_flags.delegateSupportsAttemptWillStartCallbacks) {
        [self _background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate) {
            [delegate tip_imageFetchOperation:self
                  willAttemptToLoadFromSource:source];
        }];
    }
}

- (void)_background_loadFromNextSource
{
    if ([self _background_shouldAbort]) {
        return;
    }

    TIPImageLoadSource nextSource = TIPImageLoadSourceUnknown;
    const TIPImageFetchOperationState currentState = atomic_load(&_state);

    // Get the next loading source
    if (_flags.shouldJumpToResumingDownload && currentState < TIPImageFetchOperationStateLoadingFromNetwork) {
        nextSource = TIPImageLoadSourceNetwork;
    } else {
        switch (currentState) {
            case TIPImageFetchOperationStateIdle:
            case TIPImageFetchOperationStateStarting:
                nextSource = TIPImageLoadSourceMemoryCache;
                break;
            case TIPImageFetchOperationStateLoadingFromMemory:
                nextSource = TIPImageLoadSourceDiskCache;
                break;
            case TIPImageFetchOperationStateLoadingFromDisk:
                nextSource = TIPImageLoadSourceAdditionalCache;
                break;
            case TIPImageFetchOperationStateLoadingFromAdditionalCache:
                nextSource = TIPImageLoadSourceNetwork;
                break;
            case TIPImageFetchOperationStateLoadingFromNetwork:
                nextSource = TIPImageLoadSourceUnknown;
                break;
            case TIPImageFetchOperationStateCancelled:
            case TIPImageFetchOperationStateFailed:
            case TIPImageFetchOperationStateSucceeded:
                // nothing to do
                return;
        }
    }

    // Update the metrics
    if (currentState != TIPImageFetchOperationStateIdle && currentState != TIPImageFetchOperationStateStarting) {
        [_metricsInternal endSource];
    }
    if (TIPImageLoadSourceUnknown != nextSource) {
        [_metricsInternal startWithSource:nextSource];
    }

    // Load whatever's next (or set state to failed)
    switch (nextSource) {
        case TIPImageLoadSourceUnknown:
        {
            NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                                 code:TIPImageFetchErrorCodeCouldNotLoadImage
                                             userInfo:nil];
            [self _background_updateFailureToLoadFinalImage:error updateMetrics:NO];
            break;
        }
        case TIPImageLoadSourceMemoryCache:
            [self _background_loadFromMemory];
            break;
        case TIPImageLoadSourceDiskCache:
            [self _background_loadFromDisk];
            break;
        case TIPImageLoadSourceAdditionalCache:
            [self _background_loadFromAdditional];
            break;
        case TIPImageLoadSourceNetwork:
        case TIPImageLoadSourceNetworkResumed:
            [self _background_loadFromNetwork];
            break;
    }
}

- (void)_background_loadFromMemory
{
    self.state = TIPImageFetchOperationStateLoadingFromMemory;
    if (![self supportsLoadingFromSource:TIPImageLoadSourceMemoryCache]) {
        [self _background_loadFromNextSource];
        return;
    }

    [self _background_dispatchLoadStarted:TIPImageLoadSourceMemoryCache];

    TIPImageMemoryCacheEntry *entry = [_imagePipeline.memoryCache imageEntryForIdentifier:self.imageIdentifier
                                                                         targetDimensions:_targetDimensions
                                                                        targetContentMode:_targetContentMode
                                                                         decoderConfigMap:_decoderConfigMap];
    [self _background_handleCompletedMemoryEntry:entry];
}


- (void)_background_loadFromDisk
{
    self.state = TIPImageFetchOperationStateLoadingFromDisk;
    if (![self supportsLoadingFromSource:TIPImageLoadSourceDiskCache]) {
        [self _background_loadFromNextSource];
        return;
    }

    [self _background_dispatchLoadStarted:TIPImageLoadSourceDiskCache];

    // Just load the meta-data (options == TIPImageDiskCacheFetchOptionsNone)
    TIPImageDiskCacheEntry *entry;
    entry = [_imagePipeline.diskCache imageEntryForIdentifier:self.imageIdentifier
                                                      options:TIPImageDiskCacheFetchOptionsNone
                                             targetDimensions:_targetDimensions
                                            targetContentMode:_targetContentMode
                                             decoderConfigMap:_decoderConfigMap];
    [self _background_handleCompletedDiskEntry:entry];
}

- (void)_background_loadFromOtherPipelineDisk
{
    TIPAssert(self.state == TIPImageFetchOperationStateLoadingFromDisk);

    [self _background_extractStorageInfo]; // need TTL and options
    NSMutableDictionary<NSString *, TIPImagePipeline *> *pipelines = [[TIPImagePipeline allRegisteredImagePipelines] mutableCopy];
    [pipelines removeObjectForKey:_imagePipeline.identifier];
    NSArray<TIPImagePipeline *> *otherPipelines = [pipelines allValues];
    tip_dispatch_async_autoreleasing([TIPGlobalConfiguration sharedInstance].queueForDiskCaches, ^{
        [self _diskCache_loadFromOtherPipelines:otherPipelines startMachTime:mach_absolute_time()];
    });
}

- (void)_background_loadFromAdditional
{
    self.state = TIPImageFetchOperationStateLoadingFromAdditionalCache;
    if (![self supportsLoadingFromSource:TIPImageLoadSourceAdditionalCache]) {
        [self _background_loadFromNextSource];
        return;
    }

    [self _background_dispatchLoadStarted:TIPImageLoadSourceAdditionalCache];

    NSMutableArray<id<TIPImageAdditionalCache>> *additionalCaches = [_imagePipeline.additionalCaches mutableCopy];
    [self _background_loadFromNextAdditionalCache:additionalCaches
                                         imageURL:self.imageURL];
}

- (void)_background_loadFromNextAdditionalCache:(NSMutableArray<id<TIPImageAdditionalCache>> *)caches
                                       imageURL:(NSURL *)imageURL
{
    if (caches.count == 0) {
        [self _background_loadFromNextSource];
        return;
    }

    id<TIPImageAdditionalCache> nextCache = caches.firstObject;
    [caches removeObjectAtIndex:0];
    [nextCache tip_retrieveImageForURL:imageURL completion:^(UIImage *image) {
        [self _executeBackgroundWork:^{
            if ([self _background_shouldAbort]) {
                return;
            }

            if (image) {
                const BOOL placeholder = TIP_BITMASK_HAS_SUBSET_FLAGS(self->_networkContext.imageDownloadRequest.imageDownloadOptions, TIPImageFetchTreatAsPlaceholder);
                [self _background_updateFinalImage:[[TIPImageContainer alloc] initWithImage:image]
                                         imageData:nil
                                     renderLatency:0
                                               URL:imageURL
                                        loadSource:TIPImageLoadSourceAdditionalCache
                                  networkImageType:nil
                                  networkByteCount:0
                                       placeholder:placeholder];
            } else {
                [self _background_loadFromNextAdditionalCache:caches
                                                     imageURL:imageURL];
            }
        }];
    }];
}

- (void)_background_loadFromNetwork
{
    self.state = TIPImageFetchOperationStateLoadingFromNetwork;

    if (!_imagePipeline.downloader) {
        NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                             code:TIPImageFetchErrorCodeCouldNotDownloadImage
                                         userInfo:nil];
        [self _background_updateFailureToLoadFinalImage:error
                                          updateMetrics:YES];
        return;
    }

    if (![self supportsLoadingFromSource:TIPImageLoadSourceNetwork]) {
        if (![self supportsLoadingFromSource:TIPImageLoadSourceNetworkResumed] || !_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming) {
            // if full loads not OK and resuming not OK - fail
            NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                                 code:TIPImageFetchErrorCodeCouldNotLoadImage
                                             userInfo:nil];
            [self _background_updateFailureToLoadFinalImage:error
                                              updateMetrics:YES];
            return;
        } // else if full loads not OK, but resuming is OK - continue
    }

    // Start loading
    [self _background_extractStorageInfo];
    const TIPImageLoadSource loadSource = (_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming != nil) ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork;
    [self _background_dispatchLoadStarted:loadSource];
    _networkContext.imageDownloadContext = [_imagePipeline.downloader fetchImageWithDownloadDelegate:self];
}

#pragma mark Update

- (void)_background_updateFailureToLoadFinalImage:(NSError *)error
                                    updateMetrics:(BOOL)updateMetrics
{
    TIPAssert(error != nil);
    TIPAssert(_metrics == nil);
    TIPAssert(_metricsInternal != nil);
    TIPLogDebug(@"Failed to Load Image: %@", @{ @"id" : self.imageIdentifier ?: @"<null>",
                                                @"URL" : self.imageURL ?: @"<null>",
                                                @"error" : error ?: @"<null>" });

    self.error = error;
    const BOOL didCancel = ([error.domain isEqualToString:TIPImageFetchErrorDomain] && error.code == TIPImageFetchErrorCodeCancelled);

    if (updateMetrics) {
        if (didCancel) {
            [_metricsInternal cancelSource];
        } else {
            [_metricsInternal endSource];
        }
    }
    _metrics = _metricsInternal;
    _metricsInternal = nil;
    _finishTime = mach_absolute_time();

    [self _background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate) {
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didFailToLoadFinalImage:)]) {
            [delegate tip_imageFetchOperation:self didFailToLoadFinalImage:error];
        }
    }];
    [self _background_postDidFinish];
    [self _background_setFinalStateAfterFlushingDelegate:(didCancel) ? TIPImageFetchOperationStateCancelled : TIPImageFetchOperationStateFailed];
}

- (void)_background_updateFinalImage:(TIPImageContainer *)image
                           imageData:(nullable NSData *)imageData
                       renderLatency:(NSTimeInterval)imageRenderLatency
                                 URL:(NSURL *)URL
                          loadSource:(TIPImageLoadSource)source
                    networkImageType:(nullable NSString *)networkImageType
                    networkByteCount:(NSUInteger)networkByteCount
                         placeholder:(BOOL)placeholder
{
    TIPAssert(image != nil);
    TIPAssert(_metrics == nil);
    TIPAssert(_metricsInternal != nil);
    [self _background_extractTargetInfo];
    self.finalImageContainerRaw = image;
    const uint64_t startMachTime = mach_absolute_time();
    BOOL transformed = NO;
    TIPImageContainer *finalImageContainer = [self _background_transformAndScaleImageContainer:image
                                                                                      progress:1.f
                                                                                  didTransform:&transformed];
    _flags.finalImageWasTransformed = transformed;
    imageRenderLatency += TIPComputeDuration(startMachTime, mach_absolute_time());
    id<TIPImageFetchResult> finalResult = [TIPImageFetchResultInternal resultWithImageContainer:finalImageContainer
                                                                                     identifier:self.imageIdentifier
                                                                                     loadSource:source
                                                                                            URL:URL
                                                                             originalDimensions:image.dimensions
                                                                                    placeholder:placeholder
                                                                                    transformed:transformed];
    self.finalResult = finalResult;
    self.progress = 1.0f;

    [_metricsInternal finalWasHit:imageRenderLatency synchronously:NO];
    [_metricsInternal endSource];
    _metrics = _metricsInternal;
    _metricsInternal = nil;
    _finishTime = mach_absolute_time();

    TIPLogDebug(@"Loaded Final Image: %@", @{
                                             @"id" : self.imageIdentifier,
                                             @"URL" : self.imageURL,
                                             @"originalDimensions" : NSStringFromCGSize(self.finalImageContainerRaw.dimensions),
                                             @"finalDimensions" : NSStringFromCGSize(self.finalResult.imageContainer.dimensions),
                                             @"source" : @(source),
                                             @"store" : _imagePipeline.identifier,
                                             @"resumed" : @(_flags.wasResumedDownload),
                                             @"frames" : @(self.finalResult.imageContainer.frameCount),
                                             });

    const BOOL sourceWasNetwork = TIPImageLoadSourceNetwork == source || TIPImageLoadSourceNetworkResumed == source;
    if (sourceWasNetwork && networkByteCount > 0) {
        [self _background_postDidFinishDownloadingImageOfType:networkImageType
                                                  sizeInBytes:networkByteCount];
    }

    TIPAssert(finalResult != nil);
    if (!finalResult) {
        self.error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                         code:TIPImageFetchErrorCodeUnknown
                                     userInfo:nil];
        [self _background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate) {
            if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didFailToLoadFinalImage:)]) {
                [delegate tip_imageFetchOperation:self didFailToLoadFinalImage:self.error];
            }
        }];
        [self _background_postDidFinish];
        [self _background_setFinalStateAfterFlushingDelegate:TIPImageFetchOperationStateFailed];
        return;
    }

    [self _background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate){
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFinalImage:)]) {
            [delegate tip_imageFetchOperation:self didLoadFinalImage:finalResult];
        }
    }];

    [self _background_postDidFinish];
    [self _background_propagateFinalImageData:imageData loadSource:source];
    [self _background_setFinalStateAfterFlushingDelegate:TIPImageFetchOperationStateSucceeded];
}

- (void)_background_postDidStart
{
    for (id<TIPImagePipelineObserver> observer in _observers) {
        if ([observer respondsToSelector:@selector(tip_imageFetchOperationDidStart:)]) {
            [observer tip_imageFetchOperationDidStart:self];
        }
    }
}

- (void)_background_postDidFinish
{
    for (id<TIPImagePipelineObserver> observer in _observers) {
        if ([observer respondsToSelector:@selector(tip_imageFetchOperationDidFinish:)]) {
            [observer tip_imageFetchOperationDidFinish:self];
        }
    }
}

- (void)_background_postDidStartDownload
{
    for (id<TIPImagePipelineObserver> observer in _observers) {
        if ([observer respondsToSelector:@selector(tip_imageFetchOperation:didStartDownloadingImageAtURL:)]) {
            [observer tip_imageFetchOperation:self didStartDownloadingImageAtURL:self.imageURL];
        }
    }
}

- (void)_background_postDidFinishDownloadingImageOfType:(NSString *)imageType
                                            sizeInBytes:(NSUInteger)sizeInBytes
{
    for (id<TIPImagePipelineObserver> observer in _observers) {
        if ([observer respondsToSelector:@selector(tip_imageFetchOperation:didFinishDownloadingImageAtURL:imageType:sizeInBytes:dimensions:wasResumed:)]) {
            [observer tip_imageFetchOperation:self
               didFinishDownloadingImageAtURL:self.imageURL
                                    imageType:imageType
                                  sizeInBytes:sizeInBytes
                                   dimensions:self.finalImageContainerRaw.dimensions
                                   wasResumed:(self.finalResult.imageSource == TIPImageLoadSourceNetworkResumed)];
        }
    }
}

- (void)_background_updatePreviewImageWithCacheEntry:(TIPImageCacheEntry *)cacheEntry
                                          loadSource:(TIPImageLoadSource)source
{
    TIPBoolBlock block = ^(BOOL canContinue) {
        if ([self _background_shouldAbort]) {
            return;
        } else if (!canContinue) {
            NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                                 code:TIPImageFetchErrorCodeCancelledAfterLoadingPreview
                                             userInfo:nil];
            [self _background_updateFailureToLoadFinalImage:error updateMetrics:YES];
            [self _background_propagatePreviewImage:source];
        } else {
            if (TIPImageLoadSourceMemoryCache == source) {
                [self _background_handlePartialMemoryEntry:(id)cacheEntry];
            } else if (TIPImageLoadSourceDiskCache == source) {
                [self _background_handlePartialDiskEntry:(id)cacheEntry
                      tryOtherPipelineDiskCachesIfNeeded:NO];
            } else {
                [self _background_loadFromNextSource];
            }
        }
    };

    [self _background_extractTargetInfo];

    TIPImageContainer *image = cacheEntry.completeImage;
    TIPAssert(image != nil);
    if (!image) {
        // the analyzer reports image can be nil because .completeImage is nullable;
        // if it is (and thus even if we fail TIPAssert() in dogfood but not Production),
        // then return early, because the logic below will lead to a previewResult that
        // is also nil, which results in an else-part below where we do the following.
        block(YES);
        return;
    }

    self.previewImageContainerRaw = image;
    const uint64_t startMachTime = mach_absolute_time();
    BOOL transformed = NO;
    TIPImageContainer *previewImageContainer;
    previewImageContainer = [self _background_transformAndScaleImageContainer:image
                                                                     progress:-1.f // negative == preview
                                                                 didTransform:&transformed];
    _flags.previewImageWasTransformed = transformed;
    const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
    id<TIPImageFetchResult> previewResult = [TIPImageFetchResultInternal resultWithImageContainer:previewImageContainer
                                                                                       identifier:self.imageIdentifier
                                                                                       loadSource:source
                                                                                              URL:cacheEntry.completeImageContext.URL
                                                                               originalDimensions:image.dimensions
                                                                                      placeholder:cacheEntry.completeImageContext.treatAsPlaceholder
                                                                                      transformed:transformed];
    self.previewResult = previewResult;
    id<TIPImageFetchDelegate> delegate = self.delegate;

    [_metricsInternal previewWasHit:latency];

    TIPLogDebug(@"Loaded Preview Image: %@", @{
                                               @"id" : self.imageIdentifier,
                                               @"URL" : self.previewResult.imageURL,
                                               @"originalDimensions" : NSStringFromCGSize(self.previewImageContainerRaw.dimensions),
                                               @"finalDimensions" : NSStringFromCGSize(self.previewResult.imageContainer.dimensions),
                                               @"source" : @(source),
                                               @"store" : _imagePipeline.identifier,
                                               @"resumed" : @(_flags.wasResumedDownload),
                                               });

    TIPAssert(previewResult != nil);
    if (previewResult && [delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadPreviewImage:completion:)]) {
        [self _background_executeDelegateWork:^(id<TIPImageFetchDelegate> blockDelegate) {
            if ([blockDelegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadPreviewImage:completion:)]) {
                [blockDelegate tip_imageFetchOperation:self didLoadPreviewImage:previewResult completion:^(TIPImageFetchPreviewLoadedBehavior behavior) {
                    [self _executeBackgroundWork:^{
                        block(TIPImageFetchPreviewLoadedBehaviorContinueLoading == behavior);
                    }];
                }];
            } else {
                [self _executeBackgroundWork:^{
                    block(YES);
                }];
            }
        }];
    } else {
        block(YES);
    }
}

- (void)_background_updateFirstAnimatedImageFrame:(UIImage *)image
                                    renderLatency:(NSTimeInterval)imageRenderLatency
                                              URL:(NSURL *)URL
                                         progress:(float)progress
                               sourcePartialImage:(TIPPartialImage *)sourcePartialImage
                                       loadSource:(TIPImageLoadSource)source
{
    id<TIPImageFetchDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFirstAnimatedImageFrame:progress:)]) {
        return;
    }

    TIPAssert(!isnan(progress) && !isinf(progress));
    self.progress = progress;
    const uint64_t startMachTime = mach_absolute_time();
    UIImage *firstAnimatedImage = [image tip_scaledImageWithTargetDimensions:_targetDimensions
                                                                 contentMode:_targetContentMode];
    TIPImageContainer *firstAnimatedImageFrameContainer = (firstAnimatedImage) ? [[TIPImageContainer alloc] initWithImage:firstAnimatedImage] : nil;
    imageRenderLatency += TIPComputeDuration(startMachTime, mach_absolute_time());
    id<TIPImageFetchResult> progressiveResult = [TIPImageFetchResultInternal resultWithImageContainer:firstAnimatedImageFrameContainer
                                                                                           identifier:self.imageIdentifier
                                                                                           loadSource:source
                                                                                                  URL:URL
                                                                                   originalDimensions:image.tip_dimensions
                                                                                          placeholder:NO
                                                                                          transformed:NO];
    self.progressiveResult = progressiveResult;

    [_metricsInternal progressiveFrameWasHit:imageRenderLatency];

    TIPLogDebug(@"Loaded First Animated Image Frame: %@", @{
                                                            @"id" : self.imageIdentifier,
                                                            @"URL" : self.imageURL,
                                                            @"originalDimensions" : NSStringFromCGSize(sourcePartialImage.dimensions),
                                                            @"finalDimensions" : NSStringFromCGSize([firstAnimatedImageFrameContainer dimensions]),
                                                            @"source" : @(_flags.wasResumedDownload ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork),
                                                            @"store" : _imagePipeline.identifier,
                                                            @"resumed" : @(_flags.wasResumedDownload),
                                                            });

    TIPAssert(progressiveResult != nil);
    if (progressiveResult) {
        [self _background_executeDelegateWork:^(id<TIPImageFetchDelegate> blockDelegate) {
            if ([blockDelegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFirstAnimatedImageFrame:progress:)]) {
                [blockDelegate tip_imageFetchOperation:self
                        didLoadFirstAnimatedImageFrame:progressiveResult
                                              progress:progress];
            }
        }];
    }
}

- (void)_background_updateProgressiveImage:(UIImage *)image
                               transformed:(BOOL)transformed
                             renderLatency:(NSTimeInterval)imageRenderLatency
                                       URL:(NSURL *)URL
                                  progress:(float)progress
                        sourcePartialImage:(TIPPartialImage *)sourcePartialImage
                                loadSource:(TIPImageLoadSource)source
{
    id<TIPImageFetchDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(tip_imageFetchOperation:didUpdateProgressiveImage:progress:)]) {
        return;
    }

    TIPAssert(!isnan(progress) && !isinf(progress));
    self.progress = progress;

    TIPAssert(image != nil);
    _flags.progressiveImageWasTransformed = transformed;
    TIPImageContainer *progressContainer = (image) ? [[TIPImageContainer alloc] initWithImage:image] : nil;
    id<TIPImageFetchResult> progressiveResult = [TIPImageFetchResultInternal resultWithImageContainer:progressContainer
                                                                                           identifier:self.imageIdentifier
                                                                                           loadSource:source
                                                                                                  URL:URL
                                                                                   originalDimensions:image.tip_dimensions
                                                                                          placeholder:NO
                                                                                          transformed:NO];
    self.progressiveResult = progressiveResult;

    [_metricsInternal progressiveFrameWasHit:imageRenderLatency];

    TIPLogDebug(@"Loaded Progressive Image: %@", @{
                                                   @"progress" : @(progress),
                                                   @"id" : self.imageIdentifier,
                                                   @"URL" : URL,
                                                   @"originalDimensions" : NSStringFromCGSize(sourcePartialImage.dimensions),
                                                   @"finalDimensions" : NSStringFromCGSize([self.progressiveResult.imageContainer dimensions]),
                                                   @"source" : @(source),
                                                   @"store" : _imagePipeline.identifier,
                                                   @"resumed" : @(_flags.wasResumedDownload),
                                                   });

    TIPAssert(progressiveResult != nil);
    if (progressiveResult) {
        [self _background_executeDelegateWork:^(id<TIPImageFetchDelegate> blockDelegate) {
            if ([blockDelegate respondsToSelector:@selector(tip_imageFetchOperation:didUpdateProgressiveImage:progress:)]) {
                [blockDelegate tip_imageFetchOperation:self
                             didUpdateProgressiveImage:progressiveResult
                                              progress:progress];
            }
        }];
    }
}

- (void)_background_updateProgress:(float)progress
{
    TIPAssert(!isnan(progress) && !isinf(progress));
    self.progress = progress;

    [self _background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate) {
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didUpdateProgress:)]) {
            [delegate tip_imageFetchOperation:self didUpdateProgress:progress];
        }
    }];
}

- (void)_background_handleCompletedMemoryEntry:(TIPImageMemoryCacheEntry *)entry
{
    if ([self _background_shouldAbort]) {
        return;
    }

    TIPImageContainer *image = entry.completeImage;
    if (image) {
        NSURL *completeImageURL = entry.completeImageContext.URL;
        const BOOL isFinalImage = [completeImageURL isEqual:self.imageURL];

        if (isFinalImage) {
            [self _background_updateFinalImage:image
                                     imageData:entry.completeImageData /*ok if nil*/
                                 renderLatency:0
                                           URL:completeImageURL
                                    loadSource:TIPImageLoadSourceMemoryCache
                              networkImageType:nil
                              networkByteCount:0
                                   placeholder:entry.completeImageContext.treatAsPlaceholder];
            return;
        }

        if (!self.previewResult) {
            [self _background_updatePreviewImageWithCacheEntry:entry
                                                    loadSource:TIPImageLoadSourceMemoryCache];
            return;
        }
    }

    // continue
    [self _background_handlePartialMemoryEntry:entry];
}

- (void)_background_handlePartialMemoryEntry:(TIPImageMemoryCacheEntry *)entry
{
    if ([self _background_shouldAbort]) {
        return;
    }

    TIPPartialImage * const partialImage = entry.partialImage;
    if (partialImage && [self supportsLoadingFromSource:TIPImageLoadSourceNetworkResumed]) {
        const BOOL isFinalImage = [self.imageURL isEqual:entry.partialImageContext.URL];
        if (isFinalImage) {
            TIPPartialImageEntryContext * const partialImageContext = entry.partialImageContext;
            NSString * const entryIdentifier = entry.identifier;
            _networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming = partialImage;
            _networkContext.imageDownloadRequest.imageDownloadLastModified = partialImageContext.lastModified;

            TIPImageDiskCache * const diskCache = _imagePipeline.diskCache;
            if (diskCache) {
                TIPImageDiskCacheEntry *diskEntry;
                diskEntry = [diskCache imageEntryForIdentifier:entryIdentifier
                                                       options:TIPImageDiskCacheFetchOptionTemporaryFile
                                              targetDimensions:_targetDimensions
                                             targetContentMode:_targetContentMode
                                              decoderConfigMap:_decoderConfigMap];
                TIPImageDiskCacheTemporaryFile *diskTempFile = diskEntry.tempFile;
                if (!diskTempFile) {
                    diskTempFile = [_imagePipeline.diskCache openTemporaryFileForImageIdentifier:entry.identifier];
                    [diskTempFile appendData:partialImage.data];
                }
                _networkContext.imageDownloadRequest.imageDownloadTemporaryFileForResuming = diskTempFile;
            }

            [self _background_processContinuedPartialEntry:partialImage
                                                       URL:partialImageContext.URL
                                                loadSource:TIPImageLoadSourceMemoryCache];

            _flags.shouldJumpToResumingDownload = 1;
        }
    }

    // continue
    [self _background_loadFromNextSource];
}

- (void)_background_handleCompletedDiskEntry:(TIPImageDiskCacheEntry *)entry
{
    if ([self _background_shouldAbort]) {
        return;
    }

    if (entry.completeImageContext) {
        NSURL *completeImageURL = entry.completeImageContext.URL;
        const CGSize dimensions = entry.completeImageContext.dimensions;
        const CGSize currentDimensions = self.previewResult.imageContainer.dimensions;
        const BOOL isFinal = [completeImageURL isEqual:self.imageURL];
        if (isFinal || (dimensions.width * dimensions.height > currentDimensions.width * currentDimensions.height)) {
            // Metadata checks out, load the actual complete image
            entry = [_imagePipeline.diskCache imageEntryForIdentifier:entry.identifier
                                                              options:TIPImageDiskCacheFetchOptionCompleteImage
                                                     targetDimensions:_targetDimensions
                                                    targetContentMode:_targetContentMode
                                                     decoderConfigMap:_decoderConfigMap];
            if ([completeImageURL isEqual:entry.completeImageContext.URL]) {
                TIPImageContainer *image = entry.completeImage;
                if (image) {
                    if (isFinal) {
                        [self _background_updateFinalImage:image
                                                 imageData:entry.completeImageData // ok if nil
                                             renderLatency:0
                                                       URL:completeImageURL
                                                loadSource:TIPImageLoadSourceDiskCache
                                          networkImageType:nil
                                          networkByteCount:0
                                               placeholder:entry.completeImageContext.treatAsPlaceholder];
                        return;
                    }

                    if (!self.previewResult) {
                        [self _background_updatePreviewImageWithCacheEntry:entry
                                                                loadSource:TIPImageLoadSourceDiskCache];
                        return;
                    }
                }
            }
        }
    }

    [self _background_handlePartialDiskEntry:entry
          tryOtherPipelineDiskCachesIfNeeded:YES];
}

- (void)_background_handlePartialDiskEntry:(TIPImageDiskCacheEntry *)entry
        tryOtherPipelineDiskCachesIfNeeded:(BOOL)tryOtherPipelineDiskCachesIfNeeded
{
    if ([self _background_shouldAbort]) {
        return;
    }

    if (entry.partialImageContext && [self supportsLoadingFromSource:TIPImageLoadSourceNetworkResumed]) {
        const CGSize dimensions = entry.completeImageContext.dimensions;
        const BOOL isFinal = [self.imageURL isEqual:entry.partialImageContext.URL];
        BOOL isReasonableDataRemainingAndLarger = NO;
        [self _background_extractTargetInfo];
        const BOOL couldBeReasonableDataRemainingAndLarger =
                        !isFinal &&
                        TIPSizeGreaterThanZero(_targetDimensions) &&
                        ((dimensions.width * dimensions.height) > (_targetDimensions.width * _targetDimensions.height));
        if (couldBeReasonableDataRemainingAndLarger) {
            const double ratio = (dimensions.width * dimensions.height) / (_targetDimensions.width * _targetDimensions.height);
            const NSUInteger remainingBytes = (entry.partialImageContext.expectedContentLength > entry.partialFileSize) ? entry.partialImageContext.expectedContentLength - entry.partialFileSize : NSUIntegerMax;
            NSUInteger hypotheticalBytes = (entry.partialImageContext.expectedContentLength) ?: 0;
            hypotheticalBytes = (NSUInteger)((double)hypotheticalBytes / ratio);
            isReasonableDataRemainingAndLarger = remainingBytes < hypotheticalBytes;
        }
        if (isFinal || isReasonableDataRemainingAndLarger) {
            // meta-data checks out, load the actual partial image
            entry = [_imagePipeline.diskCache imageEntryForIdentifier:entry.identifier
                                                              options:(TIPImageDiskCacheFetchOptionPartialImage | TIPImageDiskCacheFetchOptionTemporaryFile)
                                                     targetDimensions:_targetDimensions
                                                    targetContentMode:_targetContentMode
                                                     decoderConfigMap:_decoderConfigMap];
            if ([self.imageURL isEqual:entry.partialImageContext.URL] && entry.partialImage && entry.tempFile) {
                _networkContext.imageDownloadRequest.imageDownloadLastModified = entry.partialImageContext.lastModified;
                _networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming = entry.partialImage;
                _networkContext.imageDownloadRequest.imageDownloadTemporaryFileForResuming = entry.tempFile;

                [self _background_processContinuedPartialEntry:entry.partialImage
                                                           URL:entry.partialImageContext.URL
                                                    loadSource:TIPImageLoadSourceDiskCache];

                _flags.shouldJumpToResumingDownload = 1;
            }
        }
    }

    if (tryOtherPipelineDiskCachesIfNeeded) {
        [self _background_loadFromOtherPipelineDisk];
    } else {
        [self _background_loadFromNextSource];
    }
}

#pragma mark Render Progress

- (TIPImageContainer *)_background_transformAndScaleImageContainer:(TIPImageContainer *)imageContainer
                                                          progress:(float)progress
                                                      didTransform:(out BOOL *)transformedOut
{
    TIPImageContainer *outputImage;
    if (imageContainer.isAnimated) {
        outputImage = [imageContainer scaleToTargetDimensions:_targetDimensions
                                                  contentMode:_targetContentMode] ?: imageContainer;
        *transformedOut = NO;
    } else {
        UIImage *scaledImage = [self _background_transformAndScaleImage:imageContainer.image
                                                               progress:progress
                                                           didTransform:transformedOut];
        outputImage = [[TIPImageContainer alloc] initWithImage:scaledImage];
    }
    return outputImage;
}

- (UIImage *)_background_transformAndScaleImage:(UIImage *)image
                                       progress:(float)progress
                                   didTransform:(out BOOL *)transformedOut
{
    *transformedOut = NO;
    [self _background_extractTargetInfo];
    if (_transformer) {
        UIImage *transformedImage = [_transformer tip_transformImage:image
                                                        withProgress:progress
                                                hintTargetDimensions:_targetDimensions
                                               hintTargetContentMode:_targetContentMode
                                              forImageFetchOperation:self];
        if (transformedImage) {
            image = transformedImage;
            *transformedOut = YES;
        }
    }
    image = [image tip_scaledImageWithTargetDimensions:_targetDimensions
                                           contentMode:_targetContentMode];
    TIPAssert(image != nil);
    return image;
}

- (void)_background_processContinuedPartialEntry:(TIPPartialImage *)partialImage
                                             URL:(NSURL *)URL
                                      loadSource:(TIPImageLoadSource)source
{
    [self _background_validateProgressiveSupportWithPartialImage:partialImage];

    // If we have a partial image with enough progress to display, let's decode it and use it as a progress image
    if (_flags.permitsProgressiveLoading && partialImage.frameCount > 0 && [self.delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadPreviewImage:completion:)]) {
        const uint64_t startMachTime = mach_absolute_time();
        const TIPImageDecoderAppendResult givenResult = TIPImageDecoderAppendResultDidLoadFrame;
        UIImage *progressImage = [self _background_getNextProgressiveImageWithAppendResult:givenResult
                                                                              partialImage:partialImage
                                                                               renderCount:0];
        if (progressImage) {
            const float progress = partialImage.progress;
            BOOL transformed = NO;
            progressImage = [self _background_transformAndScaleImage:progressImage
                                                            progress:progress
                                                        didTransform:&transformed];
            const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
            [self _background_updateProgressiveImage:progressImage
                                         transformed:transformed
                                       renderLatency:latency
                                                 URL:URL
                                            progress:progress
                                  sourcePartialImage:partialImage
                                          loadSource:source];
        }
    }
}

- (nullable UIImage *)_background_getNextProgressiveImageWithAppendResult:(TIPImageDecoderAppendResult)appendResult
                                                             partialImage:(TIPPartialImage *)partialImage
                                                              renderCount:(NSUInteger)renderCount
{
    [self _background_validateProgressiveSupportWithPartialImage:partialImage];

    BOOL shouldRender = NO;
    TIPImageDecoderRenderMode mode = TIPImageDecoderRenderModeCompleteImage;
    if (partialImage.state > TIPPartialImageStateLoadingHeaders) {
        shouldRender = YES;
        if (_flags.permitsProgressiveLoading) {

            TIPImageFetchProgress fetchProgress = TIPImageFetchProgressNone;
            if (TIPImageDecoderAppendResultDidLoadFrame == appendResult) {
                fetchProgress = TIPImageFetchProgressFullFrame;
            } else if (partialImage.state > TIPPartialImageStateLoadingHeaders) {
                fetchProgress = TIPImageFetchProgressPartialFrame;
            }
            TIPImageFetchProgressUpdateBehavior behavior = TIPImageFetchProgressUpdateBehaviorNone;
            if (_progressiveLoadingPolicy) {
                behavior = [_progressiveLoadingPolicy tip_imageFetchOperation:self
                                                          behaviorForProgress:fetchProgress
                                                                   frameCount:partialImage.frameCount
                                                                     progress:partialImage.progress
                                                                         type:partialImage.type
                                                                   dimensions:partialImage.dimensions
                                                                  renderCount:renderCount];
            }

            switch (behavior) {
                case TIPImageFetchProgressUpdateBehaviorNone:
                    shouldRender = NO;
                    break;
                case TIPImageFetchProgressUpdateBehaviorUpdateWithAnyProgress:
                    mode = TIPImageDecoderRenderModeAnyProgress;
                    break;
                case TIPImageFetchProgressUpdateBehaviorUpdateWithFullFrameProgress:
                    mode = TIPImageDecoderRenderModeFullFrameProgress;
                    break;
            }
        }
    }

    TIPImageContainer *image = (shouldRender) ? [partialImage renderImageWithMode:mode
                                                                 targetDimensions:_targetDimensions
                                                                targetContentMode:_targetContentMode
                                                                          decoded:YES] : nil;
    return image.image;
}

- (nullable UIImage *)_background_getFirstFrameOfAnimatedImageIfNotYetProvided:(TIPPartialImage *)partialImage
{
    if (partialImage.isAnimated && partialImage.frameCount >= 1 && !_flags.didReceiveFirstAnimatedFrame) {
        if ([self.delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFirstAnimatedImageFrame:progress:)]) {
            TIPImageContainer *imageContainer = [partialImage renderImageWithMode:TIPImageDecoderRenderModeFullFrameProgress
                                                                 targetDimensions:_targetDimensions
                                                                targetContentMode:_targetContentMode
                                                                          decoded:NO];
            if (imageContainer && !imageContainer.isAnimated) {
                // Provide the first frame if requested
                _flags.didReceiveFirstAnimatedFrame = 1;
                return imageContainer.image;
            }
        }
    }

    return nil;
}

#pragma mark Create Cache Entry

- (nullable TIPImageCacheEntry *)_background_createCacheEntryUsingRawImage:(BOOL)useRawImage
                                                     permitPreviewFallback:(BOOL)permitPreviewFallback
                                                               didFallback:(nullable out BOOL *)didFallbackToPreviewOut
{
    TIPImageCacheEntry *entry = nil;
    TIPImageContainer *image = (useRawImage) ? self.finalImageContainerRaw : self.finalResult.imageContainer;
    NSURL *imageURL = self.finalResult.imageURL;
    BOOL isPlaceholder = self.finalResult.imageIsTreatedAsPlaceholder;
    if (!image && permitPreviewFallback) {
        image = (useRawImage) ? self.previewImageContainerRaw : self.previewResult.imageContainer;
        imageURL = self.previewResult.imageURL;
        isPlaceholder = self.previewResult.imageIsTreatedAsPlaceholder;
        if (didFallbackToPreviewOut) {
            *didFallbackToPreviewOut = YES;
        }
    }

    if (image) {
        entry = [[TIPImageCacheEntry alloc] init];
        TIPImageCacheEntryContext *context = nil;
        TIPCompleteImageEntryContext *completeContext = [[TIPCompleteImageEntryContext alloc] init];
        completeContext.dimensions = image.dimensions;
        completeContext.animated = image.isAnimated;

        entry.completeImageContext = completeContext;
        entry.completeImage = image;
        context = completeContext;
        [self _hydrateNewContext:context
                        imageURL:imageURL
                     placeholder:isPlaceholder];

        entry.identifier = self.imageIdentifier;
    }

    return entry;
}

- (nullable TIPImageCacheEntry *)_background_createCacheEntryFromPartialImage:(TIPPartialImage *)partialImage
                                                                 lastModified:(NSString *)lastModified
                                                                     imageURL:(NSURL *)imageURL
{
    if (!partialImage) {
        return nil;
    }

    if (!lastModified) {
        return nil;
    }

    if (partialImage.state <= TIPPartialImageStateLoadingHeaders) {
        return nil;
    }

    if (TIP_BITMASK_HAS_SUBSET_FLAGS(_networkContext.imageDownloadRequest.imageDownloadOptions, TIPImageFetchTreatAsPlaceholder)) {
        return nil;
    }

    TIPImageCacheEntry *entry = [[TIPImageCacheEntry alloc] init];
    TIPImageCacheEntryContext *context = nil;

    TIPPartialImageEntryContext *partialContext = [[TIPPartialImageEntryContext alloc] init];
    partialContext.dimensions = partialImage.dimensions;
    partialContext.expectedContentLength = partialImage.expectedContentLength;
    partialContext.lastModified = lastModified;
    partialContext.animated = partialImage.isAnimated;

    entry.partialImageContext = partialContext;
    entry.partialImage = partialImage;
    context = partialContext;
    [self _hydrateNewContext:context
                    imageURL:imageURL
                 placeholder:NO];

    entry.identifier = self.imageIdentifier;

    return entry;
}

#pragma mark Cache propagation

- (void)_background_propagatePartialImage:(TIPPartialImage *)partialImage
                             lastModified:(NSString *)lastModified
                               wasResumed:(BOOL)wasResumed
{
    [self _background_extractStorageInfo];

    if (!_flags.didReceiveFirstByte || self.finalImageContainerRaw) {
        return;
    }

    TIPImageCacheEntry *entry = [self _background_createCacheEntryFromPartialImage:partialImage
                                                                      lastModified:lastModified
                                                                          imageURL:self.progressiveResult.imageURL];
    TIPAssert(!entry || (entry.partialImage && entry.partialImageContext));
    if (entry) {
        [_imagePipeline.memoryCache updateImageEntry:entry
                             forciblyReplaceExisting:NO];
    }
}

- (void)_background_propagatePreviewImage:(TIPImageLoadSource)source
{
    if (TIPImageLoadSourceMemoryCache != source && TIPImageLoadSourceDiskCache != source) {
        // only memory/disk sources supported
        return;
    }

    [self _background_extractStorageInfo];

    if (!self.previewImageContainerRaw || self.finalImageContainerRaw) {
        return;
    }

    TIPImageCacheEntry *entry = nil;

    // First, the memory cache (if coming from disk)
    if (TIPImageLoadSourceDiskCache == source) {
        entry = [self _background_createCacheEntryUsingRawImage:YES
                                          permitPreviewFallback:YES
                                                    didFallback:NULL /*don't care*/];
        TIPAssert(!entry || (entry.completeImage && entry.completeImageContext));
        if (entry) {
            [_imagePipeline.memoryCache updateImageEntry:entry
                                 forciblyReplaceExisting:NO];
        }
    }

    // Second, the rendered cache
    if (!_flags.shouldSkipRenderedCacheStore) {
        BOOL didFallbackToPreview = NO;
        entry = [self _background_createCacheEntryUsingRawImage:NO
                                          permitPreviewFallback:YES
                                                    didFallback:&didFallbackToPreview];
        TIPAssert(!entry || (entry.completeImage && entry.completeImageContext));
        if (entry) {
            const CGSize rawSize = (didFallbackToPreview) ?
                                        self.previewImageContainerRaw.dimensions :
                                        self.finalImageContainerRaw.dimensions;
            const BOOL wasTransformed = (didFallbackToPreview) ?
                                            _flags.previewImageWasTransformed :
                                            _flags.finalImageWasTransformed;
            if (!wasTransformed || _transfomerIdentifier) {
                [_imagePipeline.renderedCache storeImageEntry:entry
                                        transformerIdentifier:(wasTransformed) ? _transfomerIdentifier : nil
                                        sourceImageDimensions:rawSize];
            }
        }
    }
}

- (void)_background_propagateFinalImageData:(nullable NSData *)imageData
                                 loadSource:(TIPImageLoadSource)source
{
    [self _background_extractStorageInfo];

    if (!self.finalImageContainerRaw) {
        return;
    }

    TIPImageCacheEntry *entry = [self _background_createCacheEntryUsingRawImage:YES
                                                          permitPreviewFallback:NO
                                                                    didFallback:NULL];
    TIPAssert(!entry || (entry.completeImage && entry.completeImageContext));

    if (entry) {
        switch (source) {
            case TIPImageLoadSourceMemoryCache:
            {
                [_imagePipeline.diskCache updateImageEntry:entry forciblyReplaceExisting:NO];
                break;
            }
            case TIPImageLoadSourceDiskCache:
            case TIPImageLoadSourceNetwork:
            case TIPImageLoadSourceNetworkResumed:
            case TIPImageLoadSourceAdditionalCache:
            {
                if (imageData && !entry.completeImageData) {
                    entry.completeImageData = imageData;
                }
                [_imagePipeline.memoryCache updateImageEntry:entry forciblyReplaceExisting:NO];
                if (TIPImageLoadSourceNetwork == source || TIPImageLoadSourceNetworkResumed == source) {
                    [_imagePipeline postCompletedEntry:entry manual:NO];
                    // the network will have already transitioned the disk entry to the disk cache
                    // so there'se no need to update the image entry of the disk cache
                }
                break;
            }
            case TIPImageLoadSourceUnknown:
                return;
        }
    }

    // Always try to update the rendered cache
    [self _background_propagateFinalRenderedImage:source];
}

- (void)_background_propagateFinalRenderedImage:(TIPImageLoadSource)source
{
    if (_flags.finalImageWasTransformed && !_transfomerIdentifier) {
        return;
    }

    if (_flags.shouldSkipRenderedCacheStore) {
        return;
    }

    TIPImageCacheEntry *entry = [self _background_createCacheEntryUsingRawImage:NO
                                                          permitPreviewFallback:NO
                                                                    didFallback:NULL];
    TIPAssert(!entry || (entry.completeImage && entry.completeImageContext));
    if (entry) {
        const CGSize rawSize = self.finalImageContainerRaw.dimensions;
        NSString *transformerIdentifier = (_flags.finalImageWasTransformed) ? _transfomerIdentifier : nil;
        [_imagePipeline.renderedCache storeImageEntry:entry
                                transformerIdentifier:transformerIdentifier
                                sourceImageDimensions:rawSize];
    }
}

#pragma mark Execute

- (void)_background_executeDelegateWork:(TIPImageFetchDelegateWorkBlock)block
{
    id<TIPImageFetchDelegate> delegate = self.delegate;
    tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        block(delegate);
    });
}

- (void)_executeBackgroundWork:(dispatch_block_t)block
{
    tip_dispatch_async_autoreleasing(_backgroundQueue, block);
}

@end

@implementation TIPImageFetchOperation (DiskCache)

- (void)_diskCache_loadFromOtherPipelines:(NSArray<TIPImagePipeline *> *)pipelines
                            startMachTime:(uint64_t)startMachTime
{
    for (TIPImagePipeline *nextPipeline in pipelines) {
        // look in the pipeline's disk cache
        if ([self _diskCache_attemptLoadFromOtherPipelineDisk:nextPipeline startMachTime:startMachTime]) {
            // success!
            return;
        }
    }

    // Ran out of "next" pipelines, load from next source
    [self _diskCache_completeLoadFromOtherPipelineDisk:nil
                                        imageContainer:nil
                                                   URL:nil
                                               latency:TIPComputeDuration(startMachTime, mach_absolute_time())
                                           placeholder:NO];
}

- (BOOL)_diskCache_attemptLoadFromOtherPipelineDisk:(TIPImagePipeline *)nextPipeline
                                      startMachTime:(uint64_t)startMachTime
{
    TIPImageDiskCache *nextDiskCache = nextPipeline.diskCache;
    if (nextDiskCache) {

        // pull out the on disk path to the desired entry if available
        TIPCompleteImageEntryContext *context = nil;
        NSString *filePath = [nextDiskCache diskCache_imageEntryFilePathForIdentifier:self.imageIdentifier
                                                             hitShouldMoveEntryToHead:NO
                                                                              context:&context];

        // only accept an exact match (URLs are equal)
        if (filePath && [context.URL isEqual:self.imageURL]) {

            // pull out our pipeline's disk cache
            TIPImageDiskCache *thisDiskCache = _imagePipeline.diskCache;

            // override fetch values
            const TIPImageFetchOptions options = _networkContext.imageDownloadRequest.imageDownloadOptions;
            context.updateExpiryOnAccess = TIP_BITMASK_EXCLUDES_FLAGS(options, TIPImageFetchDoNotResetExpiryOnAccess);
            context.TTL = _networkContext.imageDownloadRequest.imageDownloadTTL;
            context.lastAccess = [NSDate date];
            if (context.TTL <= 0.0) {
                context.TTL = TIPTimeToLiveDefault;
            }
            // leave context.treatAsPlaceholder as-is

            // create an entry
            TIPImageCacheEntry *entry = [[TIPImageCacheEntry alloc] init];
            entry.identifier = self.imageIdentifier;
            entry.completeImageContext = context;
            entry.completeImageFilePath = filePath;

            // store the entry (via file path) to disk cache
            [thisDiskCache diskCache_updateImageEntry:entry
                              forciblyReplaceExisting:!context.treatAsPlaceholder];

            // complete the loop by retrieving entry (with UIImage) from disk cache
            entry = [thisDiskCache diskCache_imageEntryForIdentifier:entry.identifier
                                                             options:TIPImageDiskCacheFetchOptionCompleteImage
                                                    targetDimensions:_targetDimensions
                                                   targetContentMode:_targetContentMode
                                                    decoderConfigMap:_decoderConfigMap];

            // did we get an image?
            TIPImageContainer *image = entry.completeImage;
            if (image) {

                // complete
                [self _diskCache_completeLoadFromOtherPipelineDisk:nextPipeline
                                                    imageContainer:image
                                                               URL:context.URL
                                                           latency:TIPComputeDuration(startMachTime, mach_absolute_time())
                                                       placeholder:context.treatAsPlaceholder];

                // success!
                return YES;
            }
        }
    }

    // didn't succeed
    return NO;
}

- (void)_diskCache_completeLoadFromOtherPipelineDisk:(nullable TIPImagePipeline *)pipeline
                                      imageContainer:(nullable TIPImageContainer *)imageContainer
                                                 URL:(nullable NSURL *)URL
                                             latency:(NSTimeInterval)latency
                                         placeholder:(BOOL)placeholder
{
    if (latency > 0.150) {
        TIPLogWarning(@"Other Pipeline Duration (%@): %.3fs", (imageContainer != nil) ? @"HIT" : @"MISS", latency);
    } else if (imageContainer) {
        TIPLogDebug(@"Other Pipeline Duration (HIT): %.3fs", latency);
    }

    [self _executeBackgroundWork:^{
        if (imageContainer && URL) {
            [self _background_updateFinalImage:imageContainer
                                     imageData:nil
                                 renderLatency:0
                                           URL:URL
                                    loadSource:TIPImageLoadSourceDiskCache
                              networkImageType:nil
                              networkByteCount:0
                                   placeholder:placeholder];
        } else {
            [self _background_loadFromNextSource];
        }
    }];
}

@end

@implementation TIPImageFetchOperation (Testing)

- (id<TIPImageDownloadContext>)associatedDownloadContext
{
    return _networkContext.imageDownloadContext;
}

@end

@implementation TIPImageFetchDelegateDeallocHandler
{
    __weak TIPImageFetchOperation *_operation;
    Class _delegateClass;
}

- (instancetype)initWithFetchOperation:(TIPImageFetchOperation *)operation
                              delegate:(id<TIPImageFetchDelegate>)delegate
{
    if (self = [super init]) {
        _operation = operation;
        _delegateClass = [delegate class];
    }
    return self;
}

- (void)invalidate
{
    _operation = nil;
}

- (void)dealloc
{
    TIPImageFetchOperation *op = _operation;
    if (op && !op.isFinished) {
        TIPLogInformation(@"%@<%@> deallocated, cancelling %@", NSStringFromClass(_delegateClass), NSStringFromProtocol(@protocol(TIPImageFetchDelegate)), op);
        [op cancel];
    }
}

@end

@implementation TIPImageFetchDownloadRequest

- (instancetype)initWithRequest:(id<TIPImageFetchRequest>)fetchRequest
{
    if (self = [super init]) {
        _imageDownloadPriority = NSOperationQueuePriorityNormal;
        _imageDownloadURL = [fetchRequest imageURL];
        _imageDownloadIdentifier = [TIPImageFetchRequestGetImageIdentifier(fetchRequest) copy];
        if ([fetchRequest respondsToSelector:@selector(decoderConfigMap)]) {
            _decoderConfigMap = [[fetchRequest decoderConfigMap] copy];
        }
    }
    return self;
}

@end

@implementation TIPImageFetchResultInternal

@synthesize imageContainer = _imageContainer;
@synthesize imageSource = _imageSource;
@synthesize imageURL = _imageURL;
@synthesize imageOriginalDimensions = _imageOriginalDimensions;
@synthesize imageIsTreatedAsPlaceholder = _imageIsTreatedAsPlaceholder;
@synthesize imageWasTransformed = _imageWasTransformed;
@synthesize imageIdentifier = _imageIdentifier;

+ (nullable TIPImageFetchResultInternal *)resultWithImageContainer:(nullable TIPImageContainer *)imageContainer
                                                        identifier:(nullable NSString *)identifier
                                                        loadSource:(TIPImageLoadSource)source
                                                               URL:(nullable NSURL *)URL
                                                originalDimensions:(CGSize)originalDimensions
                                                       placeholder:(BOOL)placeholder
                                                       transformed:(BOOL)transformed
{
    if (!imageContainer || !URL || !identifier) {
        return nil;
    }

    return [[TIPImageFetchResultInternal alloc] initWithImageContainer:imageContainer
                                                            identifier:identifier
                                                                source:source
                                                                   URL:URL
                                                    originalDimensions:originalDimensions
                                                           placeholder:placeholder
                                                           transformed:transformed];
}

- (instancetype)initWithImageContainer:(TIPImageContainer *)imageContainer
                            identifier:(NSString *)identifier
                                source:(TIPImageLoadSource)source
                                   URL:(NSURL *)URL
                    originalDimensions:(CGSize)originalDimensions
                           placeholder:(BOOL)placeholder
                           transformed:(BOOL)transformed TIP_OBJC_DIRECT
{
    if (self = [super init]) {
        _imageContainer = imageContainer;
        _imageSource = source;
        _imageURL = URL;
        _imageOriginalDimensions = originalDimensions;
        _imageIsTreatedAsPlaceholder = placeholder;
        _imageWasTransformed = transformed;
        _imageIdentifier = [identifier copy];
    }
    return self;
}

@end

static NSQualityOfService ConvertNSOperationQueuePriorityToQualityOfService(NSInteger pri)
{
    /*

    VLo              Lo              Nml             Hi              VHi
     -8  -7  -6  -5  -4  -3  -2  -1   0   1   2   3   4   5   6   7   8
      9  11  13  15  17  18  19  20  21  22  23  24  25  27  29  31  33
     Bg              Uti                            UIni             UInt

     */

    NSInteger qos = 1;
    if (pri <= -4) {
        qos = 17 - ((pri + 4) * 2);
    } else if (pri <= 4) {
        qos = 25 - (4 - pri);
    } else {
        qos = 25 + ((pri - 4) * 2);
    }

    if (qos < 1) {
        qos = 1;
    }

    return (NSQualityOfService)qos;
}

NS_ASSUME_NONNULL_END
