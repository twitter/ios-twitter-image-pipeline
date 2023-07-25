//
//  TIPImageDownloader.m
//  TwitterImagePipeline
//
//  Created on 3/3/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import "NSDictionary+TIPAdditions.h"
#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageDownloader.h"
#import "TIPImageDownloadInternalContext.h"
#import "TIPImageFetchDownload.h"
#import "TIPTiming.h"

NS_ASSUME_NONNULL_BEGIN

#ifndef TIP_LOG_DOWNLOAD_PROGRESS
#define TIP_LOG_DOWNLOAD_PROGRESS 0
#endif

NSString * const TIPImageDownloaderCancelSource = @"Image Fetch Cancelled";

static const char *kTIPImageDownloaderQueueName = "com.twitter.tip.downloader.queue";

#define TIPAssertDownloaderQueue() \
do { \
    if (!gTwitterImagePipelineAssertEnabled) { \
        break; \
    } \
    const char *__currentLabel = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL); \
    if (!__currentLabel || 0 != strcmp(__currentLabel, kTIPImageDownloaderQueueName)) { \
        NSString *__assert_fn__ = @(__PRETTY_FUNCTION__); \
        __assert_fn__ = __assert_fn__ ? __assert_fn__ : @"<Unknown Function>"; \
        NSString *__assert_file__ = @(__FILE__); \
        __assert_file__ = __assert_file__ ? __assert_file__ : @"<Unknown File>"; \
        [[NSAssertionHandler currentHandler] handleFailureInFunction:__assert_fn__ \
                                                                file:__assert_file__ \
                                                          lineNumber:__LINE__ \
                                                         description:@"%s did not match expected GCD queue name: %s", __currentLabel ?: "<null>", kTIPImageDownloaderQueueName]; \
    } \
} while (0)

static long long _ExpectedResponseBodySize(NSHTTPURLResponse * __nullable URLResponse);
static long long _ExpectedResponseBodySize(NSHTTPURLResponse * __nullable URLResponse)
{
    long long contentLength = 0;
    if (URLResponse) {
        contentLength = URLResponse.expectedContentLength;
        if (contentLength <= 0) {
            contentLength = [[URLResponse.allHeaderFields tip_objectForCaseInsensitiveKey:@"Content-Length"] longLongValue];
        }
    }
    return contentLength;
}

static BOOL _ImageDownloadIsComplete(NSHTTPURLResponse * __nullable response,
                                     NSError * __nullable error);
static BOOL _ImageDownloadIsComplete(NSHTTPURLResponse * __nullable response,
                                     NSError * __nullable error)
{
    if (response.statusCode == 200 /* OK */ || response.statusCode == 206 /* Partial Content */) {
        if (!error) {
            return YES;
        }
    }
    return NO;
}

static NSString *_ImageDownloadLastModifiedString(NSHTTPURLResponse * __nullable response,
                                                  NSError * __nullable error);
static NSString *_ImageDownloadLastModifiedString(NSHTTPURLResponse * __nullable response,
                                                  NSError * __nullable error)
{
    if (response.statusCode == 200 /* OK */ || response.statusCode == 206 /* Partial Content */) {
        if (error) {
            // can only support partial downloads if Accept-Ranges is "bytes" and Last-Modified is present
            NSString *lastModified = [response.allHeaderFields tip_objectForCaseInsensitiveKey:@"Last-Modified"];
            if (lastModified) {
                NSString *acceptRanges = [response.allHeaderFields tip_objectForCaseInsensitiveKey:@"Accept-Ranges"];
                if ([acceptRanges compare:@"bytes" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
                    return lastModified;
                }
            }
        }
    }
    return nil;
}

static void _ImageDownloadSetProgressStateFailureAndCancel(TIPImageDownloadInternalContext *context,
                                                           TIPImageFetchErrorCode code,
                                                           id<TIPImageFetchDownload> __nullable download);
static void _ImageDownloadSetProgressStateFailureAndCancel(TIPImageDownloadInternalContext *context,
                                                           TIPImageFetchErrorCode code,
                                                           id<TIPImageFetchDownload> __nullable download)
{
    TIPAssertDownloaderQueue();
    TIPAssert(context);

    NSString *cancelDescription = nil;
    switch (code) {
        case TIPImageFetchErrorCodeDownloadEncounteredToStartMoreThanOnce:
            cancelDescription = @"download started more than once";
            break;
        case TIPImageFetchErrorCodeDownloadAttemptedToHydrateRequestMoreThanOnce:
            cancelDescription = @"download hydrated more than once";
            break;
        case TIPImageFetchErrorCodeDownloadReceivedResponseMoreThanOnce:
            cancelDescription = @"download received response more than once";
            break;
        case TIPImageFetchErrorCodeDownloadNeverStarted:
            cancelDescription = @"download wasn't started before download callbacks happened";
            break;
        case TIPImageFetchErrorCodeDownloadNeverAttemptedToHydrateRequest:
            cancelDescription = @"download wasn't hydrated before downloading";
            break;
        case TIPImageFetchErrorCodeDownloadNeverReceivedResponse:
            cancelDescription = @"download didn't receive a response before receiving data or completing";
            break;
        default:
            cancelDescription = @"encountered error downloading";
            break;
    }

    context->_progressStateError = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                                       code:code
                                                   userInfo:nil];
    [download cancelWithDescription:[NSString stringWithFormat:@"TIP: %@ %@", download, cancelDescription]];
}

static BOOL _CanCoalesceDelegate(NSObject<TIPImageDownloadDelegate> *delegate,
                                 TIPImageDownloadInternalContext *context);
static BOOL _CanCoalesceDelegate(NSObject<TIPImageDownloadDelegate> *delegate,
                                 TIPImageDownloadInternalContext *context)
{
    TIPAssertDownloaderQueue();

    id<TIPImageDownloadRequest> request = delegate.imageDownloadRequest;
    id<TIPImageDownloadDelegate> otherDelegate = context.firstDelegate;
    id<TIPImageDownloadRequest> otherRequest = otherDelegate.imageDownloadRequest;

    if (![otherRequest.imageDownloadURL isEqual:request.imageDownloadURL]) {
        return NO;
    }

    if (![otherRequest.imageDownloadIdentifier isEqual:request.imageDownloadIdentifier]) {
        return NO;
    }

    if (otherRequest.imageDownloadHydrationBlock != request.imageDownloadHydrationBlock) {
        return NO;
    }

    if (otherRequest.imageDownloadAuthorizationBlock != request.imageDownloadAuthorizationBlock) {
        return NO;
    }

    if (delegate.imagePipeline != otherDelegate.imagePipeline) {
        return NO;
    }

    return YES;
}

@interface TIPImageDownloader () <TIPImageFetchDownloadClient>
@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageDownloader (Background)

- (void)_background_dequeuePendingDownloads;
- (id<TIPImageFetchDownload>)_background_getOrCreateDownload:(NSObject<TIPImageDownloadDelegate> *)delegate;
- (void)_background_clearDownload:(id<TIPImageFetchDownload>)download;
- (void)_background_updatePriorityOfDownload:(id<TIPImageFetchDownload>)download;
- (void)_background_removeDelegate:(NSObject<TIPImageDownloadDelegate> *)delegate
                      fromDownload:(id<TIPImageFetchDownload>)download;

@end

@implementation TIPImageDownloader
{
    dispatch_queue_t _downloaderQueue;
    NSMutableDictionary<NSURL *, NSMutableArray<id<TIPImageFetchDownload>> *> *_constructedDownloads;
    NSMutableArray<id<TIPImageFetchDownload>> *_pendingDownloads;
    NSUInteger _runningDownloadsCount;
}

+ (instancetype)sharedInstance
{
    static TIPImageDownloader *sDownloader;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sDownloader = [[TIPImageDownloader alloc] initInternal];
    });
    return sDownloader;
}

- (instancetype)initInternal
{
    self = [super init];
    if (self) {
        _downloaderQueue = dispatch_queue_create(kTIPImageDownloaderQueueName, DISPATCH_QUEUE_SERIAL);
        _constructedDownloads = [NSMutableDictionary dictionary];
        _pendingDownloads = [NSMutableArray array];
    }
    return self;
}

- (id<TIPImageDownloadContext>)fetchImageWithDownloadDelegate:(id<TIPImageDownloadDelegate>)delegate
{
    __block id<TIPImageFetchDownload> download = nil;
    dispatch_sync(_downloaderQueue, ^{
        download = [self _background_getOrCreateDownload:delegate];
    });
    return (id<TIPImageDownloadContext>)download;
}

- (void)removeDelegate:(id<TIPImageDownloadDelegate>)delegate
            forContext:(id<TIPImageDownloadContext>)context
{
    if (!context) {
        return;
    }

    tip_dispatch_async_autoreleasing(_downloaderQueue, ^{
        [self _background_removeDelegate:delegate
                            fromDownload:(id<TIPImageFetchDownload>)context];
    });
}

- (void)updatePriorityOfContext:(id<TIPImageDownloadContext>)context
{
    if (!context) {
        return;
    }

    tip_dispatch_async_autoreleasing(_downloaderQueue, ^{
        [self _background_updatePriorityOfDownload:(id<TIPImageFetchDownload>)context];
    });
}

#pragma mark Delegate

- (void)imageFetchDownloadDidStart:(id<TIPImageFetchDownload>)download
{
    TIPAssertDownloaderQueue();

    @autoreleasepool {
        TIPImageDownloadInternalContext *context = (TIPImageDownloadInternalContext *)download.context;
        TIPAssert(context);
        if (!context) {
            return;
        }

        if (context->_flags.didStart) {
            _ImageDownloadSetProgressStateFailureAndCancel(context, TIPImageFetchErrorCodeDownloadEncounteredToStartMoreThanOnce, download);
            return;
        }
        context->_flags.didStart = YES;

#if TIP_LOG_DOWNLOAD_PROGRESS
        TIPLogDebug(@"(%@)[%p] - starting", context.originalRequest.URL, download);
#endif

        [context executePerDelegateSuspendingQueue:_downloaderQueue
                                             block:^(id<TIPImageDownloadDelegate> delegate) {
                                                 [delegate imageDownloadDidStart:(id)download];
                                             }];
    }
}

- (void)imageFetchDownload:(id<TIPImageFetchDownload>)download
     didReceiveURLResponse:(NSHTTPURLResponse *)response
{
    TIPAssertDownloaderQueue();

    @autoreleasepool {
        TIPImageDownloadInternalContext *context = (TIPImageDownloadInternalContext *)download.context;
        TIPAssert(context);
        if (!context) {
            return;
        }

        if (context->_flags.didReceiveResponse) {
            _ImageDownloadSetProgressStateFailureAndCancel(context, TIPImageFetchErrorCodeDownloadReceivedResponseMoreThanOnce, download);
            return;
        }
        context->_flags.didReceiveResponse = YES;

        context->_response = response;
        context->_contentLength = (NSUInteger)MAX(0LL, _ExpectedResponseBodySize(response));

        if (!context->_flags.didRequestAuthorization) {
            _ImageDownloadSetProgressStateFailureAndCancel(context, TIPImageFetchErrorCodeDownloadNeverAttemptedToAuthorizeRequest, download);
            return;
        }
        TIPAssert(context.hydratedRequest);

        if (200 /* OK */ == context->_response.statusCode) {
            TIPPartialImage *partialImage = context->_partialImage;
            // reset the resuming info
            context->_partialImage = nil;
            context->_temporaryFile = nil;
            context->_lastModified = nil;
            [context executePerDelegateSuspendingQueue:_downloaderQueue
                                                 block:^(id<TIPImageDownloadDelegate> delegate) {
                                                     [delegate imageDownload:(id)download didResetFromPartialImage:partialImage];
                                                 }];
        } else if (206 /* Partial Content */ == context->_response.statusCode) {
            TIPLogDebug(@"Did resume download of image at URL: %@", context.originalRequest.URL);
            if ((context->_contentLength + context->_partialImage.byteCount) != context->_partialImage.expectedContentLength) {
                TIPLogWarning(@"Continued partial image expected Content-Lenght (%tu) does not match recalculated expected Content-Length (%tu)", context->_partialImage.expectedContentLength, context->_contentLength + context->_partialImage.byteCount);
            }
            context->_contentLength = context->_partialImage.expectedContentLength;
        } else {
            // Failure status code, image is not going to load
            context->_flags.responseStatusCodeIsFailure = YES;
        }

#if TIP_LOG_DOWNLOAD_PROGRESS
        TIPLogDebug(@"(%@)[%p] - got response (Content-Length: %tu)", context.originalRequest.URL, download, context.contentLength);
#endif
    }
}

- (void)imageFetchDownload:(id<TIPImageFetchDownload>)download
            didReceiveData:(NSData *)data
{
    TIPAssertDownloaderQueue();

    @autoreleasepool {
        TIPImageDownloadInternalContext *context = (TIPImageDownloadInternalContext *)download.context;
        TIPAssert(context);
        if (!context) {
            return;
        }

        TIPImageDecoderAppendResult result = TIPImageDecoderAppendResultDidProgress;
        const NSUInteger byteCount = data.length;

#if TIP_LOG_DOWNLOAD_PROGRESS
        TIPLogDebug(@"(%@)[%p] - downloaded %tu bytes", context.originalRequest.URL, download, byteCount);
#endif

        if (!context->_flags.didReceiveResponse) {
            _ImageDownloadSetProgressStateFailureAndCancel(context,
                                                           TIPImageFetchErrorCodeDownloadNeverReceivedResponse,
                                                           download);
            return;
        }

        if (context->_flags.responseStatusCodeIsFailure) {
            // data is for a failure, don't capture
            return;
        }

        // Prep
        if (!context->_flags.didReceiveData) {
            context->_flags.didReceiveData = YES;
            if (!context->_temporaryFile) {
                context->_temporaryFile = [context.firstDelegate regenerateImageDownloadTemporaryFileForImageDownload:(id)download];
            }
        }
        if (!context->_partialImage) {
            context->_partialImage = [[TIPPartialImage alloc] initWithExpectedContentLength:context->_contentLength];
            if (context->_decoderConfigMap) {
                [context->_partialImage updateDecoderConfigMap:context->_decoderConfigMap];
            }
        }

        // Update partial image
        result = [context->_partialImage appendData:data final:NO];

        // Update temporary file
        [context->_temporaryFile appendData:data];

        if (context.delegateCount > 0) {
            TIPPartialImage *partialImage = context->_partialImage;
            [context executePerDelegateSuspendingQueue:_downloaderQueue
                                                 block:^(id<TIPImageDownloadDelegate> delegate) {
                                                     [delegate imageDownload:(id)download
                                                              didAppendBytes:byteCount
                                                              toPartialImage:partialImage
                                                                      result:result];
                                                 }];
        } else {
            // Running as a "detached" download, time to clean it up
            [self _background_clearDownload:download];
            [download cancelWithDescription:TIPImageDownloaderCancelSource];
        }
    }
}

- (void)imageFetchDownload:(id<TIPImageFetchDownload>)download
            hydrateRequest:(NSURLRequest *)request
                completion:(TIPImageFetchDownloadRequestHydrationCompleteBlock)complete
{
    TIPAssertDownloaderQueue();

    @autoreleasepool {
        TIPImageDownloadInternalContext *context = (TIPImageDownloadInternalContext *)download.context;
        TIPAssert(context);
        if (!context) {
            complete(nil);
            return;
        }

        if (context->_flags.didRequestHydration) {
            _ImageDownloadSetProgressStateFailureAndCancel(context, TIPImageFetchErrorCodeDownloadAttemptedToHydrateRequestMoreThanOnce, download);
            return;
        }
        context->_flags.didRequestHydration = YES;

        if (!context->_flags.didStart) {
            _ImageDownloadSetProgressStateFailureAndCancel(context,
                                                           TIPImageFetchErrorCodeDownloadNeverStarted,
                                                           download);
            return;
        }

#if TIP_LOG_DOWNLOAD_PROGRESS
        TIPLogDebug(@"(%@)[%p] - hydrating", context.originalRequest.URL, download);
#endif

        void(^internalResumeBlock)(NSUInteger, NSString *, NSURLRequest *) = ^(NSUInteger alreadyDownloadedBytes, NSString *lastModified, NSURLRequest *requestToSend) {
            if (alreadyDownloadedBytes > 0 && lastModified.length > 0) {
                NSMutableURLRequest *mURLRequst = [requestToSend mutableCopy];
                if (mURLRequst) {
                    [mURLRequst setValue:[NSString stringWithFormat:@"bytes=%tu-", alreadyDownloadedBytes] forHTTPHeaderField:@"Range"];
                    [mURLRequst setValue:lastModified forHTTPHeaderField:@"If-Range"];
                    requestToSend = mURLRequst;
                }
            }

#if TIP_LOG_DOWNLOAD_PROGRESS
            TIPLogDebug(@"(%@)[%p] - did hydrate", context.originalRequest.URL, download);
#endif

            context.hydratedRequest = [requestToSend copy];
            TIPAssert(context.hydratedRequest != nil);
            complete(nil);
        };

        // Pull out contextual values since accessing the context object from another thread is unsafe
        NSUInteger partialImageByteCount = context->_partialImage.byteCount;
        NSString *lastModified = context->_lastModified;
        TIPImageFetchHydrationCompletionBlock hydrateBlock = ^(NSURLRequest * __nullable hydratedRequest, NSError * __nullable error) {
            if (error) {
                complete(error);
                return;
            }

            if (!hydratedRequest) {
                hydratedRequest = request;
            }

            TIPAssert([request.URL isEqual:hydratedRequest.URL]);
            if (![request.URL isEqual:hydratedRequest.URL]) {
                complete([NSError errorWithDomain:TIPImageFetchErrorDomain
                                             code:TIPImageFetchErrorCodeIllegalModificationByHydrationBlock
                                         userInfo:@{ @"originalURL" : request.URL,
                                                     @"modifiedURL" : hydratedRequest.URL }]);
                return;
            }

            TIPAssert([request.HTTPMethod isEqualToString:hydratedRequest.HTTPMethod]);
            if (![request.HTTPMethod isEqualToString:hydratedRequest.HTTPMethod]) {
                complete([NSError errorWithDomain:TIPImageFetchErrorDomain
                                             code:TIPImageFetchErrorCodeIllegalModificationByHydrationBlock
                                         userInfo:@{ @"originalHTTPMethod" : request.HTTPMethod ?: [NSNull null],
                                                     @"modifiedHTTPMethod" : hydratedRequest.HTTPMethod ?: [NSNull null] }]);
                return;
            }

            internalResumeBlock(partialImageByteCount, lastModified, hydratedRequest);
        };

        id<TIPImageDownloadDelegate> delegate = context.firstDelegate;
        dispatch_queue_t delegateQueue = delegate.imageDownloadDelegateQueue;
        TIPImageFetchHydrationBlock hydrationBlock = delegate.imageDownloadRequest.imageDownloadHydrationBlock;
        if (hydrationBlock) {
            if (delegateQueue) {
                tip_dispatch_async_autoreleasing(delegateQueue, ^{
                    hydrationBlock(request, context, hydrateBlock);
                });
            } else {
                hydrationBlock(request, context, hydrateBlock);
            }
        } else {
            hydrateBlock(nil, nil);
        }
    }
}

- (void)imageFetchDownload:(id<TIPImageFetchDownload>)download
          authorizeRequest:(NSURLRequest *)request
                completion:(TIPImageFetchDownloadRequestAuthorizationCompleteBlock)complete
{
    TIPAssertDownloaderQueue();

    @autoreleasepool {
        TIPImageDownloadInternalContext *context = (TIPImageDownloadInternalContext *)download.context;
        TIPAssert(context);
        if (!context) {
            complete(nil);
            return;
        }

        if (context->_flags.didRequestAuthorization) {
            _ImageDownloadSetProgressStateFailureAndCancel(context, TIPImageFetchErrorCodeDownloadAttemptedToAuthorizeRequestMoreThanOnce, download);
            return;
        }
        context->_flags.didRequestAuthorization = YES;

        if (!context->_flags.didRequestHydration) {
            _ImageDownloadSetProgressStateFailureAndCancel(context,
                                                           TIPImageFetchErrorCodeDownloadNeverAttemptedToHydrateRequest,
                                                           download);
            return;
        }

#if TIP_LOG_DOWNLOAD_PROGRESS
        TIPLogDebug(@"(%@)[%p] - authorizing", context.originalRequest.URL, download);
#endif

        TIPImageFetchAuthorizationCompletionBlock authCompleteBlock = ^(NSString * __nullable authValue, NSError * __nullable error) {
            if (error) {
                complete(error);
                return;
            }

            if (authValue) {
                context.authorization = authValue;
            }

#if TIP_LOG_DOWNLOAD_PROGRESS
            TIPLogDebug(@"(%@)[%p] - did authorize", context.originalRequest.URL, download);
#endif

            complete(nil);
        };

        id<TIPImageDownloadDelegate> delegate = context.firstDelegate;
        dispatch_queue_t delegateQueue = delegate.imageDownloadDelegateQueue;
        TIPImageFetchAuthorizationBlock authorizationBlock = delegate.imageDownloadRequest.imageDownloadAuthorizationBlock;
        if (authorizationBlock) {
            if (delegateQueue) {
                tip_dispatch_async_autoreleasing(delegateQueue, ^{
                    authorizationBlock(request, context, authCompleteBlock);
                });
            } else {
                authorizationBlock(request, context, authCompleteBlock);
            }
        } else {
            authCompleteBlock(nil, nil);
        }
    }
}

- (void)imageFetchDownloadWillRetry:(id<TIPImageFetchDownload>)download
{
    TIPAssertDownloaderQueue();

    @autoreleasepool {

        TIPImageDownloadInternalContext *context = (TIPImageDownloadInternalContext *)download.context;
        TIPAssert(context);
        if (!context) {
            return;
        }

        if (context->_flags.didComplete || context->_progressStateError != nil) {
            TIPLogError(@"Cannot retry a download after it has already completed! %@", download);
            return;
        }

        if (context->_flags.didReceiveData) {
            TIPLogError(@"Cannot retry a download if it has already appended data, need to start a new TIP fetch!");
            _ImageDownloadSetProgressStateFailureAndCancel(context,
                                                           TIPImageFetchErrorCodeDownloadWantedToRetryAfterAlreadyLoadingData,
                                                           download);
            return;
        }

#if TIP_LOG_DOWNLOAD_PROGRESS
        TIPLogDebug(@"(%@)[%p] - retrying", context.originalRequest.URL, download);
#endif

        [context reset];
    }
}

- (void)imageFetchDownload:(id<TIPImageFetchDownload>)download
      didCompleteWithError:(nullable NSError *)error
{
    TIPAssertDownloaderQueue();

    @autoreleasepool {

        TIPImageDownloadInternalContext *context = (TIPImageDownloadInternalContext *)download.context;
        TIPAssert(context);
        if (!context) {
            return;
        }

        if (context->_flags.didComplete) {
            TIPAssertMessage(NO, @"%@ completed more than once", download);
            return;
        }
        context->_flags.didComplete = YES;

        [self _background_clearDownload:download];
        context->_download = nil;
        [download discardContext];

#if TIP_LOG_DOWNLOAD_PROGRESS
        TIPLogDebug(@"(%@)[%p] - finished %@", context.originalRequest.URL, download, error ?: @(context.response.statusCode));
#endif

        if (!error && !context->_progressStateError && !context->_flags.didReceiveData && !context->_flags.responseStatusCodeIsFailure) {
            _ImageDownloadSetProgressStateFailureAndCancel(context,
                                                           TIPImageFetchErrorCodeDownloadNeverReceivedResponse,
                                                           nil /* don't cancel */);
        }
        if (error) {
            if (context->_response.statusCode == 200 || context->_response.statusCode == 206) {
                if (context->_partialImage.expectedContentLength == context->_partialImage.byteCount && context->_partialImage.byteCount > 0) {
                    /**
                     Networking is hard :(

                     It is not unheard of for a service responding with the payload of an image to mistakenly
                     disconnect, timeout or indicate failure for the response after it has successfully delivered
                     the final payload byte.

                     To protect against needless image resumes when we already have all the data,
                     catch cases when the download provides an error but the image had loaded all data.
                     */

                    // 1) report the problem
                    NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
                    info[@"error"] = error;
                    info[@"response"] = context->_response;
                    if (download.finalURLRequest != nil) {
                        info[@"request"] = download.finalURLRequest;
                    }
                    if ([download respondsToSelector:@selector(downloadMetrics)] && download.downloadMetrics) {
                        info[@"metrics"] = download.downloadMetrics;
                    }
                    [[TIPGlobalConfiguration sharedInstance] postProblem:TIPProblemImageDownloadedWithUnnecessaryError
                                                                userInfo:info];

                    // 2) clear the unnecessary error
                    error = nil;
                }
            }
        }
        if (!error) {
            error = context->_progressStateError;
        }

        const BOOL isComplete = _ImageDownloadIsComplete(context->_response, error);
        [context->_partialImage appendData:nil final:isComplete];
        const BOOL didReadHeaders = (context->_partialImage.state > TIPPartialImageStateLoadingHeaders);
        const BOOL complete = isComplete && didReadHeaders;
        context->_lastModified = _ImageDownloadLastModifiedString(context->_response, error);
        NSUInteger totalBytes = context->_partialImage.byteCount;
        NSString *imageType = context->_partialImage.type;
        NSData* finalData = (isComplete) ? context->_partialImage.data : nil;
        id<TIPImageDownloadDelegate> firstDelegate = context.firstDelegate;
        const NSUInteger delegateCount = context.delegateCount;

        if (!didReadHeaders || (!complete && !context->_lastModified && !context->_partialImage.progressive)) {
            // Abandon the partial image
            context->_partialImage = nil;
            context->_lastModified = nil;
        }

        NSTimeInterval imageRenderLatency = 0.0;
        TIPImageContainer *image = nil;
        if (complete && firstDelegate != nil) {
            const uint64_t startMachTime = mach_absolute_time();
            image = [context->_partialImage renderImageWithMode:TIPImageDecoderRenderModeFullFrameProgress
                                               targetDimensions:(delegateCount == 1) ? firstDelegate.imageDownloadRequest.targetDimensions : CGSizeZero
                                              targetContentMode:(delegateCount == 1) ? firstDelegate.imageDownloadRequest.targetContentMode : UIViewContentModeCenter
                                                        decoded:NO];
            imageRenderLatency = TIPComputeDuration(startMachTime, mach_absolute_time());
        }

        if (context->_temporaryFile) {
            if (context->_partialImage) {

                TIPImageCacheEntryContext *imageContext = nil;
                if (complete) {
                    imageContext = [[TIPCompleteImageEntryContext alloc] init];
                } else {
                    imageContext = [[TIPPartialImageEntryContext alloc] init];
                    TIPPartialImageEntryContext *partialContext = (id)imageContext;
                    partialContext.lastModified = context->_lastModified;
                    partialContext.expectedContentLength = context->_partialImage.expectedContentLength;
                }
                imageContext.animated = context->_partialImage.animated;

                id<TIPImageDownloadRequest> firstDelegateRequest = firstDelegate.imageDownloadRequest;
                if (firstDelegateRequest != nil) {
                    TIPImageFetchOptions options = firstDelegateRequest.imageDownloadOptions;
                    imageContext.TTL = firstDelegateRequest.imageDownloadTTL;
                    imageContext.updateExpiryOnAccess = TIP_BITMASK_EXCLUDES_FLAGS(options, TIPImageFetchDoNotResetExpiryOnAccess);
                    imageContext.treatAsPlaceholder = TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageFetchTreatAsPlaceholder);
                    imageContext.URL = firstDelegateRequest.imageDownloadURL;
                } else {
                    // Defaults for dealing with "detached" download
                    imageContext.TTL = TIPTimeToLiveDefault;
                    imageContext.updateExpiryOnAccess = NO;
                    imageContext.treatAsPlaceholder = NO;
                    imageContext.URL = context.originalRequest.URL;
                }

                if (imageContext.TTL <= 0.0) {
                    imageContext.TTL = TIPTimeToLiveDefault;
                }

                imageContext.dimensions = context->_partialImage.dimensions;
                if (TIPSizeEqualToZero(imageContext.dimensions) && image) {
                    imageContext.dimensions = image.dimensions;
                }

                if (gTwitterImagePipelineAssertEnabled) {
                    // Complex assertion, break it down

                    if (!firstDelegate) {
                        // OK
                    } else {
                        NSString *contextTempIdentifier = context->_temporaryFile.imageIdentifier;
                        NSString *delegateDownloadIdentifier = firstDelegateRequest.imageDownloadIdentifier;
                        if (!contextTempIdentifier || !delegateDownloadIdentifier) {
                            // Not OK!  Need to have identifiers!
                            TIPAssertNever();
                        } else if (![contextTempIdentifier isEqualToString:delegateDownloadIdentifier]) {
                            // Not OK!  Identifiers need to match!
                            TIPAssertNever();
                        } else {
                            // OK
                        }
                    }
                }
                [context->_temporaryFile finalizeWithContext:imageContext];
            }

            context->_temporaryFile = nil;
            if (complete) {
                context->_partialImage = nil;
            }
        }

        if (!firstDelegate) {
            // Nothing left to do if we don't have a delegate
            return;
        }

        if (!error && !image) {
            if (context->_flags.responseStatusCodeIsFailure || 200 != ((context->_response.statusCode / 100) * 100)) {
                error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                            code:TIPImageFetchErrorCodeHTTPTransactionError
                                        userInfo:@{ TIPErrorInfoHTTPStatusCodeKey : @(context->_response.statusCode) }];
            } else if (isComplete) {

                NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
                id value = nil;

                value = context->_temporaryFile.imageIdentifier;
                if (value) {
                    userInfo[TIPProblemInfoKeyImageIdentifier] = value;
                }
                value = context.originalRequest.URL;
                if (value) {
                    userInfo[TIPProblemInfoKeyImageURL] = value;
                }
                value = download.finalURLRequest;
                if (value) {
                    userInfo[@"finalRequest"] = value;
                }
                value = context->_response;
                if (value) {
                    userInfo[@"response"] = value;
                }
                value = [download respondsToSelector:@selector(downloadMetrics)] ? [download downloadMetrics] : nil;
                if (value) {
                    userInfo[@"metrics"] = value;
                }

                error = [NSError errorWithDomain:TIPImageFetchErrorDomain
                                            code:TIPImageFetchErrorCodeCouldNotDecodeImage
                                        userInfo:userInfo];
                [[TIPGlobalConfiguration sharedInstance] postProblem:TIPProblemImageDownloadedCouldNotBeDecoded
                                                            userInfo:userInfo];

            } else { // !response.isComplete
                TIPAssertNever();
                error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                            code:EBADEXEC
                                        userInfo:nil];
            }
        }

        TIPAssert((nil == error) ^ (nil == image));

        // Pull out contextual values since accessing the context object from another thread is unsafe
        TIPPartialImage *partialImage = context->_partialImage;
        NSString *lastModified = context->_lastModified;
        const NSInteger statusCode = context->_response.statusCode;
        [context executePerDelegateSuspendingQueue:NULL block:^(id<TIPImageDownloadDelegate> delegateInner) {
            // only the first delegate is granted the honor of caching the partial image
            const BOOL isFirstDelegate = (delegateInner == firstDelegate);
            [delegateInner imageDownload:(id)download
             didCompleteWithPartialImage:((isFirstDelegate) ? partialImage : nil)
                            lastModified:((isFirstDelegate) ? lastModified : nil)
                                byteSize:((isFirstDelegate) ? totalBytes : 0)
                               imageType:((isFirstDelegate) ? imageType : nil)
                                   image:image
                               imageData:((isFirstDelegate) ? finalData : nil)
                      imageRenderLatency:imageRenderLatency
                              statusCode:statusCode
                                   error:error];
        }];

    }
}

@end

#pragma mark Background

@implementation TIPImageDownloader (Background)

- (void)_background_dequeuePendingDownloads
{
    TIPAssertDownloaderQueue();

    // Cast signed max value to unsigned making negative values (infinite) be HUGE (and effectively infinite)
    const NSUInteger count = (NSUInteger)[TIPGlobalConfiguration sharedInstance].maxConcurrentImagePipelineDownloadCount;
    while (_runningDownloadsCount < count && _pendingDownloads.count > 0) {
        id<TIPImageFetchDownload> download = _pendingDownloads.firstObject;
        [_pendingDownloads removeObjectAtIndex:0];
        _runningDownloadsCount++;
        [download start];
    }
}

- (void)_background_updatePriorityOfDownload:(id<TIPImageFetchDownload>)download
{
    TIPAssertDownloaderQueue();

    if ([download respondsToSelector:@selector(setPriority:)]) {
        TIPImageDownloadInternalContext *context = (TIPImageDownloadInternalContext *)download.context;
        NSOperationQueuePriority priority = [context downloadPriority];
        download.priority = priority;
    }
}

- (void)_background_removeDelegate:(NSObject<TIPImageDownloadDelegate> *)delegate
                      fromDownload:(id<TIPImageFetchDownload>)download
{
    TIPAssertDownloaderQueue();

    TIPImageDownloadInternalContext *context = (TIPImageDownloadInternalContext *)download.context;

    // Multiple delegates?
    if (context.delegateCount > 1) {
        // Just remove the delegate
        [context removeDelegate:delegate];
        return;
    }

    // Is it a known delegate?
    if (![context containsDelegate:delegate]) {
        // Unknown delegate, just no-op
        return;
    }

    [self _background_clearDownload:download];
    [download cancelWithDescription:TIPImageDownloaderCancelSource];
    TIPLogInformation(@"Download[%p] has no more delegates and is below the acceptable download speed, cancelling", download);
}

- (void)_background_clearDownload:(id<TIPImageFetchDownload>)download
{
    TIPAssertDownloaderQueue();

    TIPImageDownloadInternalContext *context = (TIPImageDownloadInternalContext *)download.context;
    NSURL *URL = context.originalRequest.URL;
    NSMutableArray<id<TIPImageFetchDownload>> *downloads = _constructedDownloads[URL];
    if (downloads) {
        BOOL downloadFound = NO;
        NSUInteger count = downloads.count;
        NSUInteger index = [downloads indexOfObjectIdenticalTo:download];
        if (index < count) {
            [downloads removeObjectAtIndex:index];
            count--;
            downloadFound = YES;
        }
        TIPAssert(downloads.count == count);
        if (!count) {
            [_constructedDownloads removeObjectForKey:URL];
        }

        if (downloadFound) {
            index = [_pendingDownloads indexOfObjectIdenticalTo:download];
            if (index == NSNotFound) {
                TIPAssert(_runningDownloadsCount > 0);
                _runningDownloadsCount--;
                [self _background_dequeuePendingDownloads];
            } else {
                [_pendingDownloads removeObjectAtIndex:index];
            }
        }
    }
}

- (id<TIPImageFetchDownload>)_background_getOrCreateDownload:(NSObject<TIPImageDownloadDelegate> *)delegate
{
    TIPAssertDownloaderQueue();

    id<TIPImageFetchDownload> download = nil;
    NSObject<TIPImageDownloadRequest> *request = delegate.imageDownloadRequest;
    NSURL *URL = request.imageDownloadURL;
    NSMutableArray<id<TIPImageFetchDownload>> *constructedDownloads = _constructedDownloads[URL];

    // Coalesce if possible
    for (id<TIPImageFetchDownload> existingDownload in constructedDownloads) {
        TIPImageDownloadInternalContext *context = (TIPImageDownloadInternalContext *)existingDownload.context;
        if (_CanCoalesceDelegate(delegate, context)) {
            TIPLogDebug(@"Coalescing two requests for the same image: ('%@' ==> '%@')", request.imageDownloadIdentifier, request.imageDownloadURL);

            download = existingDownload;

            [context addDelegate:delegate];
            if (context->_partialImage) {
                // Prepopulate with progress (if available/possible)

                TIPImageDecoderAppendResult result = TIPImageDecoderAppendResultDidProgress;
                if (context->_partialImage.frameCount > 0) {
                    result = TIPImageDecoderAppendResultDidLoadFrame;
                } else if (context->_partialImage.state > TIPPartialImageStateLoadingHeaders) {
                    result = TIPImageDecoderAppendResultDidLoadHeaders;
                }

                // Pull out contextual values since accessing the context object from another thread is unsafe
                TIPPartialImage *partialImage = context->_partialImage;
                const BOOL didStart = context->_flags.didStart;
                const BOOL didReceiveFirstByte = context->_flags.didReceiveData;
                NSInteger statusCode = context->_response.statusCode;
                [TIPImageDownloadInternalContext executeDelegate:delegate
                                                 suspendingQueue:_downloaderQueue
                                                           block:^(id<TIPImageDownloadDelegate> blockDelegate) {

                    if (200 /* OK */ == statusCode) {
                        // already started a fresh download, reset
                        [blockDelegate imageDownload:(id)download
                            didResetFromPartialImage:partialImage];
                    }

                    if (didStart) {
                        // already started receiving data, catch the delegate up to speed
                        [blockDelegate imageDownloadDidStart:(id)download];

                        if (didReceiveFirstByte) {
                            // already started receiving data, catch the delegate up to speed
                            [blockDelegate imageDownload:(id)download
                                          didAppendBytes:partialImage.byteCount
                                          toPartialImage:partialImage
                                                  result:result];
                        }
                    }

                }];
            }
        }
    }

    // Create a new operation if necessary
    if (!download) {
        TIPImageDownloadInternalContext *context = [[TIPImageDownloadInternalContext alloc] init];
        context->_lastModified = request.imageDownloadLastModified;
        context->_partialImage = request.imageDownloadPartialImageForResuming;
        context->_temporaryFile = request.imageDownloadTemporaryFileForResuming;
        context->_decoderConfigMap = request.decoderConfigMap;

        [context addDelegate:delegate];

        NSMutableURLRequest *URLRequest = [NSMutableURLRequest requestWithURL:URL];
        URLRequest.allHTTPHeaderFields = request.imageDownloadHeaders;

        context.originalRequest = URLRequest;
        context.downloadQueue = _downloaderQueue;
        context.client = self;

        download = [[TIPGlobalConfiguration sharedInstance] createImageFetchDownloadWithContext:context];
        context->_download = download;

        if (!constructedDownloads) {
            constructedDownloads = [[NSMutableArray alloc] init];
            _constructedDownloads[URL] = constructedDownloads;
        }
        [constructedDownloads addObject:download];
        [_pendingDownloads addObject:download];
        [self _background_dequeuePendingDownloads];
    }

    [self _background_updatePriorityOfDownload:download];
    return download;
}

@end

NS_ASSUME_NONNULL_END
