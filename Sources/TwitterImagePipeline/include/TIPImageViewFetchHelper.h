//
//  TIPImageViewFetchHelper.h
//  TwitterImagePipeline
//
//  Created on 4/18/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TIPImageFetchDelegate.h>
#import <TIPImageUtils.h>
#import <UIKit/UIView.h>

@class TIPImageFetchMetrics;
@class TIPImagePipeline;
@protocol TIPImageFetchable;
@protocol TIPImageFetchRequest;
@protocol TIPImageViewFetchHelperDelegate;
@protocol TIPImageViewFetchHelperDataSource;

NS_ASSUME_NONNULL_BEGIN

/** enum of disappearnace behaviors */
typedef NS_ENUM(NSInteger, TIPImageViewDisappearanceBehavior)
{
    /** do nothing on disappear */
    TIPImageViewDisappearanceBehaviorNone = 0,
    /** cancel the fetch on disappear */
    TIPImageViewDisappearanceBehaviorCancelImageFetch,
    /** lower priority of fetch on disappear */
    TIPImageViewDisappearanceBehaviorLowerImageFetchPriority,
    /** unload the image on disappear (and cancel any outstanding fetch) */
    TIPImageViewDisappearanceBehaviorUnload,
    /** replace the image on disappear with a placeholder */
    TIPImageViewDisappearanceBehaviorReplaceWithPlaceholder
};

/**
 Helper object for loading a fetch request on behalf of a target `UIView` adopting `TIPImageFetchable`.
 Offers lots of dynamic features via subclassing and/or use of the `delegate` and/or `dataSource`.
 `TIPImageViewFetchHelper` has built in support for an information overlay too that is helpful
 for debugging (see `TIPImageViewHelper(Debugging)`)
 */
@interface TIPImageViewFetchHelper : NSObject

#pragma mark Properties / State

/** behavior on "disappear", default == `TIPImageViewDisappearanceBehaviorUnload` */
@property (nonatomic) TIPImageViewDisappearanceBehavior disappearanceBehavior;
/** should treat application backgrounding as the view disappearing?, default == `YES` */
@property (nonatomic) BOOL shouldTreatApplicationBackgroundAsViewDisappearance;
/** associated `UIView` that conforms to `TIPImageFetchable` */
@property (nonatomic, nullable, weak) UIView<TIPImageFetchable> *fetchView;
/** request to fetch */
@property (nonatomic, readonly, nullable) id<TIPImageFetchRequest> fetchRequest;

/** is the helper loading the fetch */
@property (nonatomic, readonly, getter=isLoading) BOOL loading;
/** progress of the fetch, `0.f` to `1.f` */
@property (nonatomic, readonly) float fetchProgress;
/** error of fetch, if encountered */
@property (nonatomic, readonly, nullable) NSError *fetchError;
/** metrics of fetch */
@property (nonatomic, readonly, nullable) TIPImageFetchMetrics *fetchMetrics;
/** dimensions of the fetched image */
@property (nonatomic, readonly) CGSize fetchResultDimensions;
/** source of fetch */
@property (nonatomic, readonly) TIPImageLoadSource fetchSource;
/** is the fetched image treated as a placeholder? */
@property (nonatomic, readonly) BOOL fetchedImageTreatedAsPlaceholder;
/** is the fetched image a preview? */
@property (nonatomic, readonly) BOOL fetchedImageIsPreview;
/** is the fetched image a preview that's being treated as final? */
@property (nonatomic, readonly) BOOL fetchedImageIsScaledPreviewAsFinal;
/** is the fetched image a progressive scan/frame? */
@property (nonatomic, readonly) BOOL fetchedImageIsProgressiveFrame;
/** is the fetched image the full load? */
@property (nonatomic, readonly) BOOL fetchedImageIsFullLoad;
/** is the fetched image loaded at all? */
@property (nonatomic, readonly) BOOL didLoadAny;
/** the fetched image, not necessarily the final image URL */
@property (nonatomic, readonly, nullable) NSURL *fetchedImageURL;

#pragma mark Dynamic Behavior Support

/** the delegate for this fetch helper */
@property (nonatomic, weak, nullable) id<TIPImageViewFetchHelperDelegate> delegate;
/** the data source for this fetch helper */
@property (nonatomic, weak, nullable) id<TIPImageViewFetchHelperDataSource> dataSource;

#pragma mark Initializer

/** initializer (convenience) */
- (instancetype)init;
/** initializer with delegate & data source (designated) */
- (instancetype)initWithDelegate:(nullable id<TIPImageViewFetchHelperDelegate>)delegate
                      dataSource:(nullable id<TIPImageViewFetchHelperDataSource>)dataSource  NS_DESIGNATED_INITIALIZER;

#pragma mark Primary Actions

/** reload the fetch */
- (void)reload;
/** cancel in flight fetch */
- (void)cancelFetchRequest;
/** clear the fetched image */
- (void)clearImage;

#pragma mark Override Actions

/** set the image, as if it was loaded from a fetch */
- (void)setImageAsIfLoaded:(UIImage *)image;
/** set the image container, as if it was loaded from a fetch */
- (void)setImageContainerAsIfLoaded:(TIPImageContainer *)imageContainer;
/** mark the image as loaded from a fetch */
- (void)markAsIfLoaded;
/** set the image, as if it was a placeholder image */
- (void)setImageAsIfPlaceholder:(UIImage *)image;
/** set the image container, as if it was a placeholder image */
- (void)setImageContainerAsIfPlaceholder:(TIPImageContainer *)imageContainer;
/** mark the image as a placeholder */
- (void)markAsIfPlaceholder;

#pragma mark Triggers - Do NOT override

/** call when view will disappear */
- (void)triggerViewWillDisappear NS_REQUIRES_SUPER;
/** call when view did disappear */
- (void)triggerViewDidDisappear NS_REQUIRES_SUPER;
/** call when view will appear */
- (void)triggerViewWillAppear NS_REQUIRES_SUPER;
/** call when view did appear */
- (void)triggerViewDidAppear NS_REQUIRES_SUPER;
/** call when view is laying out subviews */
- (void)triggerViewLayingOutSubviews NS_REQUIRES_SUPER;

/** call when view will move to window _newWindow_ (can be `nil` when removed from all windows) */
- (void)triggerViewWillMoveToWindow:(nullable UIWindow *)newWindow NS_REQUIRES_SUPER;
/** call when view did move to window (or `nil`) */
- (void)triggerViewDidMoveToWindow NS_REQUIRES_SUPER;

/** call when application did enter the background */
- (void)triggerApplicationDidEnterBackground;
/** call when application will enter the foreground */
- (void)triggerApplicationWillEnterForeground;


#pragma mark Transition a UIView between fetch helpers

/** call to transition view from one fetch helper to a new fetch helper */
+ (void)transitionView:(UIView<TIPImageFetchable> *)fetchableView
       fromFetchHelper:(nullable TIPImageViewFetchHelper *)fromHelper
         toFetchHelper:(nullable TIPImageViewFetchHelper *)toHelper;

#pragma mark Global Methods

/**
 Call this method to trigger all `TIPImageFetchHelpers` that failed
 to load an image to retry.
 For example, when the network conditions change, calling this method
 could yield a successful load with the network returning.
 */
+ (void)notifyAllFetchHelpersToRetryFailedLoads;

#pragma mark Deprecated

/** Deprecated */
@property (nonatomic) TIPImageViewDisappearanceBehavior fetchDisappearanceBehavior __attribute__((deprecated("`fetchDisappearanceBehavior` is deprecated.  Use `disappearanceBehavior` isntead.  This API will be removed in the future.")));

@end

//! Notification that the debug info visibility for `TIPImageView` changed
FOUNDATION_EXTERN NSString * const TIPImageViewDidUpdateDebugInfoVisibilityNotification;
//! User info key of visibility, `NSNumber` wrapping a `BOOL`
FOUNDATION_EXTERN NSString * const TIPImageViewDidUpdateDebugInfoVisibilityNotificationKeyVisible;

/** Category for debugging features on `TIPImageView` */
@interface TIPImageViewFetchHelper (Debugging)

/** make debug info visible or not */
@property (class, nonatomic, getter=isDebugInfoVisible) BOOL debugInfoVisible;

/** color for image highlight when debug info visible */
@property (nonatomic, nullable) UIColor *debugImageHighlightColor;
/** color for text of debug info when visible */
@property (nonatomic, nullable) UIColor *debugInfoTextColor;

/**
 Returns a mutable array of debug info strings for debug info view to display.
 Subclasses can override and modify returned array.
 */
- (NSMutableArray<NSString *> *)debugInfoStrings NS_REQUIRES_SUPER;
/** trigger that the debug info needs updating */
- (void)setDebugInfoNeedsUpdate;

@end

/**
 Data source protocol for `TIPImageViewFetchHelper`
 Selection order:
    1. TIPImageContainer
    2. UIImage
    3. TIPImageFetchRequest
    4. NSURL
 */
@protocol TIPImageViewFetchHelperDataSource <NSObject>

#pragma mark Image Load Source
@optional

// Chosen in order

/** load from a static `TIPImageContainer` */
- (nullable TIPImageContainer *)tip_imageContainerForFetchHelper:(TIPImageViewFetchHelper *)helper;

/** load from a static `UIImage` */
- (nullable UIImage *)tip_imageForFetchHelper:(TIPImageViewFetchHelper *)helper;

/** load from a specific `NSURL` */
- (nullable NSURL *)tip_imageURLForFetchHelper:(TIPImageViewFetchHelper *)helper;

/** load from a `TIPImageFetchRequest` */
- (nullable id<TIPImageFetchRequest>)tip_imageFetchRequestForFetchHelper:(TIPImageViewFetchHelper *)helper;

// Pipeline

/**
 always called after a `TIPImageFetchRequest` or `NSURL` is loaded.
 Failing to implement this method or returning `nil` will end the fetch.
 */
- (nullable TIPImagePipeline *)tip_imagePipelineForFetchHelper:(TIPImageViewFetchHelper *)helper;

#pragma mark Image Load Behavior
@optional

/** can inspect the fetchImageView and the fetchRequest to make a decision.  Default == `NO` */
- (BOOL)tip_shouldRefetchOnTargetSizingChangeForFetchHelper:(TIPImageViewFetchHelper *)helper;

/** the priority for the fetch, default == `NSOperationQueuePriorityNormal` */
- (NSOperationQueuePriority)tip_fetchOperationPriorityForFetchHelper:(TIPImageViewFetchHelper *)helper;

#pragma mark Debug
@optional

/** Can extend the debug info of a debug info overlay */
- (nullable NSArray<NSString *> *)tip_additionalDebugInfoStringsForFetchHelper:(TIPImageViewFetchHelper *)helper;

@end

/** Delegate protocol for `TIPImageViewFetchHelper` */
@protocol TIPImageViewFetchHelperDelegate <NSObject>

#pragma mark Deciders
@optional

/** should update image with preview image?  default == `NO` */
- (BOOL)tip_fetchHelper:(TIPImageViewFetchHelper *)helper
        shouldUpdateImageWithPreviewImageResult:(id<TIPImageFetchResult>)previewImageResult;
/**
 should continue to load after fetching preview?
 Default behavior:
 - If preview result is a placeholder, `YES`.
 - If fetching request is placeholder, `NO`.
 - If preview is larger or equal to target sizing, `NO`.
 - Otherwise, `YES`.
 */
- (BOOL)tip_fetchHelper:(TIPImageViewFetchHelper *)helper
        shouldContinueLoadingAfterFetchingPreviewImageResult:(id<TIPImageFetchResult>)previewImageResult;
/**
 should load progressively?  default == `NO`
 Called via a background thread synchronously.
 */
- (BOOL)tip_fetchHelper:(TIPImageViewFetchHelper *)helper
        shouldLoadProgressivelyWithIdentifier:(NSString *)identifier
        URL:(NSURL *)URL
        imageType:(NSString *)imageType
        originalDimensions:(CGSize)originalDimensions;
/**
 should reload after a different fetch completed?
 Has automatic/default behavior, call super to utilize auto behavior
 */
- (BOOL)tip_fetchHelper:(TIPImageViewFetchHelper *)helper
        shouldReloadAfterDifferentFetchCompletedWithImageContainer:(TIPImageContainer *)imageContainer
        dimensions:(CGSize)dimensions
        identifier:(NSString *)identifier
        URL:(NSURL *)URL
        treatedAsPlaceholder:(BOOL)placeholder
        manuallyStored:(BOOL)manuallyStored;

#pragma mark Events
@optional

/** fetch did start loading */
- (void)tip_fetchHelperDidStartLoading:(TIPImageViewFetchHelper *)helper;
/** fetch did update progress */
- (void)tip_fetchHelper:(TIPImageViewFetchHelper *)helper didUpdateProgress:(float)progress;
/** fetch did update displayed image with a `TIPImageContainer` */
- (void)tip_fetchHelper:(TIPImageViewFetchHelper *)helper didUpdateDisplayedImageContainer:(TIPImageContainer *)imageContainer fromSourceDimensions:(CGSize)size isFinal:(BOOL)isFinal;
/** fetch did load final image */
- (void)tip_fetchHelper:(TIPImageViewFetchHelper *)helper didLoadFinalImageFromSource:(TIPImageLoadSource)source;
/** fetch did fail */
- (void)tip_fetchHelper:(TIPImageViewFetchHelper *)helper didFailToLoadFinalImage:(NSError *)error;
/** fetch did reset */
- (void)tip_fetchHelperDidReset:(TIPImageViewFetchHelper *)helper;
/** fetch did start loading from the network */
- (void)tip_fetchHelperDidStartLoadingFromNetwork:(TIPImageViewFetchHelper *)helper;


#pragma mark Deprecated

/**
 should reload after a different fetch completed?
 Has automatic/default behavior, call super to utilize auto behavior
 @warning deprecated callback, implement `tip_fetchHelper:shouldReloadAfterDifferentFetchCompletedWithImage:dimensions:identifier:URL:treatedAsPlaceholder:manuallyStored:` instead
 */
- (BOOL)tip_fetchHelper:(TIPImageViewFetchHelper *)helper
        shouldReloadAfterDifferentFetchCompletedWithImage:(UIImage *)image
        dimensions:(CGSize)dimensions
        identifier:(NSString *)identifier
        URL:(NSURL *)URL
        treatedAsPlaceholder:(BOOL)placeholder
         manuallyStored:(BOOL)manuallyStored __attribute__((deprecated("implement `tip_fetchHelper:shouldReloadAfterDifferentFetchCompletedWithImage:dimensions:identifier:URL:treatedAsPlaceholder:manuallyStored:` instead")));

/**
 fetch did update displayed image
 @warning deprecated callback, implement `tip_fetchHelper:didUpdateDisplayedImageContainer:fromSourceDimensions:isFinal:` instead
 */
- (void)tip_fetchHelper:(TIPImageViewFetchHelper *)helper
didUpdateDisplayedImage:(UIImage *)image
   fromSourceDimensions:(CGSize)size
                isFinal:(BOOL)isFinal __attribute__((deprecated("implement `tip_fetchHelper:didUpdateDisplayedImageContainer:fromSourceDimensions:isFinal:` instead")));

@end

NS_ASSUME_NONNULL_END
