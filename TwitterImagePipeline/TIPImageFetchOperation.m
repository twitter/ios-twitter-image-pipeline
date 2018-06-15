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

// Primary class gets the SELF_ARG convenience
#define SELF_ARG PRIVATE_SELF(TIPImageFetchOperation)

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
- (instancetype)initWithFetchOperation:(TIPImageFetchOperation *)operation
                              delegate:(id<TIPImageFetchDelegate>)delegate;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (void)invalidate;
@end

@interface TIPImageFetchOperationNetworkStepContext : NSObject
@property (nonatomic, nullable) TIPImageFetchDownloadRequest *imageDownloadRequest;
@property (nonatomic, nullable) id<TIPImageDownloadContext> imageDownloadContext;
@end

@interface TIPImageFetchResultInternal : NSObject <TIPImageFetchResult>
static TIPImageFetchResultInternal * __nullable
_CreateFetchResultInternal(TIPImageContainer * __nullable imageContainer,
                           NSString * __nullable identifier,
                           TIPImageLoadSource source,
                           NSURL * __nullable URL,
                           CGSize originalDimensions,
                           BOOL placeholder,
                           BOOL transformed);
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

// Private
static void _extractBasicRequestInfo(SELF_ARG);
static void _initializeDelegate(SELF_ARG,
                                id<TIPImageFetchDelegate> __nullable delegate);
static void _clearDelegateHandler(SELF_ARG);
static void _hydrateNewContext(SELF_ARG,
                               TIPImageCacheEntryContext *context,
                               NSURL *imageURL,
                               BOOL placeholder);

@end

@interface TIPImageFetchOperation (Background)

// Start/Abort
static void _background_start(SELF_ARG);
static BOOL _background_shouldAbort(SELF_ARG);

// Generate State
static void _background_extractObservers(SELF_ARG);
static void _background_extractAdvancedRequestInfo(SELF_ARG);
static void _background_extractTargetInfo(SELF_ARG);
static void _background_extractStorageInfo(SELF_ARG);
static void _background_validateProgressiveSupport(SELF_ARG,
                                                   TIPPartialImage *partialImage);
static void _background_clearNetworkContextVariables(SELF_ARG);
static void _background_setFinalStateAfterFlushingDelegate(SELF_ARG,
                                                           TIPImageFetchOperationState state);

// Load
static void _background_dispatchLoadStarted(SELF_ARG,
                                            TIPImageLoadSource source);
static void _background_loadFromNextSource(SELF_ARG);
static void _background_loadFromMemory(SELF_ARG);
static void _background_loadFromDisk(SELF_ARG);
static void _background_loadFromOtherPipelineDisk(SELF_ARG);
static void _background_loadFromAdditional(SELF_ARG);
static void _background_loadFromNextAdditionalCache(SELF_ARG,
                                                    NSURL *imageURL,
                                                    NSMutableArray<id<TIPImageAdditionalCache>> *caches);
static void _background_loadFromNetwork(SELF_ARG);

// Update
static void _background_updateFailureToLoadFinalImage(SELF_ARG,
                                                      NSError *error,
                                                      BOOL updateMetrics);
static void _background_updateProgress(SELF_ARG,
                                       float progress);
static void _background_updateFinalImage(SELF_ARG,
                                         TIPImageContainer *image,
                                         NSTimeInterval imageRenderLatency,
                                         NSURL *URL,
                                         TIPImageLoadSource source,
                                         NSString * __nullable networkImageType,
                                         NSUInteger networkByteCount,
                                         BOOL placeholder);
static void _background_updatePreviewImage(SELF_ARG,
                                           TIPImageCacheEntry *cacheEntry,
                                           TIPImageLoadSource source);
static void _background_updateProgressiveImage(SELF_ARG,
                                               UIImage *image,
                                               BOOL transformed,
                                               NSTimeInterval imageRenderLatency,
                                               NSURL *URL,
                                               float progress,
                                               TIPPartialImage *sourcePartialImage,
                                               TIPImageLoadSource source);
static void _background_updateFirstAnimatedImageFrame(SELF_ARG,
                                                      UIImage *image,
                                                      NSTimeInterval imageRenderLatency,
                                                      NSURL *URL,
                                                      float progress,
                                                      TIPPartialImage *sourcePartialImage,
                                                      TIPImageLoadSource source);
static void _background_handleCompletedMemoryEntry(SELF_ARG,
                                                   TIPImageMemoryCacheEntry *entry);
static void _background_handlePartialMemoryEntry(SELF_ARG,
                                                 TIPImageMemoryCacheEntry *entry);
static void _background_handleCompletedDiskEntry(SELF_ARG,
                                                 TIPImageDiskCacheEntry *entry);
static void _background_handlePartialDiskEntry(SELF_ARG,
                                               TIPImageDiskCacheEntry *entry,
                                               BOOL tryOtherPipelineDiskCachesIfNeeded);

// Render Progress
static void _background_processContinuedPartialEntry(SELF_ARG,
                                                     TIPPartialImage *partialImage,
                                                     NSURL *URL,
                                                     TIPImageLoadSource source);
static UIImage * __nullable _background_getNextProgressiveImage(SELF_ARG,
                                                                TIPImageDecoderAppendResult appendResult,
                                                                TIPPartialImage *partialImage,
                                                                NSUInteger renderCount);
static UIImage * __nullable _background_getFirstFrameOfAnimatedImageIfNotYetProvided(SELF_ARG,
                                                                                     TIPPartialImage *partialImage);
static UIImage *_background_transformAndScaleImage(SELF_ARG,
                                                   UIImage *image,
                                                   float progress,
                                                   BOOL *transformedOut);
static TIPImageContainer *_background_transformAndScaleImageContainer(SELF_ARG,
                                                                      TIPImageContainer *imageContainer,
                                                                      float progress,
                                                                      BOOL *transformedOut);

// Create Cache Entry
static TIPImageCacheEntry * __nullable _background_createCacheEntry(SELF_ARG,
                                                                    BOOL useRawImage,
                                                                    BOOL permitPreviewFallback,
                                                                    BOOL * __nullable didFallbackToPreviewOut);
static TIPImageCacheEntry * __nullable _background_createCacheEntryFromPartialImage(SELF_ARG,
                                                                                    TIPPartialImage *partialImage,
                                                                                    NSString *lastModified,
                                                                                    NSURL *imageURL);

// Cache propagation
static void _background_propagateFinalImage(SELF_ARG,
                                            TIPImageLoadSource source);
static void _background_propagateFinalRenderedImage(SELF_ARG,
                                                    TIPImageLoadSource source);
static void _background_propagatePartialImage(SELF_ARG,
                                              TIPPartialImage *partialImage,
                                              NSString *lastModified,
                                              BOOL wasResumed); // source is always the network
static void _background_propagatePreviewImage(SELF_ARG,
                                              TIPImageLoadSource source);

// Notifications
static void _background_postDidStart(SELF_ARG);
static void _background_postDidFinish(SELF_ARG);
static void _background_postDidStartDownload(SELF_ARG);
static void _background_postDidFinishDownloading(SELF_ARG,
                                                 NSString *imageType,
                                                 NSUInteger sizeInBytes);

// Execute
static void _background_executeDelegateWork(SELF_ARG,
                                            TIPImageFetchDelegateWorkBlock block);
static void _executeBackgroundWork(SELF_ARG,
                                   dispatch_block_t block);

@end

@interface TIPImageFetchOperation (DiskCache)

static void _diskCache_loadFromOtherPipelines(SELF_ARG,
                                              NSArray<TIPImagePipeline *> *pipelines,
                                              uint64_t startMachTime);
static BOOL _diskCache_attemptLoadFromOtherPipelineDisk(SELF_ARG,
                                                        TIPImagePipeline *nextPipeline,
                                                        uint64_t startMachTime);
static void _diskCache_completeLoadFromOtherPipelineDisk(SELF_ARG,
                                                         TIPImageContainer * __nullable imageContainer,
                                                         NSURL * __nullable URL,
                                                         NSTimeInterval latency,
                                                         BOOL placeholder);

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

- (instancetype)initWithImagePipeline:(TIPImagePipeline *)pipeline
                              request:(id<TIPImageFetchRequest>)request
                             delegate:(id<TIPImageFetchDelegate>)delegate
{
    if (self = [super init]) {
        _imagePipeline = pipeline;
        _request = request;
        _metricsInternal = [[TIPImageFetchMetrics alloc] initProject];

        _backgroundQueue = dispatch_queue_create("image.fetch.queue", DISPATCH_QUEUE_SERIAL);
        atomic_init(&_state, TIPImageFetchOperationStateIdle);
        _networkContext = [[TIPImageFetchOperationNetworkStepContext alloc] init];

        _initializeDelegate(self, delegate);
        _extractBasicRequestInfo(self);
    }
    return self;
}

static void _initializeDelegate(SELF_ARG,
                                id<TIPImageFetchDelegate> __nullable delegate)
{
    if (!self) {
        return;
    }

    self->_delegate = delegate;
    self->_flags.delegateSupportsAttemptWillStartCallbacks = ([delegate respondsToSelector:@selector(tip_imageFetchOperation:willAttemptToLoadFromSource:)] != NO);
    if (!delegate) {
        // nil delegate, just let the operation happen
    } else if ([delegate isKindOfClass:[TIPSimpleImageFetchDelegate class]]) {
        self->_strongDelegate = delegate;
    } else {
        // associate an object to perform the cancel on dealloc of the delegate
        TIPImageFetchDelegateDeallocHandler *handler;
        handler = [[TIPImageFetchDelegateDeallocHandler alloc] initWithFetchOperation:self
                                                                             delegate:delegate];
        if (handler) {
            self->_delegateHandler = handler;
            // Use the reference as the unique key since a delegate could have multiple operations
            objc_setAssociatedObject(delegate, (__bridge const void *)(handler), handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static void _clearDelegateHandler(SELF_ARG)
{
    if (!self) {
        return;
    }

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

static void _extractBasicRequestInfo(SELF_ARG)
{
    if (!self) {
        return;
    }

    self->_networkContext.imageDownloadRequest = [[TIPImageFetchDownloadRequest alloc] initWithRequest:self->_request];
    self->_loadingSources = [self->_request respondsToSelector:@selector(loadingSources)] ?
                                [self->_request loadingSources] :
                                TIPImageFetchLoadingSourcesAll;
    self->_decoderConfigMap = self->_networkContext.imageDownloadRequest.decoderConfigMap;
    self->_transformer = [self->_request respondsToSelector:@selector(transformer)] ? self->_request.transformer : nil;
    if ([self->_transformer respondsToSelector:@selector(tip_transformerIdentifier)]) {
        self->_transfomerIdentifier = [[self->_transformer tip_transformerIdentifier] copy];
        TIPAssert(self->_transfomerIdentifier.length > 0);
    }

    if (!self.imageURL || self.imageIdentifier.length == 0) {
        TIPLogError(@"Cannot fetch request, it is invalid.  URL = '%@', Identifier = '%@'", self.imageURL, self.imageIdentifier);
        self->_flags.invalidRequest = 1;
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
        _clearDelegateHandler(self);
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
    _clearDelegateHandler(self);
    self.delegate = nil;
    self.strongDelegate = nil;
}

- (void)cancel
{
    _executeBackgroundWork(self, ^{
        if (!self->_flags.cancelled) {
            self->_flags.cancelled = 1;
            [self->_imagePipeline.downloader removeDelegate:self forContext:self->_networkContext.imageDownloadContext];
        }
    });
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
    _executeBackgroundWork(self, ^{
        if (!self->_flags.didStart) {
            self->_flags.didStart = 1;
            _background_start(self);
        }
    });
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
    TIPLogDebug(@"%@%@, id=%@", NSStringFromSelector(_cmd), entry.completeImage, entry.identifier);

    _startTime = mach_absolute_time();
    self.state = TIPImageFetchOperationStateLoadingFromMemory;
    _executeBackgroundWork(self, ^{
        _background_extractObservers(self);
        _background_postDidStart(self);
    });
    id<TIPImageFetchDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_imageFetchOperationDidStart:)]) {
        [delegate tip_imageFetchOperationDidStart:self];
    }

    [_metricsInternal startWithSource:TIPImageLoadSourceMemoryCache];

    _networkContext = nil;
    self.finalImageContainerRaw = entry.completeImage;
    id<TIPImageFetchResult> finalResult = _CreateFetchResultInternal(entry.completeImage,
                                                                     entry.identifier,
                                                                     TIPImageLoadSourceMemoryCache,
                                                                     entry.completeImageContext.URL,
                                                                     sourceDims,
                                                                     entry.completeImageContext.treatAsPlaceholder,
                                                                     transformed);
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
    _executeBackgroundWork(self, ^{
        _background_postDidFinish(self);
    });
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
    _background_postDidStartDownload(self);
}

- (void)imageDownload:(id<TIPImageDownloadContext>)context didResetFromPartialImage:(TIPPartialImage *)oldPartialImage
{
    TIPAssert(!_flags.didReceiveFirstByte);
    _background_clearNetworkContextVariables(self);
    if ([self supportsLoadingFromSource:TIPImageLoadSourceNetwork]) {
        _background_updateProgress(self, 0.0f /*progress*/);
    } else {
        // Not configured to do a normal network load, fail
        NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                             code:TIPImageFetchErrorCouldNotLoadImage
                                         userInfo:nil];
        _background_updateFailureToLoadFinalImage(self, error, YES /*updateMetrics*/);
        [_imagePipeline.downloader removeDelegate:self forContext:context];
    }
}

- (void)imageDownload:(id<TIPImageDownloadContext>)context
       didAppendBytes:(NSUInteger)byteCount
       toPartialImage:(TIPPartialImage *)partialImage
               result:(TIPImageDecoderAppendResult)result
{
    if (_background_shouldAbort(self)) {
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
        UIImage *image = _background_getFirstFrameOfAnimatedImageIfNotYetProvided(self, partialImage);
        const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
        if (image) {
            // First frame progress
            _background_updateFirstAnimatedImageFrame(self,
                                                      image,
                                                      latency,
                                                      self.imageURL,
                                                      progress,
                                                      partialImage,
                                                      (_flags.wasResumedDownload) ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork);
        }
    } else if (partialImage.isProgressive) {
        UIImage *image = _background_getNextProgressiveImage(self,
                                                             result,
                                                             partialImage,
                                                             _progressiveRenderCount);
        if (image) {
            // Progressive image progress
            BOOL transformed = NO;
            image = _background_transformAndScaleImage(self,
                                                       image,
                                                       progress,
                                                       &transformed);
            const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
            _progressiveRenderCount++;
            _background_updateProgressiveImage(self,
                                               image,
                                               transformed,
                                               latency,
                                               self.imageURL,
                                               progress,
                                               partialImage,
                                               (_flags.wasResumedDownload) ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork);
        }
    }

    // Always update the plain ol' progress
    _background_updateProgress(self, progress);
}

- (void)imageDownload:(id<TIPImageDownloadContext>)context
        didCompleteWithPartialImage:(nullable TIPPartialImage *)partialImage
        lastModified:(nullable NSString *)lastModified
        byteSize:(NSUInteger)bytes
        imageType:(nullable NSString *)imageType
        image:(nullable TIPImageContainer *)image
        imageRenderLatency:(NSTimeInterval)latency
        statusCode:(NSInteger)statusCode
        error:(nullable NSError *)error
{
    const BOOL wasResuming = (_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming != nil);
    _background_clearNetworkContextVariables(self);
    _networkContext.imageDownloadContext = nil;

    id<TIPImageFetchDownload> download = (id<TIPImageFetchDownload>)context;
    [_metricsInternal addNetworkMetrics:[download respondsToSelector:@selector(downloadMetrics)] ? download.downloadMetrics : nil
                             forRequest:download.finalURLRequest
                              imageType:imageType
                       imageSizeInBytes:bytes
                        imageDimensions:(image) ? image.dimensions : partialImage.dimensions];

    if (partialImage && !image) {
        _background_propagatePartialImage(self,
                                          partialImage,
                                          lastModified,
                                          wasResuming);
    }

    if (_background_shouldAbort(self)) {
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
        _background_updateFinalImage(self,
                                     image,
                                     latency,
                                     self.imageURL,
                                     (_flags.wasResumedDownload) ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork,
                                     imageType,
                                     bytes,
                                     placeholder);
    } else {
        TIPAssert(error != nil);

        if (wasResuming && 416 /* Requested range not satisfiable */ == statusCode) {
            TIPAssert(!_flags.wasResumedDownload);
            if (!_flags.wasResumedDownload) {
                TIPLogWarning(@"Network resume yielded HTTP 416... retrying with full network load: %@", _networkContext.imageDownloadRequest.imageDownloadURL);
                _background_loadFromNetwork(self);
                return;
            }
        }

        _background_updateFailureToLoadFinalImage(self, error, YES /*updateMetrics*/);
    }
}

#pragma mark Helpers

static void _hydrateNewContext(SELF_ARG,
                               TIPImageCacheEntryContext *context,
                               NSURL *imageURL,
                               BOOL placeholder)
{
    if (!self) {
        return;
    }

    if (!imageURL) {
        imageURL = self.imageURL;
    }

    const TIPImageFetchOptions options = self->_networkContext.imageDownloadRequest.imageDownloadOptions;
    context.updateExpiryOnAccess = TIP_BITMASK_EXCLUDES_FLAGS(options, TIPImageFetchDoNotResetExpiryOnAccess);
    context.treatAsPlaceholder = placeholder;
    context.TTL = self->_networkContext.imageDownloadRequest.imageDownloadTTL;
    context.URL = imageURL;
    context.lastAccess = [NSDate date];
    if (context.TTL <= 0.0) {
        context.TTL = TIPTimeToLiveDefault;
    }
}

@end

@implementation TIPImageFetchOperation (Background)

#pragma mark Start / Abort

static void _background_start(SELF_ARG)
{
    if (!self) {
        return;
    }

    self->_startTime = mach_absolute_time();
    if (_background_shouldAbort(self)) {
        return;
    }

    self.state = TIPImageFetchOperationStateStarting;

    _background_extractObservers(self);

    _background_postDidStart(self);
    _background_executeDelegateWork(self, ^(id<TIPImageFetchDelegate> delegate){
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperationDidStart:)]) {
            [delegate tip_imageFetchOperationDidStart:self];
        }
    });

    _background_extractAdvancedRequestInfo(self);
    _background_loadFromNextSource(self);
}

static BOOL _background_shouldAbort(SELF_ARG)
{
    if (!self) {
        return NO;
    }

    if (self.isFinished || self->_flags.transitioningToFinishedState) {
        return YES;
    }

    if (self->_flags.cancelled) {
        NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                             code:TIPImageFetchErrorCodeCancelled
                                         userInfo:nil];
        _background_updateFailureToLoadFinalImage(self, error, YES/*updateMetrics*/);
        return YES;
    }

    if (self->_flags.invalidRequest) {
        NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                             code:TIPImageFetchErrorCodeInvalidRequest
                                         userInfo:nil];
        _background_updateFailureToLoadFinalImage(self, error, NO /*updateMetrics*/);
        return YES;
    }

    return NO;
}

#pragma mark Generate State

static void _background_extractObservers(SELF_ARG)
{
    if (!self) {
        return;
    }

    self->_observers = [TIPGlobalConfiguration sharedInstance].allImagePipelineObservers;
    id<TIPImagePipelineObserver> pipelineObserver = self.imagePipeline.observer;
    if (pipelineObserver) {
        if (!self->_observers) {
            self->_observers = @[pipelineObserver];
        } else {
            self->_observers = [self->_observers arrayByAddingObject:pipelineObserver];
        }
    }
}

static void _background_extractStorageInfo(SELF_ARG)
{
    if (!self) {
        return;
    }
    if (self->_flags.didExtractStorageInfo) {
        return;
    }

    NSTimeInterval TTL = [self->_request respondsToSelector:@selector(timeToLive)] ?
                                [self->_request timeToLive] :
                                -1.0;
    if (TTL <= 0.0) {
        TTL = TIPTimeToLiveDefault;
    }
    self->_networkContext.imageDownloadRequest.imageDownloadTTL = TTL;

    const TIPImageFetchOptions options = [self->_request respondsToSelector:@selector(options)] ?
                                                [self->_request options] :
                                                TIPImageFetchNoOptions;
    self->_networkContext.imageDownloadRequest.imageDownloadOptions = options;

    self->_flags.didExtractStorageInfo = 1;
}

static void _background_extractAdvancedRequestInfo(SELF_ARG)
{
    if (!self) {
        return;
    }

    self->_networkContext.imageDownloadRequest.imageDownloadHydrationBlock = [self->_request respondsToSelector:@selector(imageRequestHydrationBlock)] ? self->_request.imageRequestHydrationBlock : nil;
    self->_progressiveLoadingPolicies = nil;
    id<TIPImageFetchDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:)]) {
        // could support progressive, prep the policy
        self->_progressiveLoadingPolicies = [self->_request respondsToSelector:@selector(progressiveLoadingPolicies)] ?
                                            [[self->_request progressiveLoadingPolicies] copy] :
                                            nil;
    }
}

static void _background_extractTargetInfo(SELF_ARG)
{
    if (!self) {
        return;
    }

    if (self->_flags.didExtractTargetInfo) {
        return;
    }
    self->_targetDimensions = [self->_request respondsToSelector:@selector(targetDimensions)] ?
                                    [self->_request targetDimensions] :
                                    CGSizeZero;
    self->_targetContentMode = [self->_request respondsToSelector:@selector(targetContentMode)] ?
                                    [self->_request targetContentMode] :
                                    UIViewContentModeCenter;

    self->_flags.didExtractTargetInfo = 1;
}

static void _background_validateProgressiveSupport(SELF_ARG,
                                                   TIPPartialImage *partialImage)
{
    if (!self) {
        return;
    }

    if (!self->_flags.progressivePermissionValidated) {
        if (partialImage.state > TIPPartialImageStateLoadingHeaders) {
            id<TIPImageFetchDelegate> delegate = self.delegate;
            if (partialImage.progressive && [delegate respondsToSelector:@selector(tip_imageFetchOperation:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:)]) {
                TIPAssert(partialImage.type != nil);
                self->_progressiveLoadingPolicy = self->_progressiveLoadingPolicies[partialImage.type ?: @""];
                if (!self->_progressiveLoadingPolicy) {
                    self->_progressiveLoadingPolicy = [TIPImageFetchProgressiveLoadingPolicy defaultProgressiveLoadingPolicies][partialImage.type ?: @""];
                }
                if (self->_progressiveLoadingPolicy) {
                    const BOOL shouldLoad = [delegate tip_imageFetchOperation:self
                                        shouldLoadProgressivelyWithIdentifier:self.imageIdentifier
                                                                          URL:self.imageURL
                                                                    imageType:partialImage.type
                                                           originalDimensions:partialImage.dimensions];
                    if (shouldLoad) {
                        self->_flags.permitsProgressiveLoading = 1;
                    }
                }
            }

            self->_flags.progressivePermissionValidated = 1;
        }
    }
}

static void _background_clearNetworkContextVariables(SELF_ARG)
{
    if (!self) {
        return;
    }

    self->_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming = nil;
    self->_networkContext.imageDownloadRequest.imageDownloadLastModified = nil;
    self->_networkContext.imageDownloadRequest.imageDownloadTemporaryFileForResuming = nil;
    self->_progressiveRenderCount = 0;
}

static void _background_setFinalStateAfterFlushingDelegate(SELF_ARG,
                                                           TIPImageFetchOperationState state)
{
    if (!self) {
        return;
    }

    TIPAssert(TIPImageFetchOperationStateIsFinished(state));
    self->_flags.transitioningToFinishedState = 1;
    _background_executeDelegateWork(self, ^(id<TIPImageFetchDelegate> __unused delegate) {
        _executeBackgroundWork(self, ^{
            self.state = state;
            self->_flags.transitioningToFinishedState = 0;
        });
    });
}

#pragma mark Load

static void _background_dispatchLoadStarted(SELF_ARG,
                                            TIPImageLoadSource source)
{
    if (!self) {
        return;
    }

    if (self->_flags.delegateSupportsAttemptWillStartCallbacks) {
        _background_executeDelegateWork(self, ^(id<TIPImageFetchDelegate> delegate) {
            [delegate tip_imageFetchOperation:self
                  willAttemptToLoadFromSource:source];
        });
    }
}

static void _background_loadFromNextSource(SELF_ARG)
{
    if (!self) {
        return;
    }

    if (_background_shouldAbort(self)) {
        return;
    }

    TIPImageLoadSource nextSource = TIPImageLoadSourceUnknown;
    const TIPImageFetchOperationState currentState = atomic_load(&self->_state);

    // Get the next loading source
    if (self->_flags.shouldJumpToResumingDownload && currentState < TIPImageFetchOperationStateLoadingFromNetwork) {
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
        [self->_metricsInternal endSource];
    }
    if (TIPImageLoadSourceUnknown != nextSource) {
        [self->_metricsInternal startWithSource:nextSource];
    }

    // Load whatever's next (or set state to failed)
    switch (nextSource) {
        case TIPImageLoadSourceUnknown:
        {
            NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                                 code:TIPImageFetchErrorCouldNotLoadImage
                                             userInfo:nil];
            _background_updateFailureToLoadFinalImage(self, error, NO /*updateMetrics*/);
            break;
        }
        case TIPImageLoadSourceMemoryCache:
            _background_loadFromMemory(self);
            break;
        case TIPImageLoadSourceDiskCache:
            _background_loadFromDisk(self);
            break;
        case TIPImageLoadSourceAdditionalCache:
            _background_loadFromAdditional(self);
            break;
        case TIPImageLoadSourceNetwork:
        case TIPImageLoadSourceNetworkResumed:
            _background_loadFromNetwork(self);
            break;
    }
}

static void _background_loadFromMemory(SELF_ARG)
{
    if (!self) {
        return;
    }

    self.state = TIPImageFetchOperationStateLoadingFromMemory;
    if (![self supportsLoadingFromSource:TIPImageLoadSourceMemoryCache]) {
        _background_loadFromNextSource(self);
        return;
    }

    _background_dispatchLoadStarted(self, TIPImageLoadSourceMemoryCache);

    TIPImageMemoryCacheEntry *entry = [self->_imagePipeline.memoryCache imageEntryForIdentifier:self.imageIdentifier];
    _background_handleCompletedMemoryEntry(self, entry);
}

static void _background_loadFromDisk(SELF_ARG)
{
    if (!self) {
        return;
    }

    self.state = TIPImageFetchOperationStateLoadingFromDisk;
    if (![self supportsLoadingFromSource:TIPImageLoadSourceDiskCache]) {
        _background_loadFromNextSource(self);
        return;
    }

    _background_dispatchLoadStarted(self, TIPImageLoadSourceDiskCache);

    // Just load the meta-data (options == TIPImageDiskCacheFetchOptionsNone)
    TIPImageDiskCacheEntry *entry;
    entry = [self->_imagePipeline.diskCache imageEntryForIdentifier:self.imageIdentifier
                                                            options:TIPImageDiskCacheFetchOptionsNone
                                                   decoderConfigMap:self->_decoderConfigMap];
    _background_handleCompletedDiskEntry(self, entry);
}

static void _background_loadFromOtherPipelineDisk(SELF_ARG)
{
    if (!self) {
        return;
    }

    TIPAssert(self.state == TIPImageFetchOperationStateLoadingFromDisk);

    _background_extractStorageInfo(self); // need TTL and options
    NSMutableDictionary<NSString *, TIPImagePipeline *> *pipelines = [[TIPImagePipeline allRegisteredImagePipelines] mutableCopy];
    [pipelines removeObjectForKey:self->_imagePipeline.identifier];
    NSArray<TIPImagePipeline *> *otherPipelines = [pipelines allValues];
    tip_dispatch_async_autoreleasing([TIPGlobalConfiguration sharedInstance].queueForDiskCaches, ^{
        _diskCache_loadFromOtherPipelines(self, otherPipelines, mach_absolute_time() /*start time*/);
    });
}

static void _background_loadFromAdditional(SELF_ARG)
{
    if (!self) {
        return;
    }

    self.state = TIPImageFetchOperationStateLoadingFromAdditionalCache;
    if (![self supportsLoadingFromSource:TIPImageLoadSourceAdditionalCache]) {
        _background_loadFromNextSource(self);
        return;
    }

    _background_dispatchLoadStarted(self, TIPImageLoadSourceAdditionalCache);

    NSMutableArray<id<TIPImageAdditionalCache>> *additionalCaches = [self->_imagePipeline.additionalCaches mutableCopy];
    _background_loadFromNextAdditionalCache(self, self.imageURL, additionalCaches);
}

static void _background_loadFromNextAdditionalCache(SELF_ARG,
                                                    NSURL *imageURL,
                                                    NSMutableArray<id<TIPImageAdditionalCache>> *caches)
{
    if (!self) {
        return;
    }

    if (caches.count == 0) {
        _background_loadFromNextSource(self);
        return;
    }

    id<TIPImageAdditionalCache> nextCache = caches.firstObject;
    [caches removeObjectAtIndex:0];
    [nextCache tip_retrieveImageForURL:imageURL completion:^(UIImage *image) {
        _executeBackgroundWork(self, ^{
            if (_background_shouldAbort(self)) {
                return;
            }

            if (image) {
                const BOOL placeholder = TIP_BITMASK_HAS_SUBSET_FLAGS(self->_networkContext.imageDownloadRequest.imageDownloadOptions, TIPImageFetchTreatAsPlaceholder);
                _background_updateFinalImage(self,
                                             [[TIPImageContainer alloc] initWithImage:image],
                                             0 /*imageRenderLatency*/,
                                             imageURL,
                                             TIPImageLoadSourceAdditionalCache,
                                             nil /*networkImageType*/,
                                             0 /*networkByteCount*/,
                                             placeholder);
            } else {
                _background_loadFromNextAdditionalCache(self, imageURL, caches);
            }
        });
    }];
}

static void _background_loadFromNetwork(SELF_ARG)
{
    if (!self) {
        return;
    }

    self.state = TIPImageFetchOperationStateLoadingFromNetwork;

    if (!self->_imagePipeline.downloader) {
        NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                             code:TIPImageFetchErrorCouldNotDownloadImage
                                         userInfo:nil];
        _background_updateFailureToLoadFinalImage(self, error, YES /*updateMetrics*/);
        return;
    }

    if (![self supportsLoadingFromSource:TIPImageLoadSourceNetwork]) {
        if (![self supportsLoadingFromSource:TIPImageLoadSourceNetworkResumed] || !self->_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming) {
            // if full loads not OK and resuming not OK - fail
            NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                                 code:TIPImageFetchErrorCouldNotLoadImage
                                             userInfo:nil];
            _background_updateFailureToLoadFinalImage(self, error, YES /*updateMetrics*/);
            return;
        } // else if full loads not OK, but resuming is OK - continue
    }

    // Start loading
    _background_extractStorageInfo(self);
    const TIPImageLoadSource loadSource = (self->_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming != nil) ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork;
    _background_dispatchLoadStarted(self, loadSource);
    self->_networkContext.imageDownloadContext = [self->_imagePipeline.downloader fetchImageWithDownloadDelegate:self];
}

#pragma mark Update

static void _background_updateFailureToLoadFinalImage(SELF_ARG,
                                                      NSError *error,
                                                      BOOL updateMetrics)
{
    if (!self) {
        return;
    }

    TIPAssert(error != nil);
    TIPAssert(self->_metrics == nil);
    TIPAssert(self->_metricsInternal != nil);
    TIPLogDebug(@"Failed to Load Image: %@", @{ @"id" : self.imageIdentifier ?: @"<null>",
                                                @"URL" : self.imageURL ?: @"<null>",
                                                @"error" : error ?: @"<null>" });

    self.error = error;
    const BOOL didCancel = ([error.domain isEqualToString:TIPImageFetchErrorDomain] && error.code == TIPImageFetchErrorCodeCancelled);

    if (updateMetrics) {
        if (didCancel) {
            [self->_metricsInternal cancelSource];
        } else {
            [self->_metricsInternal endSource];
        }
    }
    self->_metrics = self->_metricsInternal;
    self->_metricsInternal = nil;
    self->_finishTime = mach_absolute_time();

    _background_executeDelegateWork(self, ^(id<TIPImageFetchDelegate> delegate) {
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didFailToLoadFinalImage:)]) {
            [delegate tip_imageFetchOperation:self didFailToLoadFinalImage:error];
        }
    });
    _background_postDidFinish(self);
    _background_setFinalStateAfterFlushingDelegate(self,
                                                   (didCancel) ? TIPImageFetchOperationStateCancelled : TIPImageFetchOperationStateFailed);
}

static void _background_updateFinalImage(SELF_ARG,
                                         TIPImageContainer *image,
                                         NSTimeInterval imageRenderLatency,
                                         NSURL *URL,
                                         TIPImageLoadSource source,
                                         NSString * __nullable networkImageType,
                                         NSUInteger networkByteCount,
                                         BOOL placeholder)
{
    if (!self) {
        return;
    }

    TIPAssert(image != nil);
    TIPAssert(self->_metrics == nil);
    TIPAssert(self->_metricsInternal != nil);
    _background_extractTargetInfo(self);
    self.finalImageContainerRaw = image;
    const uint64_t startMachTime = mach_absolute_time();
    BOOL transformed = NO;
    TIPImageContainer *finalImageContainer = _background_transformAndScaleImageContainer(self,
                                                                                         image,
                                                                                         1.f /*progress*/,
                                                                                         &transformed);
    self->_flags.finalImageWasTransformed = transformed;
    imageRenderLatency += TIPComputeDuration(startMachTime, mach_absolute_time());
    id<TIPImageFetchResult> finalResult = _CreateFetchResultInternal(finalImageContainer,
                                                                     self.imageIdentifier,
                                                                     source,
                                                                     URL,
                                                                     image.dimensions,
                                                                     placeholder,
                                                                     transformed);
    self.finalResult = finalResult;
    self.progress = 1.0f;

    [self->_metricsInternal finalWasHit:imageRenderLatency synchronously:NO];
    [self->_metricsInternal endSource];
    self->_metrics = self->_metricsInternal;
    self->_metricsInternal = nil;
    self->_finishTime = mach_absolute_time();

    TIPLogDebug(@"Loaded Final Image: %@", @{
                                             @"id" : self.imageIdentifier,
                                             @"URL" : self.imageURL,
                                             @"originalDimensions" : NSStringFromCGSize(self.finalImageContainerRaw.dimensions),
                                             @"finalDimensions" : NSStringFromCGSize(self.finalResult.imageContainer.dimensions),
                                             @"source" : @(source),
                                             @"store" : self->_imagePipeline.identifier,
                                             @"resumed" : @(self->_flags.wasResumedDownload),
                                             @"frames" : @(self.finalResult.imageContainer.frameCount),
                                             });

    const BOOL sourceWasNetwork = TIPImageLoadSourceNetwork == source || TIPImageLoadSourceNetworkResumed == source;
    if (sourceWasNetwork && networkByteCount > 0) {
        _background_postDidFinishDownloading(self, networkImageType, networkByteCount);
    }

    TIPAssert(finalResult != nil);
    if (!finalResult) {
        self.error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                         code:TIPImageFetchErrorCodeUnknown
                                     userInfo:nil];
        _background_executeDelegateWork(self, ^(id<TIPImageFetchDelegate> delegate) {
            if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didFailToLoadFinalImage:)]) {
                [delegate tip_imageFetchOperation:self didFailToLoadFinalImage:self.error];
            }
        });
        _background_postDidFinish(self);
        _background_setFinalStateAfterFlushingDelegate(self, TIPImageFetchOperationStateFailed);
        return;
    }

    _background_executeDelegateWork(self, ^(id<TIPImageFetchDelegate> delegate){
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFinalImage:)]) {
            [delegate tip_imageFetchOperation:self didLoadFinalImage:finalResult];
        }
    });

    _background_postDidFinish(self);
    _background_propagateFinalImage(self, source);
    _background_setFinalStateAfterFlushingDelegate(self, TIPImageFetchOperationStateSucceeded);
}

static void _background_postDidStart(SELF_ARG)
{
    if (!self) {
        return;
    }

    for (id<TIPImagePipelineObserver> observer in self->_observers) {
        if ([observer respondsToSelector:@selector(tip_imageFetchOperationDidStart:)]) {
            [observer tip_imageFetchOperationDidStart:self];
        }
    }
}

static void _background_postDidFinish(SELF_ARG)
{
    if (!self) {
        return;
    }

    for (id<TIPImagePipelineObserver> observer in self->_observers) {
        if ([observer respondsToSelector:@selector(tip_imageFetchOperationDidFinish:)]) {
            [observer tip_imageFetchOperationDidFinish:self];
        }
    }
}

static void _background_postDidStartDownload(SELF_ARG)
{
    if (!self) {
        return;
    }

    for (id<TIPImagePipelineObserver> observer in self->_observers) {
        if ([observer respondsToSelector:@selector(tip_imageFetchOperation:didStartDownloadingImageAtURL:)]) {
            [observer tip_imageFetchOperation:self didStartDownloadingImageAtURL:self.imageURL];
        }
    }
}

static void _background_postDidFinishDownloading(SELF_ARG,
                                                 NSString *imageType,
                                                 NSUInteger sizeInBytes)
{
    if (!self) {
        return;
    }

    for (id<TIPImagePipelineObserver> observer in self->_observers) {
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

static void _background_updatePreviewImage(SELF_ARG,
                                           TIPImageCacheEntry *cacheEntry,
                                           TIPImageLoadSource source)
{
    if (!self) {
        return;
    }

    TIPBoolBlock block = ^(BOOL canContinue) {
        if (_background_shouldAbort(self)) {
            return;
        } else if (!canContinue) {
            NSError *error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                                 code:TIPImageFetchErrorCodeCancelledAfterLoadingPreview
                                             userInfo:nil];
            _background_updateFailureToLoadFinalImage(self, error, YES /*updateMetrics*/);
            _background_propagatePreviewImage(self, source);
        } else {
            if (TIPImageLoadSourceMemoryCache == source) {
                _background_handlePartialMemoryEntry(self, (id)cacheEntry);
            } else if (TIPImageLoadSourceDiskCache == source) {
                _background_handlePartialDiskEntry(self, (id)cacheEntry, NO /*tryOtherPipelineDiskCachesIfNeeded*/);
            } else {
                _background_loadFromNextSource(self);
            }
        }
    };

    _background_extractTargetInfo(self);

    TIPImageContainer *image = cacheEntry.completeImage;
    TIPAssert(image != nil);

    self.previewImageContainerRaw = image;
    const uint64_t startMachTime = mach_absolute_time();
    BOOL transformed = NO;
    TIPImageContainer *previewImageContainer;
    previewImageContainer = _background_transformAndScaleImageContainer(self,
                                                                        image,
                                                                        -1.f /*progress; negative is preview*/,
                                                                        &transformed);
    self->_flags.previewImageWasTransformed = transformed;
    const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
    id<TIPImageFetchResult> previewResult = _CreateFetchResultInternal(previewImageContainer,
                                                                       self.imageIdentifier,
                                                                       source,
                                                                       cacheEntry.completeImageContext.URL,
                                                                       image.dimensions,
                                                                       cacheEntry.completeImageContext.treatAsPlaceholder,
                                                                       transformed);
    self.previewResult = previewResult;
    id<TIPImageFetchDelegate> delegate = self.delegate;

    [self->_metricsInternal previewWasHit:latency];

    TIPLogDebug(@"Loaded Preview Image: %@", @{
                                               @"id" : self.imageIdentifier,
                                               @"URL" : self.previewResult.imageURL,
                                               @"originalDimensions" : NSStringFromCGSize(self.previewImageContainerRaw.dimensions),
                                               @"finalDimensions" : NSStringFromCGSize(self.previewResult.imageContainer.dimensions),
                                               @"source" : @(source),
                                               @"store" : self->_imagePipeline.identifier,
                                               @"resumed" : @(self->_flags.wasResumedDownload),
                                               });

    TIPAssert(previewResult != nil);
    if (previewResult && [delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadPreviewImage:completion:)]) {
        _background_executeDelegateWork(self, ^(id<TIPImageFetchDelegate> blockDelegate) {
            if ([blockDelegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadPreviewImage:completion:)]) {
                [blockDelegate tip_imageFetchOperation:self didLoadPreviewImage:previewResult completion:^(TIPImageFetchPreviewLoadedBehavior behavior) {
                    _executeBackgroundWork(self, ^{
                        block(TIPImageFetchPreviewLoadedBehaviorContinueLoading == behavior);
                    });
                }];
            } else {
                _executeBackgroundWork(self, ^{
                    block(YES);
                });
            }
        });
    } else {
        block(YES);
    }
}

static void _background_updateFirstAnimatedImageFrame(SELF_ARG,
                                                      UIImage *image,
                                                      NSTimeInterval imageRenderLatency,
                                                      NSURL *URL,
                                                      float progress,
                                                      TIPPartialImage *sourcePartialImage,
                                                      TIPImageLoadSource source)
{
    if (!self) {
        return;
    }

    id<TIPImageFetchDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFirstAnimatedImageFrame:progress:)]) {
        return;
    }

    TIPAssert(!isnan(progress) && !isinf(progress));
    self.progress = progress;
    const uint64_t startMachTime = mach_absolute_time();
    UIImage *firstAnimatedImage = [image tip_scaledImageWithTargetDimensions:self->_targetDimensions
                                                                 contentMode:self->_targetContentMode];
    TIPImageContainer *firstAnimatedImageFrameContainer = (firstAnimatedImage) ? [[TIPImageContainer alloc] initWithImage:firstAnimatedImage] : nil;
    imageRenderLatency += TIPComputeDuration(startMachTime, mach_absolute_time());
    id<TIPImageFetchResult> progressiveResult = _CreateFetchResultInternal(firstAnimatedImageFrameContainer,
                                                                           self.imageIdentifier,
                                                                           source,
                                                                           URL,
                                                                           [image tip_dimensions],
                                                                           NO /*placeholder*/,
                                                                           NO /*transformed*/);
    self.progressiveResult = progressiveResult;

    [self->_metricsInternal progressiveFrameWasHit:imageRenderLatency];

    TIPLogDebug(@"Loaded First Animated Image Frame: %@", @{
                                                            @"id" : self.imageIdentifier,
                                                            @"URL" : self.imageURL,
                                                            @"originalDimensions" : NSStringFromCGSize(sourcePartialImage.dimensions),
                                                            @"finalDimensions" : NSStringFromCGSize([firstAnimatedImageFrameContainer dimensions]),
                                                            @"source" : @(self->_flags.wasResumedDownload ? TIPImageLoadSourceNetworkResumed : TIPImageLoadSourceNetwork),
                                                            @"store" : self->_imagePipeline.identifier,
                                                            @"resumed" : @(self->_flags.wasResumedDownload),
                                                            });

    TIPAssert(progressiveResult != nil);
    if (progressiveResult) {
        _background_executeDelegateWork(self, ^(id<TIPImageFetchDelegate> blockDelegate) {
            if ([blockDelegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFirstAnimatedImageFrame:progress:)]) {
                [blockDelegate tip_imageFetchOperation:self
                        didLoadFirstAnimatedImageFrame:progressiveResult
                                              progress:progress];
            }
        });
    }
}

static void _background_updateProgressiveImage(SELF_ARG,
                                               UIImage *image,
                                               BOOL transformed,
                                               NSTimeInterval imageRenderLatency,
                                               NSURL *URL,
                                               float progress,
                                               TIPPartialImage *sourcePartialImage,
                                               TIPImageLoadSource source)
{
    if (!self) {
        return;
    }

    id<TIPImageFetchDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(tip_imageFetchOperation:didUpdateProgressiveImage:progress:)]) {
        return;
    }

    TIPAssert(!isnan(progress) && !isinf(progress));
    self.progress = progress;

    TIPAssert(image != nil);
    self->_flags.progressiveImageWasTransformed = transformed;
    TIPImageContainer *progressContainer = (image) ? [[TIPImageContainer alloc] initWithImage:image] : nil;
    id<TIPImageFetchResult> progressiveResult = _CreateFetchResultInternal(progressContainer,
                                                                           self.imageIdentifier,
                                                                           source,
                                                                           URL,
                                                                           [image tip_dimensions],
                                                                           NO /*placeholder*/,
                                                                           transformed);
    self.progressiveResult = progressiveResult;

    [self->_metricsInternal progressiveFrameWasHit:imageRenderLatency];

    TIPLogDebug(@"Loaded Progressive Image: %@", @{
                                                   @"progress" : @(progress),
                                                   @"id" : self.imageIdentifier,
                                                   @"URL" : URL,
                                                   @"originalDimensions" : NSStringFromCGSize(sourcePartialImage.dimensions),
                                                   @"finalDimensions" : NSStringFromCGSize([self.progressiveResult.imageContainer dimensions]),
                                                   @"source" : @(source),
                                                   @"store" : self->_imagePipeline.identifier,
                                                   @"resumed" : @(self->_flags.wasResumedDownload),
                                                   });

    TIPAssert(progressiveResult != nil);
    if (progressiveResult) {
        _background_executeDelegateWork(self, ^(id<TIPImageFetchDelegate> blockDelegate) {
            if ([blockDelegate respondsToSelector:@selector(tip_imageFetchOperation:didUpdateProgressiveImage:progress:)]) {
                [blockDelegate tip_imageFetchOperation:self
                             didUpdateProgressiveImage:progressiveResult
                                              progress:progress];
            }
        });
    }
}

static void _background_updateProgress(SELF_ARG,
                                       float progress)
{
    if (!self) {
        return;
    }

    TIPAssert(!isnan(progress) && !isinf(progress));
    self.progress = progress;

    _background_executeDelegateWork(self, ^(id<TIPImageFetchDelegate> delegate) {
        if ([delegate respondsToSelector:@selector(tip_imageFetchOperation:didUpdateProgress:)]) {
            [delegate tip_imageFetchOperation:self didUpdateProgress:progress];
        }
    });
}

static void _background_handleCompletedMemoryEntry(SELF_ARG,
                                                   TIPImageMemoryCacheEntry *entry)
{
    if (!self) {
        return;
    }

    if (_background_shouldAbort(self)) {
        return;
    }

    TIPImageContainer *image = entry.completeImage;
    if (image) {
        NSURL *completeImageURL = entry.completeImageContext.URL;
        const BOOL isFinalImage = [completeImageURL isEqual:self.imageURL];

        if (isFinalImage) {
            _background_updateFinalImage(self,
                                         image,
                                         0 /*imageRenderLatency*/,
                                         completeImageURL,
                                         TIPImageLoadSourceMemoryCache,
                                         nil /*networkImageType*/,
                                         0 /*networkByteCount*/,
                                         entry.completeImageContext.treatAsPlaceholder);
            return;
        }

        if (!self.previewResult) {
            _background_updatePreviewImage(self, entry, TIPImageLoadSourceMemoryCache);
            return;
        }
    }

    // continue
    _background_handlePartialMemoryEntry(self, entry);
}

static void _background_handlePartialMemoryEntry(SELF_ARG,
                                                 TIPImageMemoryCacheEntry *entry)
{
    if (!self) {
        return;
    }

    if (_background_shouldAbort(self)) {
        return;
    }

    TIPPartialImage * const partialImage = entry.partialImage;
    if (partialImage && [self supportsLoadingFromSource:TIPImageLoadSourceNetworkResumed]) {
        const BOOL isFinalImage = [self.imageURL isEqual:entry.partialImageContext.URL];
        if (isFinalImage) {
            TIPPartialImageEntryContext * const partialImageContext = entry.partialImageContext;
            NSString * const entryIdentifier = entry.identifier;
            self->_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming = partialImage;
            self->_networkContext.imageDownloadRequest.imageDownloadLastModified = partialImageContext.lastModified;

            TIPImageDiskCache * const diskCache = self->_imagePipeline.diskCache;
            if (diskCache) {
                TIPImageDiskCacheEntry *diskEntry;
                diskEntry = [diskCache imageEntryForIdentifier:entryIdentifier
                                                       options:TIPImageDiskCacheFetchOptionTemporaryFile
                                              decoderConfigMap:self->_decoderConfigMap];
                TIPImageDiskCacheTemporaryFile *diskTempFile = diskEntry.tempFile;
                if (!diskTempFile) {
                    diskTempFile = [self->_imagePipeline.diskCache openTemporaryFileForImageIdentifier:entry.identifier];
                    [diskTempFile appendData:partialImage.data];
                }
                self->_networkContext.imageDownloadRequest.imageDownloadTemporaryFileForResuming = diskTempFile;
            }

            _background_processContinuedPartialEntry(self,
                                                     partialImage,
                                                     partialImageContext.URL,
                                                     TIPImageLoadSourceMemoryCache);

            self->_flags.shouldJumpToResumingDownload = 1;
        }
    }

    // continue
    _background_loadFromNextSource(self);
}

static void _background_handleCompletedDiskEntry(SELF_ARG,
                                                 TIPImageDiskCacheEntry *entry)
{
    if (!self) {
        return;
    }

    if (_background_shouldAbort(self)) {
        return;
    }

    if (entry.completeImageContext) {
        NSURL *completeImageURL = entry.completeImageContext.URL;
        const CGSize dimensions = entry.completeImageContext.dimensions;
        const CGSize currentDimensions = self.previewResult.imageContainer.dimensions;
        const BOOL isFinal = [completeImageURL isEqual:self.imageURL];
        if (isFinal || (dimensions.width * dimensions.height > currentDimensions.width * currentDimensions.height)) {
            // Metadata checks out, load the actual complete image
            entry = [self->_imagePipeline.diskCache imageEntryForIdentifier:entry.identifier
                                                                    options:TIPImageDiskCacheFetchOptionCompleteImage
                                                           decoderConfigMap:self->_decoderConfigMap];
            if ([completeImageURL isEqual:entry.completeImageContext.URL]) {
                TIPImageContainer *image = entry.completeImage;
                if (image) {
                    if (isFinal) {
                        _background_updateFinalImage(self,
                                                     image,
                                                     0 /*imageRenderLatency*/,
                                                     completeImageURL,
                                                     TIPImageLoadSourceDiskCache,
                                                     nil /*networkImageType*/,
                                                     0 /*networkByteCount*/,
                                                     entry.completeImageContext.treatAsPlaceholder);
                        return;
                    }

                    if (!self.previewResult) {
                        _background_updatePreviewImage(self, entry, TIPImageLoadSourceDiskCache);
                        return;
                    }
                }
            }
        }
    }

    _background_handlePartialDiskEntry(self, entry, YES /*tryOtherPipelineDiskCachesIfNeeded*/);
}

static void _background_handlePartialDiskEntry(SELF_ARG,
                                               TIPImageDiskCacheEntry *entry,
                                               BOOL tryOtherPipelineDiskCachesIfNeeded)
{
    if (!self) {
        return;
    }

    if (_background_shouldAbort(self)) {
        return;
    }

    if (entry.partialImageContext && [self supportsLoadingFromSource:TIPImageLoadSourceNetworkResumed]) {
        const CGSize dimensions = entry.completeImageContext.dimensions;
        const BOOL isFinal = [self.imageURL isEqual:entry.partialImageContext.URL];
        BOOL isReasonableDataRemainingAndLarger = NO;
        _background_extractTargetInfo(self);
        const BOOL couldBeReasonableDataRemainingAndLarger =
                        !isFinal &&
                        TIPSizeGreaterThanZero(self->_targetDimensions) &&
                        ((dimensions.width * dimensions.height) > (self->_targetDimensions.width * self->_targetDimensions.height));
        if (couldBeReasonableDataRemainingAndLarger) {
            const double ratio = (dimensions.width * dimensions.height) / (self->_targetDimensions.width * self->_targetDimensions.height);
            const NSUInteger remainingBytes = (entry.partialImageContext.expectedContentLength > entry.partialFileSize) ? entry.partialImageContext.expectedContentLength - entry.partialFileSize : NSUIntegerMax;
            NSUInteger hypotheticalBytes = (entry.partialImageContext.expectedContentLength) ?: 0;
            hypotheticalBytes = (NSUInteger)((double)hypotheticalBytes / ratio);
            isReasonableDataRemainingAndLarger = remainingBytes < hypotheticalBytes;
        }
        if (isFinal || isReasonableDataRemainingAndLarger) {
            // meta-data checks out, load the actual partial image
            entry = [self->_imagePipeline.diskCache imageEntryForIdentifier:entry.identifier
                                                                    options:(TIPImageDiskCacheFetchOptionPartialImage | TIPImageDiskCacheFetchOptionTemporaryFile)
                                                           decoderConfigMap:self->_decoderConfigMap];
            if ([self.imageURL isEqual:entry.partialImageContext.URL] && entry.partialImage && entry.tempFile) {
                self->_networkContext.imageDownloadRequest.imageDownloadLastModified = entry.partialImageContext.lastModified;
                self->_networkContext.imageDownloadRequest.imageDownloadPartialImageForResuming = entry.partialImage;
                self->_networkContext.imageDownloadRequest.imageDownloadTemporaryFileForResuming = entry.tempFile;

                _background_processContinuedPartialEntry(self,
                                                         entry.partialImage,
                                                         entry.partialImageContext.URL,
                                                         TIPImageLoadSourceDiskCache);

                self->_flags.shouldJumpToResumingDownload = 1;
            }
        }
    }

    if (tryOtherPipelineDiskCachesIfNeeded) {
        _background_loadFromOtherPipelineDisk(self);
    } else {
        _background_loadFromNextSource(self);
    }
}

#pragma mark Render Progress

static TIPImageContainer *_background_transformAndScaleImageContainer(SELF_ARG,
                                                                      TIPImageContainer *imageContainer,
                                                                      float progress,
                                                                      BOOL *transformedOut)
{
    TIPAssert(self);
    if (!self) {
        return nil;
    }

    TIPImageContainer *outputImage;
    if (imageContainer.isAnimated) {
        outputImage = [imageContainer scaleToTargetDimensions:self->_targetDimensions
                                                  contentMode:self->_targetContentMode] ?: imageContainer;
        *transformedOut = NO;
    } else {
        UIImage *scaledImage = _background_transformAndScaleImage(self,
                                                                  imageContainer.image,
                                                                  progress,
                                                                  transformedOut);
        outputImage = [[TIPImageContainer alloc] initWithImage:scaledImage];
    }
    return outputImage;
}

static UIImage *_background_transformAndScaleImage(SELF_ARG,
                                                   UIImage *image,
                                                   float progress,
                                                   BOOL *transformedOut)
{
    TIPAssert(self);
    if (!self) {
        return nil;
    }

    *transformedOut = NO;
    _background_extractTargetInfo(self);
    if (self->_transformer) {
        UIImage *transformedImage = [self->_transformer tip_transformImage:image
                                                              withProgress:progress
                                                      hintTargetDimensions:self->_targetDimensions
                                                     hintTargetContentMode:self->_targetContentMode
                                                    forImageFetchOperation:self];
        if (transformedImage) {
            image = transformedImage;
            *transformedOut = YES;
        }
    }
    image = [image tip_scaledImageWithTargetDimensions:self->_targetDimensions
                                           contentMode:self->_targetContentMode];
    TIPAssert(image != nil);
    return image;
}

static void _background_processContinuedPartialEntry(SELF_ARG,
                                                     TIPPartialImage *partialImage,
                                                     NSURL *URL,
                                                     TIPImageLoadSource source)
{
    if (!self) {
        return;
    }

    _background_validateProgressiveSupport(self, partialImage);

    // If we have a partial image with enough progress to display, let's decode it and use it as a progress image
    if (self->_flags.permitsProgressiveLoading && partialImage.frameCount > 0 && [self.delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadPreviewImage:completion:)]) {
        const uint64_t startMachTime = mach_absolute_time();
        const TIPImageDecoderAppendResult givenResult = TIPImageDecoderAppendResultDidLoadFrame;
        UIImage *progressImage = _background_getNextProgressiveImage(self, givenResult, partialImage, 0 /*renderCount*/);
        if (progressImage) {
            const float progress = partialImage.progress;
            BOOL transformed = NO;
            progressImage = _background_transformAndScaleImage(self,
                                                               progressImage,
                                                               progress,
                                                               &transformed);
            const NSTimeInterval latency = TIPComputeDuration(startMachTime, mach_absolute_time());
            _background_updateProgressiveImage(self, progressImage, transformed, latency, URL, progress, partialImage, source);
        }
    }
}

static UIImage * __nullable _background_getNextProgressiveImage(SELF_ARG,
                                                                TIPImageDecoderAppendResult appendResult,
                                                                TIPPartialImage *partialImage,
                                                                NSUInteger renderCount)
{
    if (!self) {
        return nil;
    }

    _background_validateProgressiveSupport(self, partialImage);

    BOOL shouldRender = NO;
    TIPImageDecoderRenderMode mode = TIPImageDecoderRenderModeCompleteImage;
    if (partialImage.state > TIPPartialImageStateLoadingHeaders) {
        shouldRender = YES;
        if (self->_flags.permitsProgressiveLoading) {

            TIPImageFetchProgress fetchProgress = TIPImageFetchProgressNone;
            if (TIPImageDecoderAppendResultDidLoadFrame == appendResult) {
                fetchProgress = TIPImageFetchProgressFullFrame;
            } else if (partialImage.state > TIPPartialImageStateLoadingHeaders) {
                fetchProgress = TIPImageFetchProgressPartialFrame;
            }
            TIPImageFetchProgressUpdateBehavior behavior = TIPImageFetchProgressUpdateBehaviorNone;
            if (self->_progressiveLoadingPolicy) {
                behavior = [self->_progressiveLoadingPolicy tip_imageFetchOperation:self
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

    TIPImageContainer *image = (shouldRender) ? [partialImage renderImageWithMode:mode decoded:YES] : nil;
    return image.image;
}

static UIImage * __nullable _background_getFirstFrameOfAnimatedImageIfNotYetProvided(SELF_ARG,
                                                                                     TIPPartialImage *partialImage)
{
    if (!self) {
        return nil;
    }

    if (partialImage.isAnimated && partialImage.frameCount >= 1 && !self->_flags.didReceiveFirstAnimatedFrame) {
        if ([self.delegate respondsToSelector:@selector(tip_imageFetchOperation:didLoadFirstAnimatedImageFrame:progress:)]) {
            TIPImageContainer *imageContainer = [partialImage renderImageWithMode:TIPImageDecoderRenderModeFullFrameProgress decoded:NO];
            if (imageContainer && !imageContainer.isAnimated) {
                // Provide the first frame if requested
                self->_flags.didReceiveFirstAnimatedFrame = 1;
                return imageContainer.image;
            }
        }
    }

    return nil;
}

#pragma mark Create Cache Entry

static TIPImageCacheEntry * __nullable _background_createCacheEntry(SELF_ARG,
                                                                    BOOL useRawImage,
                                                                    BOOL permitPreviewFallback,
                                                                    BOOL * __nullable didFallbackToPreviewOut)
{
    if (!self) {
        return nil;
    }

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
        _hydrateNewContext(self, context, imageURL, isPlaceholder);

        entry.identifier = self.imageIdentifier;
    }

    return entry;
}

static TIPImageCacheEntry * __nullable _background_createCacheEntryFromPartialImage(SELF_ARG,
                                                                                    TIPPartialImage *partialImage,
                                                                                    NSString *lastModified,
                                                                                    NSURL *imageURL)
{
    if (!self) {
        return nil;
    }

    if (!partialImage) {
        return nil;
    }

    if (!lastModified) {
        return nil;
    }

    if (partialImage.state <= TIPPartialImageStateLoadingHeaders) {
        return nil;
    }

    if (TIP_BITMASK_HAS_SUBSET_FLAGS(self->_networkContext.imageDownloadRequest.imageDownloadOptions, TIPImageFetchTreatAsPlaceholder)) {
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
    _hydrateNewContext(self, context, imageURL, NO /*placeholder*/);

    entry.identifier = self.imageIdentifier;

    return entry;
}

#pragma mark Cache propagation

static void _background_propagatePartialImage(SELF_ARG,
                                              TIPPartialImage *partialImage,
                                              NSString *lastModified,
                                              BOOL wasResumed)
{
    if (!self) {
        return;
    }

    _background_extractStorageInfo(self);

    if (!self->_flags.didReceiveFirstByte || self.finalImageContainerRaw) {
        return;
    }

    TIPImageCacheEntry *entry = _background_createCacheEntryFromPartialImage(self,
                                                                             partialImage,
                                                                             lastModified,
                                                                             self.progressiveResult.imageURL);
    TIPAssert(!entry || (entry.partialImage && entry.partialImageContext));
    if (entry) {
        [self->_imagePipeline.memoryCache updateImageEntry:entry
                                   forciblyReplaceExisting:NO];
    }
}

static void _background_propagatePreviewImage(SELF_ARG,
                                              TIPImageLoadSource source)
{
    if (!self) {
        return;
    }

    if (TIPImageLoadSourceMemoryCache != source && TIPImageLoadSourceDiskCache != source) {
        // only memory/disk sources supported
        return;
    }

    _background_extractStorageInfo(self);

    if (!self.previewImageContainerRaw || self.finalImageContainerRaw) {
        return;
    }

    TIPImageCacheEntry *entry = nil;

    // First, the memory cache (if coming from disk)
    if (TIPImageLoadSourceDiskCache == source) {
        entry = _background_createCacheEntry(self,
                                             YES /*useRawImage*/,
                                             YES /*permitPreviewFallback*/,
                                             NULL /*didFallbackToPreviewOut; we don't care*/);
        TIPAssert(!entry || (entry.completeImage && entry.completeImageContext));
        if (entry) {
            [self->_imagePipeline.memoryCache updateImageEntry:entry
                                       forciblyReplaceExisting:NO];
        }
    }

    // Second, the rendered cache (always)
    BOOL didFallbackToPreview = NO;
    entry = _background_createCacheEntry(self,
                                         NO /*useRawImage*/,
                                         YES /*permitPreviewFallback*/,
                                         &didFallbackToPreview);
    TIPAssert(!entry || (entry.completeImage && entry.completeImageContext));
    if (entry) {
        const CGSize rawSize = (didFallbackToPreview) ?
                                    self.previewImageContainerRaw.dimensions :
                                    self.finalImageContainerRaw.dimensions;
        const BOOL wasTransformed = (didFallbackToPreview) ?
                                        self->_flags.previewImageWasTransformed :
                                        self->_flags.finalImageWasTransformed;
        if (!wasTransformed || self->_transfomerIdentifier) {
            [self->_imagePipeline.renderedCache storeImageEntry:entry
                                          transformerIdentifier:(wasTransformed) ? self->_transfomerIdentifier : nil
                                          sourceImageDimensions:rawSize];
        }
    }
}

static void _background_propagateFinalImage(SELF_ARG,
                                            TIPImageLoadSource source)
{
    if (!self) {
        return;
    }

    _background_extractStorageInfo(self);

    if (!self.finalImageContainerRaw) {
        return;
    }

    TIPImageCacheEntry *entry = _background_createCacheEntry(self,
                                                             YES /*useRawImage*/,
                                                             NO /*permitPreviewFallback*/,
                                                             NULL /*didFallbackToPreviewOut*/);
    TIPAssert(!entry || (entry.completeImage && entry.completeImageContext));

    if (entry) {
        switch (source) {
            case TIPImageLoadSourceMemoryCache:
            {
                [self->_imagePipeline.diskCache updateImageEntry:entry forciblyReplaceExisting:NO];
                break;
            }
            case TIPImageLoadSourceDiskCache:
            case TIPImageLoadSourceNetwork:
            case TIPImageLoadSourceNetworkResumed:
            case TIPImageLoadSourceAdditionalCache:
            {
                [self->_imagePipeline.memoryCache updateImageEntry:entry forciblyReplaceExisting:NO];
                if (TIPImageLoadSourceNetwork == source || TIPImageLoadSourceNetworkResumed == source) {
                    [self->_imagePipeline postCompletedEntry:entry manual:NO];
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
    _background_propagateFinalRenderedImage(self, source);
}

static void _background_propagateFinalRenderedImage(SELF_ARG,
                                                    TIPImageLoadSource source)
{
    if (!self) {
        return;
    }

    if (self->_flags.finalImageWasTransformed && !self->_transfomerIdentifier) {
        return;
    }

    TIPImageCacheEntry *entry = _background_createCacheEntry(self,
                                                             NO /*useRawImage*/,
                                                             NO /*permitPreviewFallback*/,
                                                             NULL /*didFallbackToPreviewOut*/);
    TIPAssert(!entry || (entry.completeImage && entry.completeImageContext));
    if (entry) {
        const CGSize rawSize = self.finalImageContainerRaw.dimensions;
        NSString *transformerIdentifier = (self->_flags.finalImageWasTransformed) ? self->_transfomerIdentifier : nil;
        [self->_imagePipeline.renderedCache storeImageEntry:entry
                                      transformerIdentifier:transformerIdentifier
                                      sourceImageDimensions:rawSize];
    }
}

#pragma mark Execute

static void _background_executeDelegateWork(SELF_ARG,
                                            TIPImageFetchDelegateWorkBlock block)
{
    if (!self) {
        return;
    }

    id<TIPImageFetchDelegate> delegate = self.delegate;
    tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        block(delegate);
    });
}

static void _executeBackgroundWork(SELF_ARG,
                                   dispatch_block_t block)
{
    if (!self) {
        return;
    }

    tip_dispatch_async_autoreleasing(self->_backgroundQueue, block);
}

@end

@implementation TIPImageFetchOperation (DiskCache)

static void _diskCache_loadFromOtherPipelines(SELF_ARG,
                                              NSArray<TIPImagePipeline *> *pipelines,
                                              uint64_t startMachTime)
{
    if (!self) {
        return;
    }

    for (TIPImagePipeline *nextPipeline in pipelines) {
        // look in the pipeline's disk cache
        if (_diskCache_attemptLoadFromOtherPipelineDisk(self, nextPipeline, startMachTime)) {
            // success!
            return;
        }
    }

    // Ran out of "next" pipelines, load from next source
    _diskCache_completeLoadFromOtherPipelineDisk(self,
                                                 nil /*imageContainer*/,
                                                 nil /*URL*/,
                                                 TIPComputeDuration(startMachTime, mach_absolute_time()),
                                                 NO /*placeholder*/);
}

static BOOL _diskCache_attemptLoadFromOtherPipelineDisk(SELF_ARG,
                                                        TIPImagePipeline *nextPipeline,
                                                        uint64_t startMachTime)
{
    if (!self) {
        return NO;
    }

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
            TIPImageDiskCache *thisDiskCache = self->_imagePipeline.diskCache;

            // override fetch values
            const TIPImageFetchOptions options = self->_networkContext.imageDownloadRequest.imageDownloadOptions;
            context.updateExpiryOnAccess = TIP_BITMASK_EXCLUDES_FLAGS(options, TIPImageFetchDoNotResetExpiryOnAccess);
            context.TTL = self->_networkContext.imageDownloadRequest.imageDownloadTTL;
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
                                                    decoderConfigMap:self->_decoderConfigMap];

            // did we get an image?
            TIPImageContainer *image = entry.completeImage;
            if (image) {

                // complete
                _diskCache_completeLoadFromOtherPipelineDisk(self,
                                                             image,
                                                             context.URL,
                                                             TIPComputeDuration(startMachTime, mach_absolute_time()),
                                                             context.treatAsPlaceholder);

                // success!
                return YES;
            }
        }
    }

    // didn't succeed
    return NO;
}

static void _diskCache_completeLoadFromOtherPipelineDisk(SELF_ARG,
                                                         TIPImageContainer * __nullable imageContainer,
                                                         NSURL * __nullable URL,
                                                         NSTimeInterval latency,
                                                         BOOL placeholder)
{
    if (!self) {
        return;
    }

    if (latency > 0.150) {
        TIPLogWarning(@"Other Pipeline Duration (%@): %.3fs", (imageContainer != nil) ? @"HIT" : @"MISS", latency);
    } else if (imageContainer) {
        TIPLogDebug(@"Other Pipeline Duration (HIT): %.3fs", latency);
    }

    _executeBackgroundWork(self, ^{
        if (imageContainer && URL) {
            _background_updateFinalImage(self,
                                         imageContainer,
                                         0 /*imageRenderLatency*/,
                                         URL,
                                         TIPImageLoadSourceDiskCache,
                                         nil /*networkImageType*/,
                                         0 /*networkByteCount*/,
                                         placeholder);
        } else {
            _background_loadFromNextSource(self);
        }
    });
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

static TIPImageFetchResultInternal * __nullable
_CreateFetchResultInternal(TIPImageContainer * __nullable imageContainer,
                           NSString * __nullable identifier,
                           TIPImageLoadSource source,
                           NSURL * __nullable URL,
                           CGSize originalDimensions,
                           BOOL placeholder,
                           BOOL transformed)
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
                           transformed:(BOOL)transformed
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
