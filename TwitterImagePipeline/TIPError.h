//
//  TIPError.h
//  TwitterImagePipeline
//
//  Created on 7/14/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Errors

#pragma mark Error Domains

///! The error domain for image fetching operations
FOUNDATION_EXTERN NSString * const TIPImageFetchErrorDomain;
///! The error domain for image storing operations
FOUNDATION_EXTERN NSString * const TIPImageStoreErrorDomain;
///! The error domain for generic errors
FOUNDATION_EXTERN NSString * const TIPErrorDomain;

#pragma mark Error User Info Keys

/**
 The `userInfo` key for the _HTTP Status Code_ when
 `TIPImageFetchErrorCodeHTTPTransactionError` is the error code
 */
FOUNDATION_EXTERN NSString * const TIPErrorUserInfoHTTPStatusCodeKey;

#pragma mark Error Codes

/**
 The error code related to fetching an image.  See also `TIPImageFetchErrorDomain`.
 */
typedef NS_ENUM(NSInteger, TIPImageFetchErrorCode) {

    // Fetch Errors

    /** Unknown */
    TIPImageFetchErrorCodeUnknown = 0,
    /** Invalid Fetch Request.  Often from a `nil` `imageURL` or a zero length `imageIdentifier`. */
    TIPImageFetchErrorCodeInvalidRequest,
    /**
     There was an _HTTP_ transaction issue (based on the _HTTP Status Code_).
     `TIPErrorUserInfoHTTPStatusCodeKey` will be populated with the _HTTP Status Code_ as an
     `NSInteger` (wrapped by an `NSNumber`).
     */
    TIPImageFetchErrorCodeHTTPTransactionError,
    /** The image fetched could not be decoded */
    TIPImageFetchErrorCodeCouldNotDecodeImage,
    /**
     The URL or HTTP Method was mutated by the provided hydration block, which is not permitted with
     a `TIPImageFetchRequest`
     */
    TIPImageFetchErrorCodeIllegalModificationByHydrationBlock,
    /** The image could not be downloaded */
    TIPImageFetchErrorCouldNotDownloadImage,
    /**
     The image could not be loaded from any of the specified loading sources, see
     `[TIPImageFetchRequest loadingSources]`
     */
    TIPImageFetchErrorCouldNotLoadImage,

    // TIPImageFetchDownload errors (starting from 1001)

    /**
     The image fetch download redundantly started.
     Custom `TIPImageFetchDownload` implementations are to call
     `[TIPImageFetchDownloadClient imageFetchDownloadDidStart:]` only once.
     */
    TIPImageFetchErrorCodeDownloadEncounteredToStartMoreThanOnce = 1001,
    /**
     The image fetch download redundantly attempted to hydrate the request.
     Custom `TIPImageFetchDownload` implementations are to call
     `[TIPImageFetchDownloadClient imageFetchDownload:hydrateRequest:completion:]` only once.
     */
    TIPImageFetchErrorCodeDownloadAttemptedToHydrateRequestMoreThanOnce,
    /**
     The image fetch download redundantly received a response.
     Custom `TIPImageFetchDownload` implementations are to call
     `[TIPImageFetchDownloadClient imageFetchDownload:didReceiveURLResponse:]` only once.
     */
    TIPImageFetchErrorCodeDownloadReceivedResponseMoreThanOnce,
    /**
     The image fetch download never indicated that it was started.
     Custom `TIPImageFetchDownload` implementations are to call
     `[TIPImageFetchDownloadClient imageFetchDownloadDidStart:]` before any other client method.
     */
    TIPImageFetchErrorCodeDownloadNeverStarted,
    /**
     The image fetch download never attempted to hydrate the request.
     Custom `TIPImageFetchDownload` implementations are to call
     `[TIPImageFetchDownloadClient imageFetchDownload:hydrateRequest:completion:]` once after
     `[TIPImageFetchDownloadClient imageFetchDownloadDidStart:]` and before any other client method.
     */
    TIPImageFetchErrorCodeDownloadNeverAttemptedToHydrateRequest,
    /**
     The image fetch download never received a response.
     Custom `TIPImageFetchDownload` implementations are to call
     `[TIPImageFetchDownloadClient imageFetchDownload:didReceiveURLResponse:]` before calling
     `[TIPImageFetchDownloadClient imageFetchDownload:didReceiveData:]` or a non-error call to
     `[TIPImageFetchDownloadClient imageFetchDownload:didCompleteWithError:]`
     */
    TIPImageFetchErrorCodeDownloadNeverReceivedResponse,

    // Cancellation codes (negative)

    /** The fetch was cancelled */
    TIPImageFetchErrorCodeCancelled = -1,
    /** The fetch was cancelled by the delegate when the preview was loaded */
    TIPImageFetchErrorCodeCancelledAfterLoadingPreview = -2,
};

/**
 The error code related to storing an image.  See also `TIPImageStoreErrorDomain`.
 */
typedef NS_ENUM(NSInteger, TIPImageStoreErrorCode) {
    /** Unknown */
    TIPImageStoreErrorCodeUnknown = 0,
    /**
     The image was not provided via `image`, `imageData` nor `imageFilePath` in the
     `TIPImageStoreRequest`
     */
    TIPImageStoreErrorCodeImageNotProvided,
    /** `imageURL` was not provided in the `TIPImageStoreRequest` */
    TIPImageStoreErrorCodeImageURLNotProvided,
    /** There is no underlying cache to store too. */
    TIPImageStoreErrorCodeNoCacheForStoring,
    /** The request's image info could not be stored as an image. */
    TIPImageStoreErrorCodeStorageFailed,
};

/**
 TIP error codes that are not related to fetching or storing
 */
typedef NS_ENUM(NSInteger, TIPErrorCode) {
    /** unknown error */
    TIPErrorCodeUnknown = 0,
    /** attempted to use GPU while app is in background */
    TIPErrorCodeCannotUseGPUInBackground,
    /** a `CIImage` was expected, but there was none */
    TIPErrorCodeMissingCIImage,
    /** a `CGImageRef` was expected, but there was none */
    TIPErrorCodeMissingCGImage,
    /** failed creating a `CGImageDestinationRef` */
    TIPErrorCodeFailedToInitializeImageDestination,
    /** failed finalizing a `CGImageDestinationRef` */
    TIPErrorCodeFailedToFinalizeImageDestination,
    /** target encoding is not supported (likely the image type can't be encoded) */
    TIPErrorCodeEncodingUnsupported,
};

#pragma mark - Problems

/**
 Problems are when non-fatal errors are encountered within the __TIP__ framework.
 Most of the time they can be ignored, but it can be useful to observe problems
 to help diagnose issues.
 */

/**
 Protocol for observing problems encountered with __TIP__
*/
@protocol TIPProblemObserver <NSObject>

@optional
/**
 Callback when a problem was encountered
 @param problemName the name of the problem
 @param userInfo a dictionary of user info related to the problem
 */
- (void)tip_problemWasEncountered:(NSString *)problemName
                         userInfo:(NSDictionary<NSString *, id> *)userInfo;

/**
 Callback when a CGContext is accessed
 @param duration the access duration of CGContext
 @param serially `YES` if the CGContext access was serialized
 @param mainThread `YES` if the CGContext access was on the main thread
 */
- (void)tip_CGContextAccessed:(NSTimeInterval)duration
                     serially:(BOOL)serially
               fromMainThread:(BOOL)mainThread;

@end

#pragma mark Problem Names

//! Problem when disk cache cannot generate a file name for an image entry
FOUNDATION_EXTERN NSString * const TIPProblemDiskCacheUpdateImageEntryCouldNotGenerateFileName;
//! Problem when an image fails to scale
FOUNDATION_EXTERN NSString * const TIPProblemImageFailedToScale;
//! Problem when a `TIPImageContainer` has a `nil` _image_
FOUNDATION_EXTERN NSString * const TIPProblemImageContainerHasNilImage;
//! Problem when a `TIPImageFetchRequests` provides invalid `targetDimensions`
FOUNDATION_EXTERN NSString * const TIPProblemImageFetchHasInvalidTargetDimensions;
//! Problem that a downloaded image has GPS info
FOUNDATION_EXTERN NSString * const TIPProblemImageDownloadedHasGPSInfo;
//! Problem decoding downloaded image
FOUNDATION_EXTERN NSString * const TIPProblemImageDownloadedCouldNotBeDecoded;
//! Problem when attempting to store an image to disk cache due to size limit
FOUNDATION_EXTERN NSString * const TIPProblemImageTooLargeToStoreInDiskCache;

#pragma mark Problem Info Keys

//! Image identifier, `NSString`
FOUNDATION_EXTERN NSString * const TIPProblemInfoKeyImageIdentifier;
//! Image identifier (coerced to be safe), `NSString`
FOUNDATION_EXTERN NSString * const TIPProblemInfoKeySafeImageIdentifier;
//! Image URL, `NSURL`
FOUNDATION_EXTERN NSString * const TIPProblemInfoKeyImageURL;

//! Target dimensions, `NSValue` wrapping `CGSize`
FOUNDATION_EXTERN NSString * const TIPProblemInfoKeyTargetDimensions;
//! Target content mode, `NSNumber` wrapping `UIViewContentMode`
FOUNDATION_EXTERN NSString * const TIPProblemInfoKeyTargetContentMode;
//! Computed scaled dimensions, `NSValue` wrapping `CGSize`
FOUNDATION_EXTERN NSString * const TIPProblemInfoKeyScaledDimensions;
//! The dimensions of the image, `NSValue` wrapping `CGSize`
FOUNDATION_EXTERN NSString * const TIPProblemInfoKeyImageDimensions;
//! The image is animated, `NSNumber` wrapping `BOOL`
FOUNDATION_EXTERN NSString * const TIPProblemInfoKeyImageIsAnimated;

//! Fetch requeset, `id<TIPImageFetchRequest>`
FOUNDATION_EXTERN NSString * const TIPProblemInfoKeyFetchRequest;

NS_ASSUME_NONNULL_END
