//
//  TIPImageFetchDelegate.h
//  TwitterImagePipeline
//
//  Created on 3/16/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <TIPDefinitions.h>
#import <TIPImageUtils.h>
#import <UIKit/UIImage.h>
#import <UIKit/UIView.h>

@class TIPImageFetchOperation;
@class TIPImageContainer;
@protocol TIPImageFetchResult;

/**
 Behavior for fetch to make after a preview image has been fetched
 */
typedef NS_ENUM(NSInteger, TIPImageFetchPreviewLoadedBehavior) {
    /** Keep loading the final image */
    TIPImageFetchPreviewLoadedBehaviorContinueLoading,
    /**
     Stop loading.
     The operation failure error code will be `TIPImageFetchErrorCodeCancelledAfterLoadingPreview`
     */
    TIPImageFetchPreviewLoadedBehaviorStopLoading,
};

///! Callback for when a preview image is loaded
typedef void(^TIPImageFetchDidLoadPreviewCallback)(TIPImageFetchPreviewLoadedBehavior behavior);

/**
 The delegate for all `TIPImageFetchOperation` callbacks
 */
@protocol TIPImageFetchDelegate <NSObject>

@optional

/**
 Called if a dirty render cache preview was encountered _before_ the fetch even starts.
 Use this to pre-populate the target view with the given result if desired.
 This is the only callback that can happen prior to `tip_imageFetchOperationDidStart:`

 @param op The image fetch operation
 @param result The preview image result that is dirty
 */
- (void)tip_imageFetchOperation:(nonnull TIPImageFetchOperation *)op
       didLoadDirtyPreviewImage:(nonnull id<TIPImageFetchResult>)result;

/**
 Called when the fetch starts
 @param op The image fetch operation
 */
- (void)tip_imageFetchOperationDidStart:(nonnull TIPImageFetchOperation *)op;

/**
 Called as the fetch starts loading from each source `TIPImageLoadSource`.
 @param op The image fetch operation
 @param source the `TIPImageLoadSource` that an attempt at loading will be made on
 @note Does not get called if image was synchronously loaded from the rendered cache.
 @note Only one of `TIPImageLoadSourceNetwork` and `TIPImageLoadSourceNetworkResumed` will be
 provided to the callback via _source_.  `TIPImageLoadSourceNetworkResumed` does not guarantee the
 image will be resumed, and it would be possible for the image to have to fully load and complete
 with `TIPImageLoadSourceNetwork`.
 */
- (void)tip_imageFetchOperation:(nonnull TIPImageFetchOperation *)op
    willAttemptToLoadFromSource:(TIPImageLoadSource)source;

/**
 Called when a preview image is loaded.

 Provide `TIPImageFetchPreviewLoadedBehaviorContinueLoading` to keep loading the final image or
 `TIPImageFetchPreviewLoadedBehaviorStopLoading` to stop the fetch operation (such as when the
 preview is of high enough fidelity).

 @param op The image fetch operation
 @param previewResult The preview `TIPImageFetchResult`
 @param completion The callback to call (async or sync) with the behavior after the preview was
 fetched.

 `previewResult.imageContainer` will be resized if _targetDimensions_ and _targetContentMode_ are
 provided by the `TIPImageRequest`
 `previewResult.imageSource` will be either from `TIPImageLoadSourceMemoryCache` or
 `TIPImageLoadSourceDiskCache`
 */
- (void)tip_imageFetchOperation:(nonnull TIPImageFetchOperation *)op
            didLoadPreviewImage:(nonnull id<TIPImageFetchResult>)previewResult
                     completion:(nonnull TIPImageFetchDidLoadPreviewCallback)completion;

/**
 Implement this method to support progressive loading.

 @param op The image fetch operation
 @param identifier The image's identifier
 @param URL The URL being loaded
 @param imageType The type of the image
 @param originalDimensions The original dimensions

 @return `YES` to support progressive loading, `NO` to not support it.
 Default is `NO`.

 @note This method is called synchronously from a background thread.
 */
- (BOOL)tip_imageFetchOperation:(nonnull TIPImageFetchOperation *)op
        shouldLoadProgressivelyWithIdentifier:(nonnull NSString *)identifier
        URL:(nonnull NSURL *)URL
        imageType:(nonnull NSString *)imageType
        originalDimensions:(CGSize)originalDimensions;

/**
 Called when a progressive image was loaded for images that support it.
 (Currently, just Progressive JPEG).

 @param op The image fetch operation
 @param progressiveResult The progressive image's `TIPImageFetchResult`
 @param progress total progress

 `progressiveResult.source` the source of the image (likely one of `TIPImageLoadSourceNetwork`,
 `TIPImageLoadSourceNetworkResumed` or `TIPImageLoadSourceDiskCache`)
 */
- (void)tip_imageFetchOperation:(nonnull TIPImageFetchOperation *)op
      didUpdateProgressiveImage:(nonnull id<TIPImageFetchResult>)progressiveResult
                       progress:(float)progress;

/**
 Called when an animated image has loaded enough to display its first frame.
 (Currently, just GIFs).

 @param op The image fetch operation
 @param progressiveResult The animated image's first frame result as `TIPImageFetchResult`
 @param progress The total progress

 `progressiveResult.source` the source of the image (likely one of `TIPImageLoadSourceNetwork`,
 `TIPImageLoadSourceNetworkResumed` or `TIPImageLoadSourceDiskCache`)
 */
- (void)tip_imageFetchOperation:(nonnull TIPImageFetchOperation *)op
 didLoadFirstAnimatedImageFrame:(nonnull id<TIPImageFetchResult>)progressiveResult
                       progress:(float)progress;

/**
 Called when progress has occurred.

 @param op The image fetch operation
 @param progress total progress
 */
- (void)tip_imageFetchOperation:(nonnull TIPImageFetchOperation *)op
              didUpdateProgress:(float)progress;

/**
 Called when the final image was loaded, thus completing the operation

 @param op The image fetch operation
 @param finalResult The final fetched result as a `TIPImageFetchResult`

 `finalResult.imageContainer` will be resized if _targetDimensions_ and _targetContentMode_ are
 provided by the `TIPImageRequest`
 */
- (void)tip_imageFetchOperation:(nonnull TIPImageFetchOperation *)op
              didLoadFinalImage:(nonnull id<TIPImageFetchResult>)finalResult;

/**
 Called when the final image was unable to load

 @param op The image fetch operation
 @param error The error that was encountered
 */
- (void)tip_imageFetchOperation:(nonnull TIPImageFetchOperation *)op
        didFailToLoadFinalImage:(nonnull NSError *)error;

@end
