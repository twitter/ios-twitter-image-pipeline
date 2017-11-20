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

NSString * const TIPImageFetchErrorDomain = @"TIPImageFetchErrorDomain";
NSString * const TIPImageStoreErrorDomain = @"TIPImageStoreErrorDomain";
NSString * const TIPErrorDomain = @"TIPErrorDomain";
NSString * const TIPErrorUserInfoHTTPStatusCodeKey = @"httpStatusCode";

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
@property (nonatomic, nullable, copy) NSDictionary<NSString *, id> *decoderConfigMap;

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

@interface TIPImageFetchDelegateDeallocHandler : NSObject
- (instancetype)initWithFetchOperation:(TIPImageFetchOperation *)operation delegate:(id<TIPImageFetchDelegate>)delegate;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (void)invalidate;
@end

@interface TIPImageFetchOperationNetworkStepContext : NSObject
@property (nonatomic, nullable) TIPImageFetchDownloadRequest *imageDownloadRequest;
@property (nonatomic, nullable) id<TIPImageDownloadContext> imageDownloadContext;
@end

@interface TIPImageFetchResultInternal : NSObject <TIPImageFetchResult>
+ (nullable instancetype)resultWithImageContainer:(nullable TIPImageContainer *)imageContainer identifier:(nullable NSString *)identifier source:(TIPImageLoadSource)source URL:(nullable NSURL *)URL originalDimensions:(CGSize)originalDimensions placeholder:(BOOL)placeholder transformed:(BOOL)transformed;
@end

@implementation TIPImageFetchOperationNetworkStepContext
@end

@interface TIPImageFetchOperation () <TIPImageDownloadDelegate>

@property (atomic, nullable, weak) id<TIPImageFetchDelegate> delegate;
#pragma twitter startignorestylecheck
@property (atomic, nullable, strong) id<TIPImageFetchDelegate> strongDelegate;
#pragma twitter endignorestylecheck
@property (atomic, nullable, weak) TIPImageFetchDelegateDeallocHandler *delegateHandler;
@property (nonatomic) TIPImageFetchOperationState state;

@property (nonatomic) float progress;
@property (nonatomic, nullable) NSError *operationError;

@property (nonatomic, nullable) id<TIPImageFetchResult> previewResult;
@property (nonatomic, nullable) id<TIPImageFetchResult> progressiveResult;
@property (nonatomic, nullable) id<TIPImageFetchResult> finalResult;

@property (nonatomic, nullable) TIPImageContainer *previewImageContainerRaw;
@property (nonatomic, nullable) TIPImageContainer *finalImageContainerRaw;

@property (nonatomic, nullable) NSError *error;
@property (nonatomic, nullable, copy) NSString *networkLoadImageType;
@property (nonatomic) CGSize networkImageOriginalDimensions;

- (void)_tip_extractBasicRequestInfo;
- (void)_tip_initializeDelegate:(nullable id<TIPImageFetchDelegate>)delegate;
- (void)_tip_clearDelegateHandler;

@end

@interface TIPImageFetchOperation (Background)

// Start/Abort
- (void)_tip_background_start;
- (BOOL)_tip_background_shouldAbort;

// Generate State
- (void)_tip_background_extractObservers;
- (void)_tip_background_extractAdvancedRequestInfo;
- (void)_tip_background_extractTargetInfo;
- (void)_tip_background_extractStorageInfo;
- (void)_tip_background_validateProgressiveSupport:(TIPPartialImage *)partialImage;
- (void)_tip_background_clearNetworkContextVariables;
- (void)_tip_background_setFinalStateAfterFlushingDelegate:(TIPImageFetchOperationState)state;

// Load
- (void)_tip_background_dispatchLoadStartedFromSource:(TIPImageLoadSource)source;
- (void)_tip_background_loadFromNextSource;
- (void)_tip_background_loadFromMemory;
- (void)_tip_background_loadFromDisk;
- (void)_tip_background_loadFromOtherPipelineDisk;
- (void)_tip_background_loadFromAdditional;
- (void)_tip_background_loadImageURL:(NSURL *)imageURL fromNextAdditionalCache:(NSMutableArray<id<TIPImageAdditionalCache>> *)caches;
- (void)_tip_background_loadFromNetwork;

// Update
- (void)_tip_background_updateFailureToLoadFinalImage:(NSError *)error updateMetrics:(BOOL)updateMetrics;
- (void)_tip_background_updateWithProgress:(float)progress;
- (void)_tip_background_updateWithFinalImage:(TIPImageContainer *)image imageRenderLatency:(NSTimeInterval)latency URL:(NSURL *)URL source:(TIPImageLoadSource)source networkImageType:(nullable NSString *)imageType networkBytes:(NSUInteger)byteSize placeholder:(BOOL)placeholder;
- (void)_tip_background_updateWithPreviewImageEntry:(TIPImageCacheEntry *)entry source:(TIPImageLoadSource)source;
- (void)_tip_background_updateWithProgressiveImage:(UIImage *)image transformed:(BOOL)transformed imageRenderLatency:(NSTimeInterval)latency URL:(NSURL *)URL progress:(float)progress sourcePartialImage:(TIPPartialImage *)partialImage source:(TIPImageLoadSource)source;
- (void)_tip_background_updateWithFirstAnimatedImageFrame:(UIImage *)image imageRenderLatency:(NSTimeInterval)latency URL:(NSURL *)URL progress:(float)progress sourcePartialImage:(TIPPartialImage *)partialImage source:(TIPImageLoadSource)source;
- (void)_tip_background_updateWithCompletedMemoryEntry:(TIPImageMemoryCacheEntry *)entry;
- (void)_tip_background_updateWithPartialMemoryEntry:(TIPImageMemoryCacheEntry *)entry;
- (void)_tip_background_updateWithCompletedDiskEntry:(TIPImageDiskCacheEntry *)entry;
- (void)_tip_background_updateWithPartialDiskEntry:(TIPImageDiskCacheEntry *)entry tryOtherPipelineDiskCachesIfNeeded:(BOOL)tryOtherPipelines;

// Render Progress
- (void)_tip_background_processContinuedPartialEntry:(TIPPartialImage *)partialImage forURL:(NSURL *)URL source:(TIPImageLoadSource)source;
- (nullable UIImage *)_tip_background_progressiveImageGivenAppendResult:(TIPImageDecoderAppendResult)result partialImage:(TIPPartialImage *)partialImage renderCount:(NSUInteger)renderCount;
- (nullable UIImage *)_tip_background_firstFrameOfAnimatedImageIfNotYetProvidedFromPartialImage:(TIPPartialImage *)partialImage;
- (UIImage *)_tip_background_transformAndScaleImage:(UIImage *)image progress:(float)progress transformed:(BOOL *)transformed;
- (TIPImageContainer *)_tip_background_transformAndScaleImageContainer:(TIPImageContainer *)image progress:(float)progress transformed:(BOOL *)transformed;

// Create Cache Entry
- (nullable TIPImageCacheEntry *)_tip_background_createCacheEntryFromRaw:(BOOL)useRawImage permitPreviewFallback:(BOOL)previewFallback didFallbackToPreview:(out BOOL * __nullable)didFallbackToPreviewOut;
- (nullable TIPImageCacheEntry *)_tip_background_createCacheEntryFromPartialImage:(TIPPartialImage *)partialImage lastModified:(NSString *)lastModified URL:(NSURL *)URL;

// Cache propogation
- (void)_tip_background_propagateFinalImageFromSource:(TIPImageLoadSource)source;
- (void)_tip_background_propagatePartialImageFromNetwork:(TIPPartialImage *)partialImage lastModified:(NSString *)lastModified;
- (void)_tip_background_propagatePreviewImageFromDiskCache;

// Notifications
- (void)_tip_background_postDidStart;
- (void)_tip_background_postDidFinish;
- (void)_tip_background_postDidStartDownload;
- (void)_tip_background_postDidFinishDownloadingImageType:(NSString *)imageType sizeInBytes:(NSUInteger)byteSize;

// Execute
- (void)_tip_background_executeDelegateWork:(TIPImageFetchDelegateWorkBlock)block;
- (void)_tip_executeBackgroundWork:(dispatch_block_t)block;

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
    } _flags;
}

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (instancetype)initWithImagePipeline:(TIPImagePipeline *)pipeline request:(id<TIPImageFetchRequest>)request delegate:(id<TIPImageFetchDelegate>)delegate
{
    if (self = [super init]) {
        _imagePipeline = pipeline;
        _request = request;
        _metricsInternal = [[TIPImageFetchMetrics alloc] initProject];

        _backgroundQueue = dispatch_queue_create("image.fetch.queue", DISPATCH_QUEUE_SERIAL);
        atomic_init(&_state, TIPImageFetchOperationStateIdle);
        _networkContext = [[TIPImageFetchOperationNetworkStepContext alloc] init];

        [self _tip_initializeDelegate:delegate];
        [self _tip_extractBasicRequestInfo];
    }
    return self;
}

- (void)_tip_initializeDelegate:(nullable id<TIPImageFetchDelegate>)delegate
{
    _delegate = delegate;
    _flags.delegateSupportsAttemptWillStartCallbacks = ([delegate respondsToSelector:@selector(tip_imageFetchOperation:willAttemptToLoadFromSource:)] != NO);
    if (!delegate) {
        // nil delegate, just let the operation happen
    } else if ([delegate isKindOfClass:[TIPSimpleImageFetchDelegate class]]) {
        _strongDelegate = delegate;
    } else {
        // associate an object to perform the cancel on dealloc of the delegate
        TIPImageFetchDelegateDeallocHandler *handler = [[TIPImageFetchDelegateDeallocHandler alloc] initWithFetchOperation:self delegate:delegate];
        if (handler) {
            _delegateHandler = handler;
            // Use the reference as the unique key since a delegate could have multiple operations
            objc_setAssociatedObject(delegate, (__bridge const void *)(handler), handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

- (void)_tip_clearDelegateHandler
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

- (void)_tip_extractBasicRequestInfo
{
    _networkContext.imageDownloadRequest = [[TIPImageFetchDownloadRequest alloc] initWithRequest:_request];
    _loadingSources = [_request respondsToSelector:@selector(loadingSources)] ? [_request loadingSources] : TIPImageFetchLoadingSourcesAll;
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
        [self _tip_clearDelegateHandler];
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
        BOOL qos = NO;
        if (!wasEnqueued) {
            qos = [self respondsToSelector:@selector(setQualityOfService:)];
            [self willChangeValueForKey:@"queuePriority"];
            if (qos) {
                [self willChangeValueForKey:@"qualityOfService"];
            }
        }

        _networkContext.imageDownloadRequest.imageDownloadPriority = priority;

        if (!wasEnqueued) {
            if (qos) {
                [self didChangeValueForKey:@"qualityOfService"];
            }
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
    [self _tip_clearDelegateHandler];
    self.delegate = nil;
    self.strongDelegate = nil;
}

- (void)cancel
{
    [self _tip_executeBackgroundWork:^{
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
    [self _tip_executeBackgroundWork:^{
        if (!self->_flags.didStart) {
            self->_flags.didStart = 1;
            [self _tip_background_start];
        }
    }];
}

- (void)earlyCompleteOperationWithImageEntry:(TIPImageCacheEntry *)entry
{
    TIPAssert([NSThread isMainThread]);
    TIPAssert(!_flags.didStart);
    TIPAssert(entry.completeImage != nil);
    TIPAssert(_metrics == nil);
    TIPAssert(_metricsInternal != nil);

    [self willEnqueue];
    _flags.didStart = 1;
    _flags.isEarlyCompletion = 1;
    TIPLogDebug(@"%@%@, id=%@", NSStringFromSelector(_cmd), entry.completeImage, entry.identifier);

    _startTime = mach_absolute_time();
    self.state = TIPImageFetchOperationStateLoadingFromMemory;
    [self _tip_executeBackgroundWork:^{
        [self _tip_background_extractObservers];
        [self _tip_background_postDidStart];
    }];
    id<TIPImageFetchDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_imageFetchOperationDidStart:)]) {
        [delegate tip_imageFetchOperationDidStart:self];
    }

    [_metricsInternal startWithSource:TIPImageLoadSourceMemoryCache];

    _networkContext = nil;
    self.finalImageContainerRaw = entry.completeImage;
    id<TIPImageFetchResult> finalResult = [TIPImageFetchResultInternal resultWithImageContainer:entry.completeImage identifier:entry.identifier source:TIPImageLoadSourceMemoryCache URL:entry.completeImageContext.URL originalDimensions:self.finalImageContainerRaw.dimensions placeholder:entry.completeImageContext.treatAsPlaceholder transformed:NO];
    self.finalResult = finalResult;

    [_imagePipeline.memoryCache touchImageWithIdentifier:entry.identifier];
    [_imagePipeline.diskCache touchImageWithIdentifier:entry.identifier orSaveImageEntry:nil];

    [_metricsInternal finalWasHit:0.0];
    [_metricsInternal endSource];
    _metrics = _metricsInternal;
    _metricsInternal = nil;
    _finishTime = mach_absolute_time();

    TIPAssert(finalResult != nil);
    if (finalResult && [delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFinalImage:)]) {
        [delegate tip_imageFetchOperation:self didLoadFinalImage:finalResult];
    }
    [self _tip_executeBackgroundWork:^{
        [self _tip_background_postDidFinish];
    }];
    self.state = TIPImageFetchOperationStateSucceeded;
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
    return tempFile;
}

- (void)imageDownloadDidStart:(id<TIPImageDownloadContext>)context
{
    [self _tip_background_postDidStartDownload];
}

- (void)imageDownload:(id<TIPImageDownloadContext>)context didResetFromPartialImage:(TIPPartialImage *)oldPartialImage
{
    TIPAssert(!_flags.didReceiveFirstByte);
    [self _tip_background_clearNetworkContextVariables];
    if ([self supportsLoadingFromSource:TIPImageLoadSourceNetwork]) {
        [self _tip_background_updateWithProgress:0.0f];
    } else {
        // Not configured to do a normal network load, fail
        [self _tip_background_updateFailureToLoadFinalImage:[NSError errorWithDomain:TIPImageFetchErrorDomain code:TIPImageFetchErrorCouldNotLoadImage userInfo:nil] updateMetrics:YES];
        [_imagePipeline.downloader removeDelegate:self forContext:context];
    }
}

- (void)imageDownload:(id<TIPImageDownloadContext>)context didAppendBytes:(NSUInteger)byteCount toPartialImage:(TIPPartialImage *)partialImage result:(TIPImageDecoderAppendResult)result
{
    if ([self _tip_background_shouldAbort]) {
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
        UIImage *image = [self _tip_background_firstFrameOfAnimatedImageIfNotYetProvidedFromPartialImage:partialImage];
        const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
        if (image) {
            // First frame progress
            [self _tip_background_updateWithFirstAnimatedImageFrame:image imageRenderLatency:latency URL:self.imageURL progress:progress sourcePartialImage:partialImage source:_flags.wasResumedDownload ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork];
        }
    } else if (partialImage.isProgressive) {
        UIImage *image = [self _tip_background_progressiveImageGivenAppendResult:result partialImage:partialImage renderCount:_progressiveRenderCount];
        if (image) {
            // Progressive image progress
            BOOL transformed = NO;
            image = [self _tip_background_transformAndScaleImage:image progress:progress transformed:&transformed];
            const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
            _progressiveRenderCount++;
            [self _tip_background_updateWithProgressiveImage:image transformed:transformed imageRenderLatency:latency URL:self.imageURL progress:progress sourcePartialImage:partialImage source:_flags.wasResumedDownload ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork];
        }
    }

    // Always update the plain ol' progress
    [self _tip_background_updateWithProgress:progress];
}

- (void)imageDownload:(id<TIPImageDownloadContext>)context didCompleteWithPartialImage:(nullable TIPPartialImage *)partialImage lastModified:(nullable NSString *)lastModified byteSize:(NSUInteger)bytes imageType:(nullable NSString *)imageType image:(nullable TIPImageContainer *)image imageRenderLatency:(NSTimeInterval)latency statusCode:(NSInteger)statusCode error:(nullable NSError *)error
{
    const BOOL wasResuming = (_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming != nil);
    [self _tip_background_clearNetworkContextVariables];
    _networkContext.imageDownloadContext = nil;

    id<TIPImageFetchDownload> download = (id<TIPImageFetchDownload>)context;
    [_metricsInternal addNetworkMetrics:[download respondsToSelector:@selector(downloadMetrics)] ? download.downloadMetrics : nil forRequest:download.finalURLRequest imageType:imageType imageSizeInBytes:bytes imageDimensions:(image) ? image.dimensions : partialImage.dimensions];

    if (partialImage && !image) {
        [self _tip_background_propagatePartialImageFromNetwork:partialImage lastModified:lastModified];
    }

    if ([self _tip_background_shouldAbort]) {
        return;
    }

    if (image) {

        if (partialImage.hasGPSInfo) {
            // we should NEVER encounter an image with GPS info,
            // that would be a MAJOR security risk
            [[TIPGlobalConfiguration sharedInstance] postProblem:TIPProblemImageDownloadedHasGPSInfo userInfo:@{ TIPProblemInfoKeyImageURL : self.imageURL }];
        }

        [self _tip_background_updateWithFinalImage:image imageRenderLatency:latency URL:self.imageURL source:(_flags.wasResumedDownload ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork) networkImageType:imageType networkBytes:bytes placeholder:TIP_BITMASK_HAS_SUBSET_FLAGS(_networkContext.imageDownloadRequest.imageDownloadOptions, TIPImageFetchTreatAsPlaceholder)];
    } else {
        TIPAssert(error != nil);

        if (wasResuming && 416 /* Requested range not satisfiable */ == statusCode) {
            TIPAssert(!_flags.wasResumedDownload);
            if (!_flags.wasResumedDownload) {
                TIPLogWarning(@"Network resume yielded HTTP 416... retrying with full network load: %@", _networkContext.imageDownloadRequest.imageDownloadURL);
                [self _tip_background_loadFromNetwork];
                return;
            }
        }

        [self _tip_background_updateFailureToLoadFinalImage:error updateMetrics:YES];
    }
}

@end

@implementation TIPImageFetchOperation (Background)

#pragma mark Start / Abort

- (void)_tip_background_start
{
    _startTime = mach_absolute_time();
    if ([self _tip_background_shouldAbort]) {
        return;
    }

    self.state = TIPImageFetchOperationStateStarting;

    [self _tip_background_extractObservers];

    [self _tip_background_postDidStart];
    [self _tip_background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate){
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperationDidStart:)]) {
            [delegate tip_imageFetchOperationDidStart:self];
        }
    }];

    [self _tip_background_extractAdvancedRequestInfo];
    [self _tip_background_loadFromNextSource];
}

- (BOOL)_tip_background_shouldAbort
{
    if (self.isFinished || _flags.transitioningToFinishedState) {
        return YES;
    }

    if (_flags.cancelled) {
        NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain code:TIPImageFetchErrorCodeCancelled userInfo:nil];
        [self _tip_background_updateFailureToLoadFinalImage:error updateMetrics:YES];
        return YES;
    }

    if (_flags.invalidRequest) {
        NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain code:TIPImageFetchErrorCodeInvalidRequest userInfo:nil];
        [self _tip_background_updateFailureToLoadFinalImage:error updateMetrics:NO];
        return YES;
    }

    return NO;
}

#pragma mark Generate State

- (void)_tip_background_extractObservers
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

- (void)_tip_background_extractStorageInfo
{
    if (_flags.didExtractStorageInfo) {
        return;
    }

    NSTimeInterval TTL = [_request respondsToSelector:@selector(timeToLive)] ? [_request timeToLive] : -1.0;
    if (TTL <= 0.0) {
        TTL = TIPTimeToLiveDefault;
    }
    _networkContext.imageDownloadRequest.imageDownloadTTL = TTL;

    const TIPImageFetchOptions options = [_request respondsToSelector:@selector(options)] ? [_request options] : TIPImageFetchNoOptions;
    _networkContext.imageDownloadRequest.imageDownloadOptions = options;

    _flags.didExtractStorageInfo = 1;
}

- (void)_tip_background_extractAdvancedRequestInfo
{
    _networkContext.imageDownloadRequest.imageDownloadHydrationBlock = [_request respondsToSelector:@selector(imageRequestHydrationBlock)] ? _request.imageRequestHydrationBlock : nil;
    _progressiveLoadingPolicies = nil;
    id<TIPImageFetchDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:)]) {
        // could support progressive, prep the policy
        _progressiveLoadingPolicies = [_request respondsToSelector:@selector(progressiveLoadingPolicies)] ? [[_request progressiveLoadingPolicies] copy] : nil;
    }
}

- (void)_tip_background_extractTargetInfo
{
    if (_flags.didExtractTargetInfo) {
        return;
    }
    _targetDimensions = [_request respondsToSelector:@selector(targetDimensions)] ? [_request targetDimensions] : CGSizeZero;
    _targetContentMode = [_request respondsToSelector:@selector(targetContentMode)] ? [_request targetContentMode] : UIViewContentModeCenter;

    _flags.didExtractTargetInfo = 1;
}

- (void)_tip_background_validateProgressiveSupport:(TIPPartialImage *)partialImage
{
    if (!_flags.progressivePermissionValidated) {
        if (partialImage.state > TIPPartialImageStateLoadingHeaders) {
            id<TIPImageFetchDelegate> delegate = self.delegate;
            if (partialImage.progressive && [delegate respondsToSelector:@selector(tip_imageFetchOperation:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:)]) {
                TIPAssert(partialImage.type != nil);
                _progressiveLoadingPolicy = _progressiveLoadingPolicies[partialImage.type ?: @""] ?: [TIPImageFetchProgressiveLoadingPolicy defaultProgressiveLoadingPolicies][partialImage.type ?: @""];
                if (_progressiveLoadingPolicy) {
                    if ([delegate tip_imageFetchOperation:self shouldLoadProgressivelyWithIdentifier:self.imageIdentifier URL:self.imageURL imageType:partialImage.type originalDimensions:partialImage.dimensions]) {
                        _flags.permitsProgressiveLoading = 1;
                    }
                }
            }

            _flags.progressivePermissionValidated = 1;
        }
    }
}

- (void)_tip_background_clearNetworkContextVariables
{
    _networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming = nil;
    _networkContext.imageDownloadRequest.imageDownloadLastModified = nil;
    _networkContext.imageDownloadRequest.imageDownloadTemporaryFileForResuming = nil;
    _progressiveRenderCount = 0;
}

- (void)_tip_background_setFinalStateAfterFlushingDelegate:(TIPImageFetchOperationState)state
{
    TIPAssert(TIPImageFetchOperationStateIsFinished(state));
    _flags.transitioningToFinishedState = 1;
    [self _tip_background_executeDelegateWork:^(id<TIPImageFetchDelegate> __unused delegate) {
        [self _tip_executeBackgroundWork:^{
            self.state = state;
            self->_flags.transitioningToFinishedState = 0;
        }];
    }];
}

#pragma mark Load

- (void)_tip_background_dispatchLoadStartedFromSource:(TIPImageLoadSource)source
{
    if (_flags.delegateSupportsAttemptWillStartCallbacks) {
        [self _tip_background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate) {
            [delegate tip_imageFetchOperation:self willAttemptToLoadFromSource:source];
        }];
    }
}

- (void)_tip_background_loadFromNextSource
{
    if ([self _tip_background_shouldAbort]) {
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
            [self _tip_background_updateFailureToLoadFinalImage:[NSError errorWithDomain:TIPImageFetchErrorDomain code:TIPImageFetchErrorCouldNotLoadImage userInfo:nil] updateMetrics:NO];
            break;
        case TIPImageLoadSourceMemoryCache:
            [self _tip_background_loadFromMemory];
            break;
        case TIPImageLoadSourceDiskCache:
            [self _tip_background_loadFromDisk];
            break;
        case TIPImageLoadSourceAdditionalCache:
            [self _tip_background_loadFromAdditional];
            break;
        case TIPImageLoadSourceNetwork:
        case TIPImageLoadSourceNetworkResumed:
            [self _tip_background_loadFromNetwork];
            break;
    }
}

- (void)_tip_background_loadFromMemory
{
    self.state = TIPImageFetchOperationStateLoadingFromMemory;
    if (![self supportsLoadingFromSource:TIPImageLoadSourceMemoryCache]) {
        [self _tip_background_loadFromNextSource];
        return;
    } else {
        [self _tip_background_dispatchLoadStartedFromSource:TIPImageLoadSourceMemoryCache];
    }

    TIPImageMemoryCacheEntry *entry = [_imagePipeline.memoryCache imageEntryForIdentifier:self.imageIdentifier];
    [self _tip_background_updateWithCompletedMemoryEntry:entry];
}

- (void)_tip_background_loadFromDisk
{
    self.state = TIPImageFetchOperationStateLoadingFromDisk;
    if (![self supportsLoadingFromSource:TIPImageLoadSourceDiskCache]) {
        [self _tip_background_loadFromNextSource];
        return;
    } else {
        [self _tip_background_dispatchLoadStartedFromSource:TIPImageLoadSourceDiskCache];
    }

    // Just load the meta-data (options == TIPImageDiskCacheFetchOptionsNone)
    TIPImageDiskCacheEntry *entry = [_imagePipeline.diskCache imageEntryForIdentifier:self.imageIdentifier options:TIPImageDiskCacheFetchOptionsNone decoderConfigMap:_decoderConfigMap];
    [self _tip_background_updateWithCompletedDiskEntry:entry];
}

- (void)_tip_background_loadFromOtherPipelineDisk
{
    TIPAssert(self.state == TIPImageFetchOperationStateLoadingFromDisk);

    [self _tip_background_extractStorageInfo]; // need TTL and options
    NSMutableDictionary<NSString *, TIPImagePipeline *> *pipelines = [[TIPImagePipeline allRegisteredImagePipelines] mutableCopy];
    [pipelines removeObjectForKey:_imagePipeline.identifier];
    NSArray<TIPImagePipeline *> *otherPipelines = [pipelines allValues];
    tip_dispatch_async_autoreleasing([TIPGlobalConfiguration sharedInstance].queueForDiskCaches, ^{
        [self _tip_diskCache_loadFromOtherPipelines:otherPipelines startMachTime:mach_absolute_time()];
    });
}

- (void)_tip_diskCache_loadFromOtherPipelines:(NSArray<TIPImagePipeline *> *)pipelines startMachTime:(uint64_t)startMachTime
{
    for (TIPImagePipeline *nextPipeline in pipelines) {
        // look in the pipeline's disk cache
        if ([self _tip_diskCache_attemptLoadFromOtherPipelineDisk:nextPipeline startMachTime:startMachTime]) {
            // success!
            return;
        }
    }

    // Ran out of "next" pipelines, load from next source
    [self _tip_diskCache_completeLoadFromOtherPipelineDisk:nil URL:nil latency:TIPComputeDuration(startMachTime, mach_absolute_time()) placeholder:NO];
}

- (BOOL)_tip_diskCache_attemptLoadFromOtherPipelineDisk:(TIPImagePipeline *)nextPipeline startMachTime:(uint64_t)startMachTime
{
    TIPImageDiskCache *nextDiskCache = nextPipeline.diskCache;
    if (nextDiskCache) {

        // pull out the on disk path to the desired entry if available
        TIPCompleteImageEntryContext *context = nil;
        NSString *filePath = [nextDiskCache diskCache_imageEntryFilePathForIdentifier:self.imageIdentifier hitShouldMoveEntryToHead:NO context:&context];

        // only accept an exact match (URLs are equal)
        if (filePath && [context.URL isEqual:self.imageURL]) {

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
            [_imagePipeline.diskCache diskCache_updateImageEntry:entry forciblyReplaceExisting:!context.treatAsPlaceholder];

            // complete the loop by retrieving entry (with UIImage) from disk cache
            entry = [_imagePipeline.diskCache diskCache_imageEntryForIdentifier:entry.identifier options:TIPImageDiskCacheFetchOptionCompleteImage decoderConfigMap:_decoderConfigMap];

            // did we get an image?
            TIPImageContainer *image = entry.completeImage;
            if (image) {

                // complete
                [self _tip_diskCache_completeLoadFromOtherPipelineDisk:image URL:context.URL latency:TIPComputeDuration(startMachTime, mach_absolute_time()) placeholder:context.treatAsPlaceholder];

                // success!
                return YES;
            }
        }
    }

    // didn't succeed
    return NO;
}

- (void)_tip_diskCache_completeLoadFromOtherPipelineDisk:(nullable TIPImageContainer *)image URL:(nullable NSURL *)URL latency:(NSTimeInterval)latency placeholder:(BOOL)placeholder
{
    if (latency > 0.150) {
        TIPLogWarning(@"Other Pipeline Duration (%@): %.3fs", (image != nil) ? @"HIT" : @"MISS", latency);
    } else if (image) {
        TIPLogDebug(@"Other Pipeline Duration (HIT): %.3fs", latency);
    }

    [self _tip_executeBackgroundWork:^{
        if (image && URL) {
            [self _tip_background_updateWithFinalImage:image imageRenderLatency:0.0 URL:URL source:TIPImageLoadSourceDiskCache networkImageType:nil networkBytes:0 placeholder:placeholder];
        } else {
            [self _tip_background_loadFromNextSource];
        }
    }];
}

- (void)_tip_background_loadFromAdditional
{
    self.state = TIPImageFetchOperationStateLoadingFromAdditionalCache;
    if (![self supportsLoadingFromSource:TIPImageLoadSourceAdditionalCache]) {
        [self _tip_background_loadFromNextSource];
        return;
    } else {
        [self _tip_background_dispatchLoadStartedFromSource:TIPImageLoadSourceAdditionalCache];
    }

    NSMutableArray<id<TIPImageAdditionalCache>> *additionalCaches = [_imagePipeline.additionalCaches mutableCopy];
    [self _tip_background_loadImageURL:self.imageURL fromNextAdditionalCache:additionalCaches];
}

- (void)_tip_background_loadImageURL:(NSURL *)imageURL fromNextAdditionalCache:(NSMutableArray<id<TIPImageAdditionalCache>> *)caches
{
    if (caches.count == 0) {
        [self _tip_background_loadFromNextSource];
        return;
    }

    id<TIPImageAdditionalCache> nextCache = caches.firstObject;
    [caches removeObjectAtIndex:0];
    [nextCache tip_retrieveImageForURL:imageURL completion:^(UIImage *image) {
        [self _tip_executeBackgroundWork:^{
            if ([self _tip_background_shouldAbort]) {
                return;
            }

            if (image) {
                [self _tip_background_updateWithFinalImage:[[TIPImageContainer alloc] initWithImage:image] imageRenderLatency:0.0 URL:imageURL source:TIPImageLoadSourceAdditionalCache networkImageType:nil networkBytes:0 placeholder:TIP_BITMASK_HAS_SUBSET_FLAGS(self->_networkContext.imageDownloadRequest.imageDownloadOptions, TIPImageFetchTreatAsPlaceholder)];
            } else {
                [self _tip_background_loadImageURL:imageURL fromNextAdditionalCache:caches];
            }
        }];
    }];
}

- (void)_tip_background_loadFromNetwork
{
    self.state = TIPImageFetchOperationStateLoadingFromNetwork;

    if (!_imagePipeline.downloader) {
        [self _tip_background_updateFailureToLoadFinalImage:[NSError errorWithDomain:TIPImageFetchErrorDomain code:TIPImageFetchErrorCouldNotDownloadImage userInfo:nil] updateMetrics:YES];
        return;
    }

    if (![self supportsLoadingFromSource:TIPImageLoadSourceNetwork]) {
        if (![self supportsLoadingFromSource:TIPImageLoadSourceNetworkResumed] || !_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming) {
            // if full loads not OK and resuming not OK - fail
            [self _tip_background_updateFailureToLoadFinalImage:[NSError errorWithDomain:TIPImageFetchErrorDomain code:TIPImageFetchErrorCouldNotLoadImage userInfo:nil] updateMetrics:YES];
            return;
        } // else if full loads not OK, but resuming is OK - continue
    }

    // Start loading
    [self _tip_background_extractStorageInfo];
    const TIPImageLoadSource loadSource = (_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming != nil) ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork;
    [self _tip_background_dispatchLoadStartedFromSource:loadSource];
    _networkContext.imageDownloadContext = [_imagePipeline.downloader fetchImageWithDownloadDelegate:self];
}

#pragma mark Update

- (void)_tip_background_updateFailureToLoadFinalImage:(NSError *)error updateMetrics:(BOOL)updateMetrics
{
    TIPAssert(error != nil);
    TIPAssert(_metrics == nil);
    TIPAssert(_metricsInternal != nil);
    TIPLogDebug(@"Failed to Load Image: %@", @{ @"id" : self.imageIdentifier ?: @"<null>", @"URL" : self.imageURL ?: @"<null>", @"error" : error ?: @"<null>" });

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

    [self _tip_background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate) {
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didFailToLoadFinalImage:)]) {
            [delegate tip_imageFetchOperation:self didFailToLoadFinalImage:error];
        }
    }];
    [self _tip_background_postDidFinish];
    [self _tip_background_setFinalStateAfterFlushingDelegate:(didCancel) ? TIPImageFetchOperationStateCancelled : TIPImageFetchOperationStateFailed];
}

- (void)_tip_background_updateWithFinalImage:(TIPImageContainer *)image imageRenderLatency:(NSTimeInterval)latency URL:(NSURL *)URL source:(TIPImageLoadSource)source networkImageType:(nullable NSString *)imageType networkBytes:(NSUInteger)byteSize placeholder:(BOOL)placeholder
{
    TIPAssert(image != nil);
    TIPAssert(_metrics == nil);
    TIPAssert(_metricsInternal != nil);
    [self _tip_background_extractTargetInfo];
    self.finalImageContainerRaw = image;
    const uint64_t startMachTime = mach_absolute_time();
    BOOL transformed = NO;
    TIPImageContainer *finalImageContainer = [self _tip_background_transformAndScaleImageContainer:image progress:1.f transformed:&transformed];
    _flags.finalImageWasTransformed = transformed;
    latency += TIPComputeDuration(startMachTime, mach_absolute_time());
    id<TIPImageFetchResult> finalResult = [TIPImageFetchResultInternal resultWithImageContainer:finalImageContainer identifier:self.imageIdentifier source:source URL:URL originalDimensions:image.dimensions placeholder:placeholder transformed:transformed];
    self.finalResult = finalResult;
    self.progress = 1.0f;

    [_metricsInternal finalWasHit:latency];
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
    if (sourceWasNetwork && byteSize > 0) {
        [self _tip_background_postDidFinishDownloadingImageType:imageType sizeInBytes:byteSize];
    }

    TIPAssert(finalResult != nil);
    if (!finalResult) {
        self.error = [NSError errorWithDomain:TIPImageFetchErrorDomain code:TIPImageFetchErrorCodeUnknown userInfo:nil];
        [self _tip_background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate) {
            if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didFailToLoadFinalImage:)]) {
                [delegate tip_imageFetchOperation:self didFailToLoadFinalImage:self.error];
            }
        }];
        [self _tip_background_postDidFinish];
        [self _tip_background_setFinalStateAfterFlushingDelegate:TIPImageFetchOperationStateFailed];
        return;
    }

    [self _tip_background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate){
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFinalImage:)]) {
            [delegate tip_imageFetchOperation:self didLoadFinalImage:finalResult];
        }
    }];

    [self _tip_background_postDidFinish];
    [self _tip_background_propagateFinalImageFromSource:source];
    [self _tip_background_setFinalStateAfterFlushingDelegate:TIPImageFetchOperationStateSucceeded];
}

- (void)_tip_background_postDidStart
{
    for (id<TIPImagePipelineObserver> observer in _observers) {
        if ([observer respondsToSelector:@selector(tip_imageFetchOperationDidStart:)]) {
            [observer tip_imageFetchOperationDidStart:self];
        }
    }
}

- (void)_tip_background_postDidFinish
{
    for (id<TIPImagePipelineObserver> observer in _observers) {
        if ([observer respondsToSelector:@selector(tip_imageFetchOperationDidFinish:)]) {
            [observer tip_imageFetchOperationDidFinish:self];
        }
    }
}

- (void)_tip_background_postDidStartDownload
{
    for (id<TIPImagePipelineObserver> observer in _observers) {
        if ([observer respondsToSelector:@selector(tip_imageFetchOperation:didStartDownloadingImageAtURL:)]) {
            [observer tip_imageFetchOperation:self didStartDownloadingImageAtURL:self.imageURL];
        }
    }
}

- (void)_tip_background_postDidFinishDownloadingImageType:(NSString *)imageType sizeInBytes:(NSUInteger)byteSize
{
    for (id<TIPImagePipelineObserver> observer in _observers) {
        if ([observer respondsToSelector:@selector(tip_imageFetchOperation:didFinishDownloadingImageAtURL:imageType:sizeInBytes:dimensions:wasResumed:)]) {
            [observer tip_imageFetchOperation:self didFinishDownloadingImageAtURL:self.imageURL imageType:imageType sizeInBytes:byteSize dimensions:self.finalImageContainerRaw.dimensions wasResumed:(self.finalResult.imageSource == TIPImageLoadSourceNetworkResumed)];
        }
    }
}

- (void)_tip_background_updateWithPreviewImageEntry:(TIPImageCacheEntry *)entry source:(TIPImageLoadSource)source
{
    TIPBoolBlock block = ^(BOOL canContinue) {
        if ([self _tip_background_shouldAbort]) {
            return;
        } else if (!canContinue) {
            NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain code:TIPImageFetchErrorCodeCancelledAfterLoadingPreview userInfo:nil];
            [self _tip_background_updateFailureToLoadFinalImage:error updateMetrics:YES];
            if (TIPImageLoadSourceDiskCache == source) {
                [self _tip_background_propagatePreviewImageFromDiskCache];
            }
        } else {
            if (TIPImageLoadSourceMemoryCache == source) {
                [self _tip_background_updateWithPartialMemoryEntry:(id)entry];
            } else if (TIPImageLoadSourceDiskCache == source) {
                [self _tip_background_updateWithPartialDiskEntry:(id)entry tryOtherPipelineDiskCachesIfNeeded:NO];
            } else {
                [self _tip_background_loadFromNextSource];
            }
        }
    };

    [self _tip_background_extractTargetInfo];

    TIPImageContainer *image = entry.completeImage;
    TIPAssert(image != nil);

    self.previewImageContainerRaw = image;
    const uint64_t startMachTime = mach_absolute_time();
    BOOL transformed = NO;
    TIPImageContainer *previewImageContainer = [self _tip_background_transformAndScaleImageContainer:image progress:-1.f transformed:&transformed];
    _flags.previewImageWasTransformed = transformed;
    const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
    id<TIPImageFetchResult> previewResult = [TIPImageFetchResultInternal resultWithImageContainer:previewImageContainer identifier:self.imageIdentifier source:source URL:entry.completeImageContext.URL originalDimensions:image.dimensions placeholder:entry.completeImageContext.treatAsPlaceholder transformed:transformed];
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
        [self _tip_background_executeDelegateWork:^(id<TIPImageFetchDelegate> blockDelegate) {
            if ([blockDelegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadPreviewImage:completion:)]) {
                [blockDelegate tip_imageFetchOperation:self didLoadPreviewImage:previewResult completion:^(TIPImageFetchPreviewLoadedBehavior behavior) {
                    [self _tip_executeBackgroundWork:^{
                        block(TIPImageFetchPreviewLoadedBehaviorContinueLoading == behavior);
                    }];
                }];
            } else {
                [self _tip_executeBackgroundWork:^{
                    block(YES);
                }];
            }
        }];
    } else {
        block(YES);
    }
}

- (void)_tip_background_updateWithFirstAnimatedImageFrame:(UIImage *)image imageRenderLatency:(NSTimeInterval)latency URL:(NSURL *)URL progress:(float)progress sourcePartialImage:(TIPPartialImage *)partialImage source:(TIPImageLoadSource)source
{
    id<TIPImageFetchDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFirstAnimatedImageFrame:progress:)]) {
        return;
    }

    TIPAssert(!isnan(progress) && !isinf(progress));
    self.progress = progress;
    const uint64_t startMachTime = mach_absolute_time();
    UIImage *firstAnimatedImage = [image tip_scaledImageWithTargetDimensions:_targetDimensions contentMode:_targetContentMode];
    TIPImageContainer *firstAnimatedImageFrameContainer = (firstAnimatedImage) ? [[TIPImageContainer alloc] initWithImage:firstAnimatedImage] : nil;
    latency += TIPComputeDuration(startMachTime, mach_absolute_time());
    id<TIPImageFetchResult> progressiveResult = [TIPImageFetchResultInternal resultWithImageContainer:firstAnimatedImageFrameContainer identifier:self.imageIdentifier source:source URL:URL originalDimensions:[image tip_dimensions] placeholder:NO transformed:NO];
    self.progressiveResult = progressiveResult;

    [_metricsInternal progressiveFrameWasHit:latency];

    TIPLogDebug(@"Loaded First Animated Image Frame: %@", @{
                                                            @"id" : self.imageIdentifier,
                                                            @"URL" : self.imageURL,
                                                            @"originalDimensions" : NSStringFromCGSize(partialImage.dimensions),
                                                            @"finalDimensions" : NSStringFromCGSize([firstAnimatedImageFrameContainer dimensions]),
                                                            @"source" : @(_flags.wasResumedDownload ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork),
                                                            @"store" : _imagePipeline.identifier,
                                                            @"resumed" : @(_flags.wasResumedDownload),
                                                            });

    TIPAssert(progressiveResult != nil);
    if (progressiveResult) {
        [self _tip_background_executeDelegateWork:^(id<TIPImageFetchDelegate> blockDelegate) {
            if ([blockDelegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFirstAnimatedImageFrame:progress:)]) {
                [blockDelegate tip_imageFetchOperation:self didLoadFirstAnimatedImageFrame:progressiveResult progress:progress];
            }
        }];
    }
}

- (void)_tip_background_updateWithProgressiveImage:(UIImage *)image transformed:(BOOL)transformed imageRenderLatency:(NSTimeInterval)latency URL:(NSURL *)URL progress:(float)progress sourcePartialImage:(TIPPartialImage *)partialImage source:(TIPImageLoadSource)source
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
    id<TIPImageFetchResult> progressiveResult = [TIPImageFetchResultInternal resultWithImageContainer:progressContainer identifier:self.imageIdentifier source:source URL:URL originalDimensions:[image tip_dimensions] placeholder:NO transformed:transformed];
    self.progressiveResult = progressiveResult;

    [_metricsInternal progressiveFrameWasHit:latency];

    TIPLogDebug(@"Loaded Progressive Image: %@", @{
                                                   @"progress" : @(progress),
                                                   @"id" : self.imageIdentifier,
                                                   @"URL" : URL,
                                                   @"originalDimensions" : NSStringFromCGSize(partialImage.dimensions),
                                                   @"finalDimensions" : NSStringFromCGSize([self.progressiveResult.imageContainer dimensions]),
                                                   @"source" : @(source),
                                                   @"store" : _imagePipeline.identifier,
                                                   @"resumed" : @(_flags.wasResumedDownload),
                                                   });

    TIPAssert(progressiveResult != nil);
    if (progressiveResult) {
        [self _tip_background_executeDelegateWork:^(id<TIPImageFetchDelegate> blockDelegate) {
            if ([blockDelegate respondsToSelector:@selector(tip_imageFetchOperation:didUpdateProgressiveImage:progress:)]) {
                [blockDelegate tip_imageFetchOperation:self didUpdateProgressiveImage:progressiveResult progress:progress];
            }
        }];
    }
}

- (void)_tip_background_updateWithProgress:(float)progress
{
    TIPAssert(!isnan(progress) && !isinf(progress));
    self.progress = progress;

    [self _tip_background_executeDelegateWork:^(id<TIPImageFetchDelegate> delegate) {
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didUpdateProgress:)]) {
            [delegate tip_imageFetchOperation:self didUpdateProgress:progress];
        }
    }];
}

- (void)_tip_background_updateWithCompletedMemoryEntry:(TIPImageMemoryCacheEntry *)entry
{
    if ([self _tip_background_shouldAbort]) {
        return;
    }

    TIPImageContainer *image = entry.completeImage;
    if (image) {
        NSURL *completeImageURL = entry.completeImageContext.URL;
        const BOOL isFinalImage = [completeImageURL isEqual:self.imageURL];

        if (isFinalImage) {
            [self _tip_background_updateWithFinalImage:image imageRenderLatency:0.0 URL:completeImageURL source:TIPImageLoadSourceMemoryCache networkImageType:nil networkBytes:0 placeholder:entry.completeImageContext.treatAsPlaceholder];
            return;
        }

        if (!self.previewResult) {
            [self _tip_background_updateWithPreviewImageEntry:entry source:TIPImageLoadSourceMemoryCache];
            return;
        }
    }

    // continue
    [self _tip_background_updateWithPartialMemoryEntry:entry];
}

- (void)_tip_background_updateWithPartialMemoryEntry:(TIPImageMemoryCacheEntry *)entry
{
    if ([self _tip_background_shouldAbort]) {
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
                TIPImageDiskCacheEntry * const diskEntry = [diskCache imageEntryForIdentifier:entryIdentifier options:TIPImageDiskCacheFetchOptionTemporaryFile decoderConfigMap:_decoderConfigMap];
                TIPImageDiskCacheTemporaryFile *diskTempFile = diskEntry.tempFile;
                if (!diskTempFile) {
                    diskTempFile = [_imagePipeline.diskCache openTemporaryFileForImageIdentifier:entry.identifier];
                    [diskTempFile appendData:partialImage.data];
                }
                _networkContext.imageDownloadRequest.imageDownloadTemporaryFileForResuming = diskTempFile;
            }

            [self _tip_background_processContinuedPartialEntry:partialImage forURL:partialImageContext.URL source:TIPImageLoadSourceMemoryCache];

            _flags.shouldJumpToResumingDownload = 1;
        }
    }

    // continue
    [self _tip_background_loadFromNextSource];
}

- (void)_tip_background_updateWithCompletedDiskEntry:(TIPImageDiskCacheEntry *)entry
{
    if ([self _tip_background_shouldAbort]) {
        return;
    }

    if (entry.completeImageContext) {
        NSURL *completeImageURL = entry.completeImageContext.URL;
        const CGSize dimensions = entry.completeImageContext.dimensions;
        const CGSize currentDimensions = self.previewResult.imageContainer.dimensions;
        const BOOL isFinal = [completeImageURL isEqual:self.imageURL];
        if (isFinal || (dimensions.width * dimensions.height > currentDimensions.width * currentDimensions.height)) {
            // Metadata checks out, load the actual complete image
            entry = [_imagePipeline.diskCache imageEntryForIdentifier:entry.identifier options:TIPImageDiskCacheFetchOptionCompleteImage decoderConfigMap:_decoderConfigMap];
            if ([completeImageURL isEqual:entry.completeImageContext.URL]) {
                TIPImageContainer *image = entry.completeImage;
                if (image) {
                    if (isFinal) {
                        [self _tip_background_updateWithFinalImage:image imageRenderLatency:0.0 URL:completeImageURL source:TIPImageLoadSourceDiskCache networkImageType:nil networkBytes:0 placeholder:entry.completeImageContext.treatAsPlaceholder];
                        return;
                    }

                    if (!self.previewResult) {
                        [self _tip_background_updateWithPreviewImageEntry:entry source:TIPImageLoadSourceDiskCache];
                        return;
                    }
                }
            }
        }
    }

    [self _tip_background_updateWithPartialDiskEntry:entry tryOtherPipelineDiskCachesIfNeeded:YES];
}

- (void)_tip_background_updateWithPartialDiskEntry:(TIPImageDiskCacheEntry *)entry tryOtherPipelineDiskCachesIfNeeded:(BOOL)tryOtherPipelines
{
    if ([self _tip_background_shouldAbort]) {
        return;
    }

    if (entry.partialImageContext && [self supportsLoadingFromSource:TIPImageLoadSourceNetworkResumed]) {
        const CGSize dimensions = entry.completeImageContext.dimensions;
        const BOOL isFinal = [self.imageURL isEqual:entry.partialImageContext.URL];
        BOOL isReasonableDataRemainingAndLarger = NO;
        [self _tip_background_extractTargetInfo];
        if (!isFinal && TIPSizeGreaterThanZero(_targetDimensions) && (dimensions.width * dimensions.height > _targetDimensions.width * _targetDimensions.height)) {
            double ratio = (dimensions.width * dimensions.height) / (_targetDimensions.width * _targetDimensions.height);
            NSUInteger remainingBytes = (entry.partialImageContext.expectedContentLength > entry.partialFileSize) ? entry.partialImageContext.expectedContentLength - entry.partialFileSize : NSUIntegerMax;
            NSUInteger hypotheticalBytes = (entry.partialImageContext.expectedContentLength) ?: 0;
            hypotheticalBytes = (NSUInteger)((double)hypotheticalBytes / ratio);
            isReasonableDataRemainingAndLarger = remainingBytes < hypotheticalBytes;
        }
        if (isFinal || isReasonableDataRemainingAndLarger) {
            // meta-data checks out, load the actual partial image
            entry = [_imagePipeline.diskCache imageEntryForIdentifier:entry.identifier options:(TIPImageDiskCacheFetchOptionPartialImage | TIPImageDiskCacheFetchOptionTemporaryFile) decoderConfigMap:_decoderConfigMap];
            if ([self.imageURL isEqual:entry.partialImageContext.URL] && entry.partialImage && entry.tempFile) {
                _networkContext.imageDownloadRequest.imageDownloadLastModified = entry.partialImageContext.lastModified;
                _networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming = entry.partialImage;
                _networkContext.imageDownloadRequest.imageDownloadTemporaryFileForResuming = entry.tempFile;

                [self _tip_background_processContinuedPartialEntry:entry.partialImage forURL:entry.partialImageContext.URL source:TIPImageLoadSourceDiskCache];

                _flags.shouldJumpToResumingDownload = 1;
            }
        }
    }

    if (tryOtherPipelines) {
        [self _tip_background_loadFromOtherPipelineDisk];
    } else {
        [self _tip_background_loadFromNextSource];
    }
}

#pragma mark Render Progress

- (TIPImageContainer *)_tip_background_transformAndScaleImageContainer:(TIPImageContainer *)image progress:(float)progress transformed:(BOOL *)transformed
{
    TIPImageContainer *outputImage;
    if (image.isAnimated) {
        outputImage = [image scaleToTargetDimensions:_targetDimensions contentMode:_targetContentMode] ?: image;
        *transformed = NO;
    } else {
        UIImage *scaledImage = [self _tip_background_transformAndScaleImage:image.image progress:progress transformed:transformed];
        outputImage = [[TIPImageContainer alloc] initWithImage:scaledImage];
    }
    return outputImage;
}

- (UIImage *)_tip_background_transformAndScaleImage:(UIImage *)image progress:(float)progress transformed:(BOOL *)transformed
{
    *transformed = NO;
    [self _tip_background_extractTargetInfo];
    if (_transformer) {
        UIImage *transformedImage = [_transformer tip_transformImage:image withProgress:progress hintTargetDimensions:_targetDimensions hintTargetContentMode:_targetContentMode forImageFetchOperation:self];
        if (transformedImage) {
            image = transformedImage;
            *transformed = YES;
        }
    }
    image = [image tip_scaledImageWithTargetDimensions:_targetDimensions contentMode:_targetContentMode];
    TIPAssert(image != nil);
    return image;
}

- (void)_tip_background_processContinuedPartialEntry:(TIPPartialImage *)partialImage forURL:(NSURL *)URL source:(TIPImageLoadSource)source
{
    [self _tip_background_validateProgressiveSupport:partialImage];

    // If we have a partial image with enough progress to display, let's decode it and use it as a progress image
    if (_flags.permitsProgressiveLoading && partialImage.frameCount > 0 && [self.delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadPreviewImage:completion:)]) {
        const uint64_t startMachTime = mach_absolute_time();
        UIImage *progressImage = [self _tip_background_progressiveImageGivenAppendResult:TIPImageDecoderAppendResultDidLoadFrame partialImage:partialImage renderCount:0];
        if (progressImage) {
            const float progress = partialImage.progress;
            BOOL transformed = NO;
            progressImage = [self _tip_background_transformAndScaleImage:progressImage progress:progress transformed:&transformed];
            const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
            [self _tip_background_updateWithProgressiveImage:progressImage transformed:transformed imageRenderLatency:latency URL:URL progress:progress sourcePartialImage:partialImage source:source];
        }
    }
}

- (nullable UIImage *)_tip_background_progressiveImageGivenAppendResult:(TIPImageDecoderAppendResult)result partialImage:(TIPPartialImage *)partialImage renderCount:(NSUInteger)renderCount
{
    [self _tip_background_validateProgressiveSupport:partialImage];

    BOOL shouldRender = NO;
    TIPImageDecoderRenderMode mode = TIPImageDecoderRenderModeCompleteImage;
    if (partialImage.state > TIPPartialImageStateLoadingHeaders) {
        shouldRender = YES;
        if (_flags.permitsProgressiveLoading) {

            TIPImageFetchProgress fetchProgress = TIPImageFetchProgressNone;
            if (TIPImageDecoderAppendResultDidLoadFrame == result) {
                fetchProgress = TIPImageFetchProgressFullFrame;
            } else if (partialImage.state > TIPPartialImageStateLoadingHeaders) {
                fetchProgress = TIPImageFetchProgressPartialFrame;
            }
            TIPImageFetchProgressUpdateBehavior behavior = TIPImageFetchProgressUpdateBehaviorNone;
            if (_progressiveLoadingPolicy) {
                behavior = [_progressiveLoadingPolicy tip_imageFetchOperation:self behaviorForProgress:fetchProgress frameCount:partialImage.frameCount progress:partialImage.progress type:partialImage.type dimensions:partialImage.dimensions renderCount:renderCount];
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

    TIPImageContainer *image = (shouldRender) ? [partialImage renderImageWithMode:mode decoded:YES] : nil;
    return image.image;
}

- (nullable UIImage *)_tip_background_firstFrameOfAnimatedImageIfNotYetProvidedFromPartialImage:(TIPPartialImage *)partialImage
{
    if (partialImage.isAnimated && partialImage.frameCount >= 1 && !_flags.didReceiveFirstAnimatedFrame) {
        if ([self.delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFirstAnimatedImageFrame:progress:)]) {
            TIPImageContainer *imageContainer = [partialImage renderImageWithMode:TIPImageDecoderRenderModeFullFrameProgress decoded:NO];
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

- (nullable TIPImageCacheEntry *)_tip_background_createCacheEntryFromRaw:(BOOL)useRawImage permitPreviewFallback:(BOOL)previewFallback didFallbackToPreview:(out BOOL * __nullable)didFallbackToPreviewOut
{
    TIPImageCacheEntry *entry = nil;
    TIPImageContainer *image = (useRawImage) ? self.finalImageContainerRaw : self.finalResult.imageContainer;
    NSURL *imageURL = self.finalResult.imageURL;
    BOOL isPlaceholder = self.finalResult.imageIsTreatedAsPlaceholder;
    if (!image && previewFallback) {
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
        [self _tip_helper_hydrateNewContext:context imageURL:imageURL placeholder:isPlaceholder];

        entry.identifier = self.imageIdentifier;
    }

    return entry;
}

- (nullable TIPImageCacheEntry *)_tip_background_createCacheEntryFromPartialImage:(TIPPartialImage *)partialImage lastModified:(NSString *)lastModified URL:(NSURL *)imageURL
{
    TIPImageCacheEntry *entry = nil;
    if (partialImage && lastModified && partialImage.state > TIPPartialImageStateLoadingHeaders && TIP_BITMASK_EXCLUDES_FLAGS(_networkContext.imageDownloadRequest.imageDownloadOptions, TIPImageFetchTreatAsPlaceholder)) {
        entry = [[TIPImageCacheEntry alloc] init];
        TIPImageCacheEntryContext *context = nil;

        TIPPartialImageEntryContext *partialContext = [[TIPPartialImageEntryContext alloc] init];
        partialContext.dimensions = partialImage.dimensions;
        partialContext.expectedContentLength = partialImage.expectedContentLength;
        partialContext.lastModified = lastModified;
        partialContext.animated = partialImage.isAnimated;

        entry.partialImageContext = partialContext;
        entry.partialImage = partialImage;
        context = partialContext;
        [self _tip_helper_hydrateNewContext:context imageURL:imageURL placeholder:NO];

        entry.identifier = self.imageIdentifier;
    }

    return entry;
}

- (void)_tip_helper_hydrateNewContext:(TIPImageCacheEntryContext *)context imageURL:(NSURL *)imageURL placeholder:(BOOL)placeholder
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

#pragma mark Cache propogation

- (void)_tip_background_propagatePartialImageFromNetwork:(TIPPartialImage *)partialImage lastModified:(NSString *)lastModified
{
    [self _tip_background_extractStorageInfo];

    if (!_flags.didReceiveFirstByte || self.finalImageContainerRaw) {
        return;
    }

    TIPImageCacheEntry *entry = [self _tip_background_createCacheEntryFromPartialImage:partialImage lastModified:lastModified URL:self.progressiveResult.imageURL];
    TIPAssert(!entry || (entry.partialImage && entry.partialImageContext));
    if (entry) {
        [_imagePipeline.memoryCache updateImageEntry:entry forciblyReplaceExisting:NO];
    }
}

- (void)_tip_background_propagatePreviewImageFromDiskCache
{
    [self _tip_background_extractStorageInfo];

    if (!self.previewImageContainerRaw || self.finalImageContainerRaw) {
        return;
    }

    TIPImageCacheEntry *entry = nil;

    // First, the memory cache
    entry = [self _tip_background_createCacheEntryFromRaw:YES permitPreviewFallback:YES didFallbackToPreview:NULL];
    TIPAssert(!entry || (entry.completeImage && entry.completeImageContext));
    if (entry) {
        [_imagePipeline.memoryCache updateImageEntry:entry forciblyReplaceExisting:NO];
    }

    // Second, the rendered cache
    BOOL didFallbackToPreview = NO;
    entry = [self _tip_background_createCacheEntryFromRaw:NO permitPreviewFallback:YES didFallbackToPreview:&didFallbackToPreview];
    TIPAssert(!entry || (entry.completeImage && entry.completeImageContext));
    if (entry) {
        const BOOL wasTransformed = (didFallbackToPreview) ? _flags.previewImageWasTransformed : _flags.finalImageWasTransformed;
        if (!wasTransformed || _transfomerIdentifier) {
            [_imagePipeline.renderedCache storeImageEntry:entry transformerIdentifier:(wasTransformed) ? _transfomerIdentifier : nil];
        }
    }
}

- (void)_tip_background_propagateFinalImageFromSource:(TIPImageLoadSource)source
{
    [self _tip_background_extractStorageInfo];

    if (!self.finalImageContainerRaw) {
        return;
    }

    TIPImageCacheEntry *entry = [self _tip_background_createCacheEntryFromRaw:YES permitPreviewFallback:NO didFallbackToPreview:NULL];
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
    [self _tip_background_propagateFinalRenderedImageFromSource:source];
}

- (void)_tip_background_propagateFinalRenderedImageFromSource:(TIPImageLoadSource)source
{
    if (_flags.finalImageWasTransformed && !_transfomerIdentifier) {
        return;
    }

    TIPImageCacheEntry *entry = [self _tip_background_createCacheEntryFromRaw:NO permitPreviewFallback:NO didFallbackToPreview:NULL];
    TIPAssert(!entry || (entry.completeImage && entry.completeImageContext));
    if (entry) {
        [_imagePipeline.renderedCache storeImageEntry:entry transformerIdentifier:(_flags.finalImageWasTransformed) ? _transfomerIdentifier : nil];
    }
}

#pragma mark Execute

- (void)_tip_background_executeDelegateWork:(TIPImageFetchDelegateWorkBlock)block
{
    id<TIPImageFetchDelegate> delegate = self.delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        block(delegate);
    });
}

- (void)_tip_executeBackgroundWork:(dispatch_block_t)block
{
    dispatch_async(_backgroundQueue, block);
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

- (instancetype)initWithFetchOperation:(TIPImageFetchOperation *)operation delegate:(id<TIPImageFetchDelegate>)delegate
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
        if ([fetchRequest respondsToSelector:@selector(imageIdentifier)]) {
            _imageDownloadIdentifier = [[fetchRequest imageIdentifier] copy];
        }
        if (!_imageDownloadIdentifier) {
            _imageDownloadIdentifier = [_imageDownloadURL absoluteString];
        }
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

+ (nullable instancetype)resultWithImageContainer:(nullable TIPImageContainer *)imageContainer identifier:(nullable NSString *)identifier source:(TIPImageLoadSource)source URL:(nullable NSURL *)URL originalDimensions:(CGSize)originalDimensions placeholder:(BOOL)placeholder transformed:(BOOL)transformed
{
    if (!imageContainer || !URL || !identifier) {
        return nil;
    }

    return [[self alloc] initWithImageContainer:imageContainer identifier:identifier source:source URL:URL originalDimensions:originalDimensions placeholder:placeholder transformed:transformed];
}

- (instancetype)initWithImageContainer:(TIPImageContainer *)imageContainer identifier:(NSString *)identifier source:(TIPImageLoadSource)source URL:(NSURL *)URL originalDimensions:(CGSize)originalDimensions placeholder:(BOOL)placeholder transformed:(BOOL)transformed
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
