//
//  TIPImageFetchDownload.h
//  TwitterImagePipeline
//
//  Created on 8/24/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol TIPImageFetchDownloadClient;
@protocol TIPImageFetchDownloadContext;

NS_ASSUME_NONNULL_BEGIN

//! Name for the exception when `TIPImageFetchDownload` construction fails
FOUNDATION_EXTERN NSString * const TIPImageFetchDownloadConstructorExceptionName;

/**
 Abstraction protocol for custom networking support in __TIP__.
 Implement a `TIPImageFetchDownload` concrete class and a `TIPImageFetchDownloadProvider` concrete
 class and provide an instance of the provider to
 `[TIPGlobalConfiguration setImageFetchDownloadProvider:]` to have custom networking support.
 By default, an implementation that uses `NSURLSession` will be used.
 All methods on `TIPImageFetchDownload` are for __TIP's__ exclusive use.
 */
@protocol TIPImageFetchDownload <NSObject>

@required

/**
 The context that the download was initialized with.
 If the _context_ is not the same as what was provided via `initWithContext:`,
 an exception will be thrown.
 The context is an opaque object that offers a few properties that can be used
 by the `TIPImageFetchDownload` implementation.

 @note Since the _context_ can be discarded, it is wise to retain any relevant info from the context
 that could be needed beyond the lifespan of the _context_ instance.
 A good example of this would be the `downloadQueue` which may be desirable to use after the
 _context_ is already discarded.
 */
@property (nonatomic, readonly, nullable) id<TIPImageFetchDownloadContext> context;

/**
 Called by __TIP_ when the download should start.

 When starting a download it is __REQUIRED__ that the request used to load the image be hydrated
 __BEFORE__ performing the load __AND__ that the hydrated request __MUST__ be used for loading
 (not the original request).

 Hydration can happen any time after `start` is called, but must complete before actually loading
 (obviously since the hydrated request needs to be loaded).

 See `[TIPImageFetchDownloadContext client]` and
 `[TIPImageFetchDownloadClient imageFetchOperation:hydrateRequest:completion:]`.
 See `[TIPImageFetchDownloadContext originalRequest]` and
 `[TIPImageFetchDownloadContext hydratedRequest]`.
 */
- (void)start;

/**
 Called by __TIP__ to cancel the download.
 @param cancelDescription a contextual description for why the download was cancelled
 Implementer should cancel the underlying network load when this method is called.
 @warning Whether the underlying network load has started or not, the implementer MUST eventually
 call `[TIPImageFetchDownloadClient imageFetchDownload:didCompleteWithError:]` on `context.client`
 from the `context.downloadQueue` queue. An error reflecting cancellation must be provided. Failure
 to complete the download will yield a "hung" download which can lead to both a memory leak and a
 clogged pool for __TIP__ operations.
 */
- (void)cancelWithDescription:(NSString *)cancelDescription;

/**
 Called by __TIP__ to have the _context_ be discarded.
 The _context_ can host a lot of opaque information that, if kept retained, could cause problems.
 Implementers should release all references to the _context_ when this method is called and
 update the _context_ property so that it will return `nil` (easiest to just clear the ivar storing
 the reference to the _context_). It may be useful to cache the `originalRequest`, `hydratedRequest`
 and/or `downloadQueue` before discarding the _context_, but that is up to the implementer.
 Do NOT cache the `client`.
 */
- (void)discardContext;

@required

/**
 Required readonly property to return the final "known" `NSURLRequest` of the download.
 */
@property (nonatomic, readonly, nullable) NSURLRequest *finalURLRequest;

@optional

/**
 Optional readonly property of download metrics.
 This property is left as an opaque `id` for the implementers convenience.
 */
@property (nonatomic, readonly, nullable) id downloadMetrics;

/** Optional readwrite property to support dynamic priority */
@property (nonatomic) NSOperationQueuePriority priority;

@end

/** Block for hydration completion that provides `nil` on success or an `NSError` on failure */
typedef void(^TIPImageFetchDownloadRequestHydrationCompleteBlock)(NSError * __nullable error);

/** Block for authorization completion that provides `nil` on success and an `NSError` on failure */
typedef void(^TIPImageFetchDownloadRequestAuthorizationCompleteBlock)(NSError * __nullable error);

/**
 The client for the `TIPImageFetchDownload` to call to as it executes on downloading the image.
 Calling these methods is required and they must be called in order with the exception of
 `imageFetchDownload:didCompleteWithError:`, which can be called anytime if there was an error.
 All methods MUST be called from the `[TIPImageFetchDownloadContext downloadQueue]`.
 */
@protocol TIPImageFetchDownloadClient <NSObject>

@required

/**
 Call this method from your `TIPImageFetchDownload` class when the network load is starting.
 This method MUST be called before any other `TIPImageFetchDownloadClient` method, including
 `imageFetchDownload:hydrateRequest:completion:`
 @param download The download that is starting
 */
- (void)imageFetchDownloadDidStart:(id<TIPImageFetchDownload>)download;

/**
 Call this method from your `TIPImageFetchDownload` implementation before executing on the network
 load so that `[TIPImageFetchContext hydratedRequest]` can be populated.
 This method MUST be called after `imageFetchDownloadDidStart:`.
 This method MUST be called before `imageFetchDownload:authorizeRequest:completion:`.
 @param download The download that is hydrating
 @param request The `NSURLRequest` being hydrated (MUST match
 `[TIPImageFetchDownloadContext originalRequest]`)
 @param complete The completion block to be called when hydration has finished.
 _error_ will be `nil` on success, otherwise the download can be treated as a failure and
 `imageFetchDownload:didCompleteWithError:` needs to be called at some point (passing along the
 _error_)
 */
- (void)imageFetchDownload:(id<TIPImageFetchDownload>)download
            hydrateRequest:(NSURLRequest *)request
                completion:(TIPImageFetchDownloadRequestHydrationCompleteBlock)complete;

/**
 Call this method from your `TIPImageFetchDownload` implementation before executing on the network
 load so that `[TIPImageFetchContext hydratedRequest]` can be populated.
 This method MUST be called after `imageFetchDownload:hydrateRequest:completion:`
 This method MUST be called (and permitted to complete) before other methods can be called.
 @param download The download that is authorizing
 @param request The `NSURLRequest` being authorized (SHOULD match
 `[TIPImageFetchDownloadContext hydratedRequest]`, but can be further modified)
 @param complete The completion block to be called when authorization has finished.
 _error_ will be `nil` on success, otherwise the download can be treated as a failure and
 `imageFetchDownload:didCompleteWithError:` needs to be called at some point (passing along the
 _error_)
 */
- (void)imageFetchDownload:(id<TIPImageFetchDownload>)download
          authorizeRequest:(NSURLRequest *)request
                completion:(TIPImageFetchDownloadRequestAuthorizationCompleteBlock)complete;

/**
 Call this method from your `TIPImageFetchDownload` once the `NSHTTPResponse` has been received from
 the hydrated request.
 @param download The download that received the _response_
 @param response The `NSHTTPResponse` of the hydrated request
 */
- (void)imageFetchDownload:(id<TIPImageFetchDownload>)download
     didReceiveURLResponse:(NSHTTPURLResponse *)response;

/**
 Call this method from your `TIPImageFetchDownload` whenever `NSData` is received for the download.
 @param download The download that received more `NSData`
 @param data The additional `NSData` that was received
 */
- (void)imageFetchDownload:(id<TIPImageFetchDownload>)download
            didReceiveData:(NSData *)data;

/**
 Call this method from your `TIPImageFetchDownload` if the download needs to be retried.
 This call will reset the state of this `TIPImageFetchDownloadClient` and its `TIPImageFetchDownloadContext`.
 Can call this method anytime except if `imageFetchDownload:didCompleteWithError:` has been called.
 @param download The download that will retry.
 */
- (void)imageFetchDownloadWillRetry:(id<TIPImageFetchDownload>)download;

/**
 Call this method from your `TIPImageFetchDownload` when the download has completed.
 Once this method is called, you __MUST NOT__ call any more methods on the
 `TIPImageFetchDownloadClient`.
 @param download The download that completed
 @param error an `NSError` if there was a failure, `nil` if the download succeeded
 */
- (void)imageFetchDownload:(id<TIPImageFetchDownload>)download
      didCompleteWithError:(nullable NSError *)error;

@end

/**
 The interface to the opaque context object for `TIPImageFetchDownload` to use
 */
@protocol TIPImageFetchDownloadContext <NSObject>

@required

/**
 The original `NSURLRequest` of the download.
 Do NOT load with this request.
 */
@property (nonatomic, readonly, copy) NSURLRequest *originalRequest;

/**
 The hydrated `NSURLRequest` of the download.
 Do load with this request.
 This request will be populated after the `TIPImageFetchDownloadClient` hydrates the
 _originalRequest_ for the download.
 */
@property (nonatomic, readonly, copy, nullable) NSURLRequest *hydratedRequest;

/**
 The _Authorization_ for the download.
 This value will be populated after the `TIPImageFetchDownloadClient` authorizes the _hydratedRequest_.
 @note The value is not populated onto the _hydratedRequest_.
 Apply the value to be the authorization of your request in whatever mechanism best serves your
 loading system.
 */
@property (nonatomic, readonly, copy, nullable) NSString *authorization;

/**
 The client instance to call from the `TIPImageFetchDownload` implementation as the download loads.
 */
@property (nonatomic, readonly) id<TIPImageFetchDownloadClient> client;

/**
 The GCD queue from which all _client_ methods MUST be called from.
 Can perform non-main thread work on this queue too.
 */
@property (nonatomic, readonly) dispatch_queue_t downloadQueue;

@end

/**
 Protocol for `TIPImageFetchDownload` provider.  Simply vends `TIPImageFetchDownload` instances.
 If no custom `TIPImageFetchDownloadProvider` is set on the `TIPGlobalConfiguration`, the default
 implementation of using `NSURLSession` based `TIPImageFetchDownload` instances will be used.
 */
@protocol TIPImageFetchDownloadProvider <NSObject>

@required

/**
 Construct the download.  This will be called by __TIP__ and shouldn't be called externally.
 @param context The `TIPImageFetchDownloadContext` to use for the duration of the download
 @note Since the _context_ can be discarded, it is wise to retain any relevant info from the context
 that could be needed beyond the lifespan of the _context_ instance.
 A good example of this would be the `downloadQueue` which may be desirable to use after the
 _context_ is already discarded.
 */
- (id<TIPImageFetchDownload>)imageFetchDownloadWithContext:(id<TIPImageFetchDownloadContext>)context;

@end

/**
 Extended protocol for `TIPImageFetchDownloadProvider` that offers support for stubbing downloads.
 Download stubbing is just a term to indicate that the reponse given for a request is canned and the
 network is not actually being used to retrieve the response.
 Useful for unit testing __TwitterImagePipeline__
 */
@protocol TIPImageFetchDownloadProviderWithStubbingSupport <TIPImageFetchDownloadProvider>

@required

/** is download stubbing of requests currently enabled */
@property (nonatomic, readwrite) BOOL downloadStubbingEnabled;

/**
 Add a stub
 @param requestURL the `NSURL` to match as the stubbed request
 @param responseData the `NSData` representing the data (image data) of the response,
 can provide `nil` for error responses like a 404
 @param MIMEType the MIME type that the response data will be.  Used for setting the _Content-Type_
 of the response.
 @param shouldSupportResume a suggestion that the stubbed response should be able to support being a
 resumed download with `Range` provided in the request's header fields.  Very useful for testing
 resumed downloads if the implementation of `TIPImageFetchDownloadWithStubbingSupport` can support
 it.
 @param suggestedBitrate a suggested bitrate for the response to come down as.  Very useful for
 testing simulated slow networks if the implementation of `TIPImageFetchDownloadWithStubbingSupport`
 can support it.  `0` == unlimited.
 */
- (void)addDownloadStubForRequestURL:(NSURL *)requestURL
                        responseData:(nullable NSData *)responseData
                    responseMIMEType:(nullable NSString *)MIMEType
               shouldSupportResuming:(BOOL)shouldSupportResume
                    suggestedBitrate:(uint64_t)suggestedBitrate;

/**
 Remove a stub
 @param requestURL the `NSURL` to stop stubbing
 */
- (void)removeDownloadStubForRequestURL:(NSURL *)requestURL;

/**
 Remove all pre-existing stubs
 */
- (void)removeAllDownloadStubs;

@end

/**
 Convenience category on `NSHTTPURLResponse` to support stubbing w/ concrete
 `TIPImageFetchDownloadWithStubbingSupport` implementations
 */
@interface NSHTTPURLResponse (TIPStubbingSupport)
/**
 Convenience method for constructing an `NSHTTPURLResponse` for use in download stubbing.
 @param requestURL the `NSURL` of the request for the returned response
 @param dataLength the length (in bytes) of the response body (0 will yield a 404 status code for
 the response)
 @param MIMEType the MIME type for the response, can be `nil`
 @return an `NSHTTPURLResponse` that is populated with values representative of an image download
 */
+ (instancetype)tip_responseWithRequestURL:(NSURL *)requestURL
                                dataLength:(NSUInteger)dataLength
                          responseMIMEType:(nullable NSString *)MIMEType;
@end

NS_ASSUME_NONNULL_END
