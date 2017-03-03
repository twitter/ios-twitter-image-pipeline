//
//  TIPImageViewFetchHelper.h
//  TwitterImagePipeline
//
//  Created on 4/18/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <UIKit/UIImageView.h>

#import "TIPImageFetchDelegate.h"
#import "TIPImageUtils.h"

@class TIPImageFetchMetrics;
@protocol TIPImageFetchRequest;
@protocol TIPImageViewFetchHelperDelegate;
@protocol TIPImageViewFetchHelperDataSource;

/** enum of disappearnace behaviors */
typedef NS_ENUM(NSInteger, TIPImageViewDisappearanceBehavior)
{
    /** do nothing on disappear */
    TIPImageViewDisappearanceBehaviorNone = 0,
    /** cancel the fetch on disappear */
    TIPImageViewDisappearanceBehaviorCancelImageFetch,
    /** lower priority of fetch on disappear */
    TIPImageViewDisappearanceBehaviorLowerImageFetchPriority,
};

/**
 Helper object for loading a fetch request on behalf of a target `UIImageView`.
 Offers lots of dynamic features via subclassing and/or use of the `delegate` and/or `dataSource`.
 `TIPImageViewFetchHelper` has built in support for an information overlay too that is helpful
 for debugging (see `TIPImageViewHelper(Debugging)`)
 */
@interface TIPImageViewFetchHelper : NSObject

#pragma mark Properties / State

/** behavior on "disappear", default == `CancelImageFetch` */
@property (nonatomic) TIPImageViewDisappearanceBehavior fetchDisappearanceBehavior;
/** associated `UIImageView` */
@property (nonatomic, nullable, weak) UIImageView *fetchImageView;
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
- (nonnull instancetype)init;
/** initializer with delegate & data source (designated) */
- (nonnull instancetype)initWithDelegate:(nullable id<TIPImageViewFetchHelperDelegate>)delegate dataSource:(nullable id<TIPImageViewFetchHelperDataSource>)dataSource  NS_DESIGNATED_INITIALIZER;

#pragma mark Primary Actions

/** reload the fetch */
- (void)reload;
/** cancel in flight fetch */
- (void)cancelFetchRequest;
/** clear the fetched image */
- (void)clearImage;

#pragma mark Override Actions

/** set the image, as if it was loaded from a fetch */
- (void)setImageAsIfLoaded:(nonnull UIImage *)image;
/** mark the image as loaded from a fetch */
- (void)markAsIfLoaded;

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

#pragma mark Helper Triggers - Do NOT override

/** call when view hidden changes */
- (void)setViewHidden:(BOOL)hidden;
/** call when view will move to window _newWindow_ (can be `nil` when removed from all windows) */
- (void)viewWillMoveToWindow:(nullable UIWindow *)newWindow;
/** call when view did move to window (or `nil`) */
- (void)viewDidMoveToWindow;

/** call to transition view from one fetch helper to a new fetch helper */
+ (void)transitionView:(nonnull UIImageView *)imageView fromFetchHelper:(nullable TIPImageViewFetchHelper *)fromHelper toFetchHelper:(nullable TIPImageViewFetchHelper *)toHelper;

#pragma mark Decider Methods - Override if desired

/** should update image with preview image?  default == `NO` */
- (BOOL)shouldUpdateImageWithPreviewImageResult:(nonnull id<TIPImageFetchResult>)previewImageResult;
/**
 should continue to load after fetching preview?
 Default behavior:
    - If preview result is a placeholder, `YES`.
    - If fetching request is placeholder, `NO`.
    - If preview is larger or equal to target sizing, `NO`.
    - Otherwise, `YES`.
 */
- (BOOL)shouldContinueLoadingAfterFetchingPreviewImageResult:(nonnull id<TIPImageFetchResult>)previewImageResult;
/** should load progressively?  default == `NO` */
- (BOOL)shouldLoadProgressivelyWithIdentifier:(nonnull NSString *)identifier URL:(nonnull NSURL *)URL imageType:(nonnull NSString *)imageType originalDimensions:(CGSize)originalDimensions;
/**
 should reload after a different fetch completed?
 Has automatic/default behavior, call super to utilize auto behavior
 */
- (BOOL)shouldReloadAfterDifferentFetchCompletedWithImage:(nonnull UIImage *)image dimensions:(CGSize)dimensions identifier:(nonnull NSString *)identifier URL:(nonnull NSURL *)URL treatedAsPlaceholder:(BOOL)placeholder manuallyStored:(BOOL)manuallyStored;

#pragma mark Events - Override if desired, call super so events reach delegate too

/** fetch did start loading */
- (void)didStartLoading;
/** fetch did update progress */
- (void)didUpdateProgress:(float)progress;
/** fetch did update displayed image */
- (void)didUpdateDisplayedImage:(nonnull UIImage *)image fromSourceDimensions:(CGSize)size isFinal:(BOOL)isFinal;
/** fetch did load final image */
- (void)didLoadFinalImageFromSource:(TIPImageLoadSource)source;
/** fetch did fail */
- (void)didFailToLoadFinalImage:(nonnull NSError *)error;
/** fetch did reset */
- (void)didReset;

@end

NS_ASSUME_NONNULL_BEGIN

//! Notification that the debug info visibility for `TIPImageView` changed
FOUNDATION_EXTERN NSString * const TIPImageViewDidUpdateDebugInfoVisibilityNotification;
//! User info key of visibility, `NSNumber` wrapping a `BOOL`
FOUNDATION_EXTERN NSString * const TIPImageViewDidUpdateDebugInfoVisibilityNotificationKeyVisible;

NS_ASSUME_NONNULL_END

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
- (nonnull NSMutableArray<NSString *> *)debugInfoStrings NS_REQUIRES_SUPER;
/** trigger that the debug info needs updating */
- (void)setDebugInfoNeedsUpdate;

@end

/**
 Data source protocol for `TIPImageViewFetchHelper`
 Selection order:
    1. TIPImageContainer (TODO)
    2. UIImage
    3. TIPImageFetchRequest
    4. NSURL
 */
@protocol TIPImageViewFetchHelperDataSource <NSObject>

#pragma mark Image Load Source
@optional

// Chosen in order

/** load from a static `UIImage` */
- (nullable UIImage *)tip_imageForFetchHelper:(nonnull TIPImageViewFetchHelper *)helper;

/** load from a specific `NSURL` */
- (nullable NSURL *)tip_imageURLForFetchHelper:(nonnull TIPImageViewFetchHelper *)helper;

/** load from a `TIPImageFetchRequest` */
- (nullable id<TIPImageFetchRequest>)tip_imageFetchRequestForFetchHelper:(nonnull TIPImageViewFetchHelper *)helper;

// Pipeline

/**
 always called after a `TIPImageFetchRequest` or `NSURL` is loaded.
 Failing to implement this method or returning `nil` will end the fetch.
 */
- (nullable TIPImagePipeline *)tip_imagePipelineForFetchHelper:(nonnull TIPImageViewFetchHelper *)helper;

#pragma mark Image Load Behavior
@optional

/** can inspect the fetchImageView and the fetchRequest to make a decision.  Default == `NO` */
- (BOOL)tip_shouldRefetchOnTargetSizingChangeForFetchHelper:(nonnull TIPImageViewFetchHelper *)helper;

/** the priority for the fetch, default == `NSOperationQueuePriorityNormal` */
- (NSOperationQueuePriority)tip_fetchOperationPriorityForFetchHelper:(nonnull TIPImageViewFetchHelper *)helper;

#pragma mark Debug
@optional

/** Can extend the debug info of a debug info overlay */
- (nullable NSArray<NSString *> *)tip_additionalDebugInfoStringsForFetchHelper:(nonnull TIPImageViewFetchHelper *)helper;

@end

/** Delegate protocol for `TIPImageViewFetchHelper` */
@protocol TIPImageViewFetchHelperDelegate <NSObject>

#pragma mark Deciders
@optional

/** should update image with preview image?  default == `NO` */
- (BOOL)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper shouldUpdateImageWithPreviewImageResult:(nonnull id<TIPImageFetchResult>)previewImageResult;
/**
 should continue to load after fetching preview?
 Default behavior:
 - If preview result is a placeholder, `YES`.
 - If fetching request is placeholder, `NO`.
 - If preview is larger or equal to target sizing, `NO`.
 - Otherwise, `YES`.
 */
- (BOOL)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper shouldContinueLoadingAfterFetchingPreviewImageResult:(nonnull id<TIPImageFetchResult>)previewImageResult;
/** should load progressively?  default == `NO` */
- (BOOL)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper shouldLoadProgressivelyWithIdentifier:(nonnull NSString *)identifier URL:(nonnull NSURL *)URL imageType:(nonnull NSString *)imageType originalDimensions:(CGSize)originalDimensions;
/**
 should reload after a different fetch completed?
 Has automatic/default behavior, call super to utilize auto behavior
 */
- (BOOL)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper shouldReloadAfterDifferentFetchCompletedWithImage:(nonnull UIImage *)image dimensions:(CGSize)dimensions identifier:(nonnull NSString *)identifier URL:(nonnull NSURL *)URL treatedAsPlaceholder:(BOOL)placeholder manuallyStored:(BOOL)manuallyStored;

#pragma mark Events
@optional

/** fetch did start loading */
- (void)tip_fetchHelperDidStartLoading:(nonnull TIPImageViewFetchHelper *)helper;
/** fetch did update progress */
- (void)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper didUpdateProgress:(float)progress;
/** fetch did update displayed image */
- (void)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper didUpdateDisplayedImage:(nonnull UIImage *)image fromSourceDimensions:(CGSize)size isFinal:(BOOL)isFinal;
/** fetch did load final image */
- (void)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper didLoadFinalImageFromSource:(TIPImageLoadSource)source;
/** fetch did fail */
- (void)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper didFailToLoadFinalImage:(nonnull NSError *)error;
/** fetch did reset */
- (void)tip_fetchHelperDidReset:(nonnull TIPImageViewFetchHelper *)helper;

@end
