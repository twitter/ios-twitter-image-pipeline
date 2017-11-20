//
//  TIPImageViewFetchHelper.m
//  TwitterImagePipeline
//
//  Created on 4/18/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPImageFetchMetrics.h"
#import "TIPImageFetchOperation+Project.h"
#import "TIPImageFetchRequest.h"
#import "TIPImagePipeline.h"
#import "TIPImageViewFetchHelper.h"

#import "UIImage+TIPAdditions.h"

NS_ASSUME_NONNULL_BEGIN

NSString * const TIPImageViewDidUpdateDebugInfoVisibilityNotification = @"TIPImageViewDidUpdateDebugInfoVisibility";
NSString * const TIPImageViewDidUpdateDebugInfoVisibilityNotificationKeyVisible = @"visible";

#define kDEBUG_HIGHLIGHT_COLOR_DEFAULT  [UIColor colorWithWhite:(CGFloat)0.3 alpha:(CGFloat)0.55]
#define kDEBUG_TEXT_COLOR_DEFAULT       [UIColor whiteColor]

static BOOL sDebugInfoVisible = NO;

NS_INLINE BOOL TIPIsViewVisible(UIView * __nullable view)
{
    return view != nil && view.window != nil && !view.isHidden;
}

@interface TIPImageViewSimpleFetchRequest : NSObject <TIPImageFetchRequest>
@property (nonatomic, readonly) NSURL *imageURL;
@property (nonatomic, readonly) CGSize targetDimensions;
@property (nonatomic, readonly) UIViewContentMode targetContentMode;
- (instancetype)initWithImageURL:(NSURL *)imageURL targetView:(nullable UIView *)view;
@end

@interface TIPImageViewFetchHelper () <TIPImageFetchDelegate>
@property (nonatomic) float fetchProgress;
@property (nonatomic, nullable) NSError *fetchError;
@property (nonatomic, nullable) TIPImageFetchMetrics *fetchMetrics;
@property (nonatomic) CGSize fetchResultDimensions;
@property (nonatomic) TIPImageLoadSource fetchSource;
@property (nonatomic, nullable) id<TIPImageFetchRequest> fetchRequest;
@property (atomic, weak, nullable) id<TIPImageViewFetchHelperDelegate> atomicDelegate;

- (BOOL)_tip_shouldUpdateImageWithPreviewImageResult:(id<TIPImageFetchResult>)previewImageResult;
- (BOOL)_tip_shouldContinueLoadingAfterFetchingPreviewImageResult:(id<TIPImageFetchResult>)previewImageResult;
- (BOOL)_tip_shouldLoadProgressivelyWithIdentifier:(NSString *)identifier URL:(NSURL *)URL imageType:(NSString *)imageType originalDimensions:(CGSize)originalDimensions;
- (BOOL)_tip_shouldReloadAfterDifferentFetchCompletedWithImage:(UIImage *)image dimensions:(CGSize)dimensions identifier:(NSString *)identifier URL:(NSURL *)URL treatedAsPlaceholder:(BOOL)placeholder manuallyStored:(BOOL)manuallyStored;

- (void)_tip_didStartLoading;
- (void)_tip_didUpdateProgress:(float)progress;
- (void)_tip_didUpdateDisplayedImage:(UIImage *)image fromSourceDimensions:(CGSize)size isFinal:(BOOL)isFinal;
- (void)_tip_didLoadFinalImageFromSource:(TIPImageLoadSource)source;
- (void)_tip_didFailToLoadFinalImage:(NSError *)error;
- (void)_tip_didReset;

@end

@implementation TIPImageViewFetchHelper
{
    TIPImageFetchOperation *_fetchOperation;
    NSOperationQueuePriority _priorPriority;
    UILabel *_debugInfoView;
    struct {
        BOOL transitioningAppearance:1;
        BOOL didCancelOnDisapper:1;
        BOOL didChangePriorityOnDisappear:1;
        BOOL isLoadedImageFinal:1;
        BOOL isLoadedImageProgressive:1;
        BOOL isLoadedImagePreview:1;
        BOOL isLoadedImageScaled:1;
        BOOL treatAsPlaceholder:1;
    } _flags;
    NSString *_loadedImageType;
    UIColor *_debugImageHighlightColor;
    UIColor *_debugInfoTextColor;
}

- (instancetype)init
{
    return [self initWithDelegate:nil dataSource:nil];
}

- (instancetype)initWithDelegate:(nullable id<TIPImageViewFetchHelperDelegate>)delegate dataSource:(nullable id<TIPImageViewFetchHelperDataSource>)dataSource
{
    if (self = [super init]) {
        [self _tip_setDelegate:delegate];
        _dataSource = dataSource;
        [self _tip_prep];
    }
    return self;
}

- (void)dealloc
{
    [self _tip_tearDown];
}

- (BOOL)fetchedImageTreatedAsPlaceholder
{
    return _flags.treatAsPlaceholder;
}

- (BOOL)fetchedImageIsPreview
{
    return _flags.isLoadedImagePreview;
}

- (BOOL)fetchedImageIsProgressiveFrame
{
    return _flags.isLoadedImageProgressive;
}

- (BOOL)fetchedImageIsScaledPreviewAsFinal
{
    return _flags.isLoadedImageScaled;
}

- (BOOL)fetchedImageIsFullLoad
{
    return _flags.isLoadedImageFinal;
}

- (BOOL)didLoadAny
{
    return _flags.isLoadedImageFinal || _flags.isLoadedImageScaled || _flags.isLoadedImageProgressive || _flags.isLoadedImagePreview;
}

- (void)setDelegate:(nullable id<TIPImageViewFetchHelperDelegate>)delegate
{
    [self _tip_setDelegate:delegate];
}

- (void)_tip_setDelegate:(nullable id<TIPImageViewFetchHelperDelegate>)delegate
{
    _delegate = delegate;

    // Certain callbacks are made via non-main thread and require atomic property backing
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:)]) {
        self.atomicDelegate = delegate;
    } else {
        self.atomicDelegate = nil;
    }
}

- (void)setFetchImageView:(nullable UIImageView *)fetchImageView
{
    UIImageView *oldView = _fetchImageView;
    if (oldView != fetchImageView) {
        const BOOL triggerDisappear = TIPIsViewVisible(oldView);
        const BOOL triggerAppear = TIPIsViewVisible(fetchImageView);

        if (triggerDisappear) {
            if (_debugInfoView) {
                [_debugInfoView removeFromSuperview];
            }
            [self triggerViewWillDisappear];
            [self triggerViewDidDisappear];
        }

        _fetchImageView = fetchImageView;
        if (_debugInfoView && fetchImageView) {
            _debugInfoView.frame = fetchImageView.bounds;
            [fetchImageView addSubview:_debugInfoView];
            [self setDebugInfoNeedsUpdate];
        }

        if (triggerAppear) {
            [self triggerViewWillAppear];
            [self triggerViewDidAppear];
        }
    }
}

- (BOOL)isLoading
{
    return _fetchOperation != nil;
}

#pragma mark Load

- (void)cancelFetchRequest
{
    [self _tip_cancelFetch];
    self.fetchRequest = nil;
}

- (void)clearImage
{
    [self _tip_resetImage:nil];
}

- (void)reload
{
    [self _tip_refetch:nil];
}

#pragma mark Override methods

- (void)setImageAsIfLoaded:(UIImage *)image
{
    [self cancelFetchRequest];
    [self _tip_startObservingImagePipeline:nil];
    self.fetchImageView.image = image;
    [self markAsIfLoaded];
}

- (void)markAsIfLoaded
{
    if (self.fetchImageView.image) {
        _flags.isLoadedImageFinal = YES;
        _flags.isLoadedImageScaled = NO;
        _flags.isLoadedImagePreview = NO;
        _flags.isLoadedImageProgressive = NO;
        _flags.treatAsPlaceholder = NO;
    }
}

- (void)setImageAsIfPlaceholder:(UIImage *)image
{
    [self cancelFetchRequest];
    [self _tip_startObservingImagePipeline:nil];
    self.fetchImageView.image = image;
    [self markAsIfPlaceholder];
}

- (void)markAsIfPlaceholder
{
    if (self.fetchImageView.image) {
        _flags.isLoadedImageFinal = NO;
        _flags.isLoadedImageScaled = NO;
        _flags.isLoadedImagePreview = NO;
        _flags.isLoadedImageProgressive = NO;
        _flags.treatAsPlaceholder = YES;
    }
}

#pragma mark Helpers

+ (void)transitionView:(UIImageView *)imageView fromFetchHelper:(nullable TIPImageViewFetchHelper *)fromHelper toFetchHelper:(nullable TIPImageViewFetchHelper *)toHelper
{
    if (fromHelper == toHelper || !toHelper) {
        return;
    }

    if (fromHelper && fromHelper.fetchImageView != imageView) {
        return;
    }

    toHelper.fetchImageView = imageView;
    TIPImageFetchOperation *oldOp = fromHelper ? fromHelper->_fetchOperation : nil;
    if (oldOp) {
        [oldOp discardDelegate];

        // we want the old operation be coalesced with the new one (from the new fetch helper),
        // so defer the cancellation until after a coalescing can happen
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [oldOp cancel];
        });
    }
    fromHelper.fetchImageView = nil;
}


- (void)triggerViewWillChangeHidden
{
    UIView *view = self.fetchImageView;
    if (view.window != nil) {
        if (view.isHidden) {
            [self triggerViewWillAppear];
        } else {
            [self triggerViewWillDisappear];
        }
    }
}

- (void)triggerViewDidChangeHidden
{
    UIView *view = self.fetchImageView;
    if (view.window != nil) {
        if (view.isHidden) {
            [self triggerViewDidDisappear];
        } else {
            [self triggerViewDidAppear];
        }
    }
}

- (void)triggerViewWillMoveToWindow:(nullable UIWindow *)newWindow
{
    UIView *imageView = self.fetchImageView;
    if (TIPIsViewVisible(imageView) && !newWindow) {
        // going from visible to not
        [self triggerViewWillDisappear];
    } else if (!imageView.window && !imageView.isHidden && newWindow) {
        // going from not visible to visible
        [self triggerViewWillAppear];
    }
}

- (void)triggerViewDidMoveToWindow
{
    UIView *imageView = self.fetchImageView;
    if (_flags.transitioningAppearance) {
        if (imageView.window) {
            TIPAssert(TIPIsViewVisible(imageView));
            [self triggerViewDidAppear];
        } else {
            [self triggerViewDidDisappear];
        }
    }
}

#pragma mark Triggers

- (void)triggerViewLayingOutSubviews
{
    if (!self.fetchRequest || [self _tip_resizeRequestIfNeeded]) {
        id<TIPImageFetchRequest> peekRequest = nil;
        if (_flags.isLoadedImageFinal) {
            // downgrade what we have from being "final" to a "preview"
            _flags.isLoadedImageFinal = 0;
            _flags.isLoadedImagePreview = 1;
            [self _tip_cancelFetch];
        } else if (_fetchOperation) {
            id<TIPImageViewFetchHelperDataSource> dataSource = self.dataSource;
            peekRequest = [self _tip_extractRequestFromDataSource:dataSource];

            if (peekRequest && [_fetchOperation.request.imageURL isEqual:peekRequest.imageURL]) {
                // We're about to fetch the same image as our current op.
                // Don't cancel the current op, just make it headless (no delegate).
                // That way, the resize doesn't force the request to stop and start again.
                [_fetchOperation discardDelegate];
            } else {
                [_fetchOperation cancelAndDiscardDelegate];
            }
            _fetchOperation = nil;
        }
        [self _tip_refetch:peekRequest];
    }
}

- (void)triggerViewWillDisappear
{
    _flags.transitioningAppearance = 1;
}

- (void)triggerViewDidDisappear
{
    _flags.transitioningAppearance = 0;
    switch (self.fetchDisappearanceBehavior) {
        case TIPImageViewDisappearanceBehaviorNone:
            break;
        case TIPImageViewDisappearanceBehaviorCancelImageFetch:
        {
            if (_fetchOperation) {
                [self _tip_cancelFetch];
                _flags.didCancelOnDisapper = 1;
            }
            break;
        }
        case TIPImageViewDisappearanceBehaviorLowerImageFetchPriority:
        {
            if (_fetchOperation) {
                _priorPriority = _fetchOperation.priority;
                _fetchOperation.priority = NSOperationQueuePriorityVeryLow;
                _flags.didChangePriorityOnDisappear = 1;
            }
            break;
        }
    }
}

- (void)triggerViewWillAppear
{
    _flags.transitioningAppearance = 1;
    if (!_fetchOperation) {
        if (!_flags.isLoadedImageFinal) {
            [self cancelFetchRequest];
            [self _tip_startObservingImagePipeline:nil];
            [self _tip_refetch:nil];
        }
    } else {
        if (_flags.didChangePriorityOnDisappear) {
            _fetchOperation.priority = _priorPriority;
        }
    }
    _flags.didCancelOnDisapper = _flags.didChangePriorityOnDisappear = 0;
}

- (void)triggerViewDidAppear
{
    _flags.transitioningAppearance = 0;
}

#pragma mark Events

- (BOOL)_tip_shouldUpdateImageWithPreviewImageResult:(id<TIPImageFetchResult>)previewImageResult
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldUpdateImageWithPreviewImageResult:)]) {
        return [delegate tip_fetchHelper:self shouldUpdateImageWithPreviewImageResult:previewImageResult];
    }
    return NO;
}

- (BOOL)_tip_shouldContinueLoadingAfterFetchingPreviewImageResult:(id<TIPImageFetchResult>)previewImageResult
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldContinueLoadingAfterFetchingPreviewImageResult:)]) {
        return [delegate tip_fetchHelper:self shouldContinueLoadingAfterFetchingPreviewImageResult:previewImageResult];
    }

    if (previewImageResult.imageIsTreatedAsPlaceholder) {
        return YES;
    }

    id<TIPImageFetchRequest> request = self.fetchRequest;
    if ([request respondsToSelector:@selector(options)] && (request.options & TIPImageFetchTreatAsPlaceholder)) {
        // would be a downgrade, stop
        return NO;
    }

    const CGSize originalDimensions = previewImageResult.imageOriginalDimensions;
    const CGSize viewDimensions = TIPDimensionsFromView(self.fetchImageView);
    if (originalDimensions.height >= viewDimensions.height && originalDimensions.width >= viewDimensions.width) {
        return NO;
    }

    return YES;
}

- (BOOL)_tip_shouldLoadProgressivelyWithIdentifier:(NSString *)identifier URL:(NSURL *)URL imageType:(NSString *)imageType originalDimensions:(CGSize)originalDimensions
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.atomicDelegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:)]) {
        return [delegate tip_fetchHelper:self shouldLoadProgressivelyWithIdentifier:identifier URL:URL imageType:imageType originalDimensions:originalDimensions];
    }
    return NO;
}

- (BOOL)_tip_shouldReloadAfterDifferentFetchCompletedWithImage:(UIImage *)image dimensions:(CGSize)dimensions identifier:(NSString *)identifier URL:(NSURL *)URL treatedAsPlaceholder:(BOOL)placeholder manuallyStored:(BOOL)manuallyStored
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldReloadAfterDifferentFetchCompletedWithImage:dimensions:identifier:URL:treatedAsPlaceholder:manuallyStored:)]) {
        return [delegate tip_fetchHelper:self shouldReloadAfterDifferentFetchCompletedWithImage:image dimensions:dimensions identifier:identifier URL:URL treatedAsPlaceholder:placeholder manuallyStored:manuallyStored];
    }

    id<TIPImageFetchRequest> request = self.fetchRequest;
    if (!self.fetchImageView.image && [request.imageURL isEqual:URL]) {
        // auto handle when the image loaded someplace else
        return YES;
    }

    if (self.fetchedImageTreatedAsPlaceholder && !placeholder) {
        // take the non-placeholder over the placeholder
        return YES;
    }

    return NO;
}

- (void)_tip_didStartLoading
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelperDidStartLoading:)]) {
        [delegate tip_fetchHelperDidStartLoading:self];
    }
}

- (void)_tip_didUpdateProgress:(float)progress
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didUpdateProgress:)]) {
        [delegate tip_fetchHelper:self didUpdateProgress:progress];
    }
}

- (void)_tip_didUpdateDisplayedImage:(UIImage *)image fromSourceDimensions:(CGSize)size isFinal:(BOOL)isFinal
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didUpdateDisplayedImage:fromSourceDimensions:isFinal:)]) {
        [delegate tip_fetchHelper:self didUpdateDisplayedImage:image fromSourceDimensions:size isFinal:isFinal];
    }
}

- (void)_tip_didLoadFinalImageFromSource:(TIPImageLoadSource)source
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didLoadFinalImageFromSource:)]) {
        [delegate tip_fetchHelper:self didLoadFinalImageFromSource:source];
    }
}

- (void)_tip_didFailToLoadFinalImage:(NSError *)error
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didFailToLoadFinalImage:)]) {
        [delegate tip_fetchHelper:self didFailToLoadFinalImage:error];
    }
}

- (void)_tip_didReset
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelperDidReset:)]) {
        [delegate tip_fetchHelperDidReset:self];
    }
}

#pragma mark Fetch Delegate

- (void)tip_imageFetchOperationDidStart:(TIPImageFetchOperation *)op
{
    if (op != _fetchOperation) {
        return;
    }

    [self _tip_didStartLoading];
    [self setDebugInfoNeedsUpdate];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadPreviewImage:(id<TIPImageFetchResult>)previewResult completion:(TIPImageFetchDidLoadPreviewCallback)completion
{

    BOOL continueLoading = (op == _fetchOperation);
    if (continueLoading) {
        const BOOL shouldUpdate = [self _tip_shouldUpdateImageWithPreviewImageResult:previewResult];
        if (shouldUpdate) {
            continueLoading = !![self _tip_shouldContinueLoadingAfterFetchingPreviewImageResult:previewResult];

            [self _tip_updateImage:previewResult.imageContainer.image
                  sourceDimensions:previewResult.imageOriginalDimensions
                               URL:previewResult.imageURL
                            source:previewResult.imageSource
                              type:nil
                          progress:(continueLoading) ? 0.0f : 1.0f
                             error:nil
                           metrics:(continueLoading) ? nil : op.metrics
                             final:!continueLoading
                            scaled:!continueLoading
                       progressive:NO
                           preview:continueLoading
                       placeholder:previewResult.imageIsTreatedAsPlaceholder];

        }
    }

    completion(continueLoading ? TIPImageFetchPreviewLoadedBehaviorContinueLoading : TIPImageFetchPreviewLoadedBehaviorStopLoading);
}

- (BOOL)tip_imageFetchOperation:(TIPImageFetchOperation *)op shouldLoadProgressivelyWithIdentifier:(NSString *)identifier URL:(NSURL *)URL imageType:(NSString *)imageType originalDimensions:(CGSize)originalDimensions
{
    if (op != _fetchOperation) {
        return NO;
    }

    return [self _tip_shouldLoadProgressivelyWithIdentifier:identifier URL:URL imageType:imageType originalDimensions:originalDimensions];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didUpdateProgressiveImage:(id<TIPImageFetchResult>)progressiveResult progress:(float)progress
{
    if (op != _fetchOperation) {
        return;
    }

    [self _tip_updateImage:progressiveResult.imageContainer.image
          sourceDimensions:op.networkImageOriginalDimensions
                       URL:progressiveResult.imageURL
                    source:progressiveResult.imageSource
                      type:op.networkLoadImageType
                  progress:progress
                     error:nil
                   metrics:nil
                     final:NO
                    scaled:NO
               progressive:YES
                   preview:NO
               placeholder:YES /*TODO: investigate whether there are conditions when we can pass NO*/];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFirstAnimatedImageFrame:(id<TIPImageFetchResult>)progressiveResult progress:(float)progress
{
    if (op != _fetchOperation) {
        return;
    }

    [self _tip_updateImage:progressiveResult.imageContainer.image
          sourceDimensions:op.networkImageOriginalDimensions
                       URL:op.request.imageURL
                    source:progressiveResult.imageSource
                      type:op.networkLoadImageType
                  progress:progress
                     error:nil
                   metrics:nil
                     final:NO
                    scaled:NO
               progressive:YES
                   preview:NO
               placeholder:YES /*TODO: investigate whether there are conditions when we can pass NO*/];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didUpdateProgress:(float)progress
{
    if (op != _fetchOperation) {
        return;
    }

    self.fetchProgress = progress;
    _loadedImageType = op.networkLoadImageType;
    [self _tip_didUpdateProgress:progress];
    [self setDebugInfoNeedsUpdate];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFinalImage:(id<TIPImageFetchResult>)finalResult
{
    if (op != _fetchOperation) {
        return;
    }

    TIPImageContainer *imageContainer = finalResult.imageContainer;

    _fetchOperation = nil;
    [self _tip_updateImage:imageContainer.image
          sourceDimensions:finalResult.imageOriginalDimensions
                       URL:finalResult.imageURL
                    source:finalResult.imageSource
                      type:op.networkLoadImageType
                  progress:1.0f
                     error:nil
                   metrics:op.metrics
                     final:YES
                    scaled:NO
               progressive:NO
                   preview:NO
               placeholder:!!finalResult.imageIsTreatedAsPlaceholder];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didFailToLoadFinalImage:(NSError *)error
{
    if (op != _fetchOperation) {
        return;
    }

    _fetchOperation = nil;

    self.fetchMetrics = op.metrics;
    if ([error.domain isEqualToString:TIPImageFetchErrorDomain] && TIPImageFetchErrorCodeCancelledAfterLoadingPreview == error.code) {
        // already finished as success
    } else {
        self.fetchError = error;
        [self _tip_didFailToLoadFinalImage:error];
    }
    [self setDebugInfoNeedsUpdate];
}

#pragma mark Private

- (void)_tip_tearDown
{
    [self _tip_cancelFetch];
    [self _tip_startObservingImagePipeline:nil];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:TIPImageViewDidUpdateDebugInfoVisibilityNotification object:nil];
    [_debugInfoView removeFromSuperview];
}

- (void)_tip_prep
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_tip_didUpdateDebugVisibility) name:TIPImageViewDidUpdateDebugInfoVisibilityNotification object:nil];
    [self _tip_didUpdateDebugVisibility];
    _fetchDisappearanceBehavior = TIPImageViewDisappearanceBehaviorCancelImageFetch;
    [self _tip_resetImage:nil];
}

- (BOOL)_tip_resizeRequestIfNeeded
{
    id<TIPImageViewFetchHelperDataSource> dataSource = self.dataSource;
    if (![dataSource respondsToSelector:@selector(tip_shouldRefetchOnTargetSizingChangeForFetchHelper:)]) {
        return NO;
    }

    id<TIPImageFetchRequest> fetchRequest = self.fetchRequest;
    const CGSize targetDimensions = [fetchRequest respondsToSelector:@selector(targetDimensions)] ? [fetchRequest targetDimensions] : CGSizeZero;
    const UIViewContentMode targetContentMode = [fetchRequest respondsToSelector:@selector(targetContentMode)] ? [fetchRequest targetContentMode] : UIViewContentModeCenter;

    BOOL canRefetch = NO;
    if (!TIPContentModeDoesScale(targetContentMode) || !TIPSizeGreaterThanZero(targetDimensions)) {
        canRefetch = YES; // don't know the sizing, can refetch
    } else {
        UIImageView *fetchImageView = self.fetchImageView;
        const CGSize viewDimensions = TIPDimensionsFromView(fetchImageView);
        const UIViewContentMode viewContentMode = fetchImageView.contentMode;
        if (!CGSizeEqualToSize(viewDimensions, targetDimensions)) {
            canRefetch = YES; // size differs, can refetch
        } else if (viewContentMode != targetContentMode) {
            canRefetch = YES; // content mode differs, can refetch
        }
    }

    if (canRefetch) {
        return [dataSource tip_shouldRefetchOnTargetSizingChangeForFetchHelper:self];
    }

    return NO;
}

- (void)_tip_updateImage:(nullable UIImage *)image sourceDimensions:(CGSize)sourceDimensions URL:(nullable NSURL *)URL source:(TIPImageLoadSource)source type:(nullable NSString *)type progress:(float)progress error:(nullable NSError *)error metrics:(nullable TIPImageFetchMetrics *)metrics final:(BOOL)final scaled:(BOOL)scaled progressive:(BOOL)progressive preview:(BOOL)preview placeholder:(BOOL)placeholder
{
    if (gTwitterImagePipelineAssertEnabled) {
        TIPAssertMessage((0b11111110 & final) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & preview) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & progressive) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & scaled) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & placeholder) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
    }

    self.fetchImageView.image = image;
    self.fetchSource = source;
    _fetchedImageURL = URL;
    _flags.isLoadedImageFinal = final;
    _flags.isLoadedImageScaled = scaled;
    _flags.isLoadedImageProgressive = progressive;
    _flags.isLoadedImagePreview = preview;
    _flags.treatAsPlaceholder = placeholder;
    _loadedImageType = [type copy];
    self.fetchError = error;
    self.fetchMetrics = metrics;
    if (metrics && image) {
        self.fetchResultDimensions = [image tip_dimensions];
    } else {
        self.fetchResultDimensions = CGSizeZero;
    }
    const float oldProgress = self.fetchProgress;
    if ((progress > oldProgress) || (progress == oldProgress && oldProgress > 0.f) || !self.didLoadAny) {
        self.fetchProgress = progress;
        [self _tip_didUpdateProgress:progress];
    }
    if (image) {
        [self _tip_didUpdateDisplayedImage:image fromSourceDimensions:sourceDimensions isFinal:final || scaled];
    }
    if (final || scaled) {
        [self _tip_didLoadFinalImageFromSource:source];
    }
    if (!self.didLoadAny) {
        [self _tip_didReset];
    }
    [self setDebugInfoNeedsUpdate];
}

- (void)_tip_resetImage:(nullable UIImage *)image
{
    [self _tip_cancelFetch];
    [self _tip_startObservingImagePipeline:nil];
    [self _tip_updateImage:image
          sourceDimensions:CGSizeZero
                       URL:nil
                    source:TIPImageLoadSourceUnknown
                      type:nil
                  progress:(image != nil) ? 1.f : 0.f
                     error:nil
                   metrics:nil
                     final:NO
                    scaled:NO
               progressive:NO
                   preview:NO
               placeholder:NO];
}

- (void)_tip_cancelFetch
{
    [_fetchOperation cancelAndDiscardDelegate];
    _fetchOperation = nil;
}

- (void)_tip_refetch:(nullable id<TIPImageFetchRequest>)peekedRequest
{
    if (!_fetchOperation) {
        UIImageView *imageView = self.fetchImageView;
        if (TIPIsViewVisible(imageView) || _flags.transitioningAppearance) {
            const CGSize size = imageView.bounds.size;
            if (size.width > 0 && size.height > 0) {
                if (!imageView.image || !_flags.isLoadedImageFinal) {
                    id<TIPImageViewFetchHelperDataSource> dataSource = self.dataSource;

                    // Attempt static load first

                    if ([dataSource respondsToSelector:@selector(tip_imageForFetchHelper:)]) {
                        UIImage *image = [dataSource tip_imageForFetchHelper:self];
                        if (image) {
                            [self setImageAsIfLoaded:image];
                            return;
                        }
                    }

                    // Attempt network load

                    id<TIPImageFetchRequest> request = peekedRequest;
                    if (!request) {
                        request = [self _tip_extractRequestFromDataSource:dataSource];
                    }

                    if (request && [dataSource respondsToSelector:@selector(tip_imagePipelineForFetchHelper:)]) {
                        self.fetchRequest = request;
                        TIPImagePipeline *pipeline = [dataSource tip_imagePipelineForFetchHelper:self];

                        if (!pipeline) {
                            self.fetchRequest = nil;
                            return;
                        }

                        _fetchOperation = [pipeline operationWithRequest:request context:nil delegate:self];
                        if ([dataSource respondsToSelector:@selector(tip_fetchOperationPriorityForFetchHelper:)]) {
                            const NSOperationQueuePriority priority = [dataSource tip_fetchOperationPriorityForFetchHelper:self];
                            _fetchOperation.priority = priority;
                        }
                        [self _tip_startObservingImagePipeline:pipeline];
                        [pipeline fetchImageWithOperation:_fetchOperation];
                    }
                }
            }
        }
    }
}

- (nullable id<TIPImageFetchRequest>)_tip_extractRequestFromDataSource:(nullable id<TIPImageViewFetchHelperDataSource>)dataSource
{
    id<TIPImageFetchRequest> request = nil;
    if (!request && [dataSource respondsToSelector:@selector(tip_imageFetchRequestForFetchHelper:)]) {
        request = [dataSource tip_imageFetchRequestForFetchHelper:self];
    }
    if (!request && [dataSource respondsToSelector:@selector(tip_imageURLForFetchHelper:)]) {
        NSURL *imageURL = [dataSource tip_imageURLForFetchHelper:self];
        if (imageURL) {
            request = [self _tip_requestForURL:imageURL];
        }
    }
    return request;
}

- (id<TIPImageFetchRequest>)_tip_requestForURL:(NSURL *)imageURL
{
    return [[TIPImageViewSimpleFetchRequest alloc] initWithImageURL:imageURL targetView:self.fetchImageView];
}

- (void)_tip_startObservingImagePipeline:(nullable TIPImagePipeline *)pipeline
{
    // Clear related observing
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TIPImagePipelineDidStoreCachedImageNotification object:nil];

    // Start observing
    if (pipeline) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_tip_imageDidUpdate:) name:TIPImagePipelineDidStoreCachedImageNotification object:pipeline];
    }
}

- (void)_tip_imageDidUpdate:(NSNotification *)note
{
    if (!_fetchOperation) {
        id<TIPImageFetchRequest> request = self.fetchRequest;
        NSString *requestIdentifier = [request respondsToSelector:@selector(imageIdentifier)] ? request.imageIdentifier : [request.imageURL absoluteString];

        NSDictionary *userInfo = note.userInfo;
        NSString *identifier = userInfo[TIPImagePipelineImageIdentifierNotificationKey];

        if ([requestIdentifier isEqualToString:identifier]) {

            const BOOL manuallyStored = [userInfo[TIPImagePipelineImageWasManuallyStoredNotificationKey] boolValue];
            const BOOL placeholder = [userInfo[TIPImagePipelineImageTreatAsPlaceholderNofiticationKey] boolValue];
            NSURL *URL = userInfo[TIPImagePipelineImageURLNotificationKey];
            CGSize dimensions = [(NSValue *)userInfo[TIPImagePipelineImageDimensionsNotificationKey] CGSizeValue];
            TIPImageContainer *container = userInfo[TIPImagePipelineImageContainerNotificationKey];
            UIImage *image = container.image;

            if ([self _tip_shouldReloadAfterDifferentFetchCompletedWithImage:image dimensions:dimensions identifier:identifier URL:URL treatedAsPlaceholder:placeholder manuallyStored:manuallyStored]) {
                _flags.isLoadedImageFinal = 0;
                UIImageView *fetchImageView = self.fetchImageView;
                if (!TIPIsViewVisible(fetchImageView)) {
                    _flags.didCancelOnDisapper = 1;
                }
                [self _tip_resetImage:fetchImageView.image];
                [self _tip_refetch:nil];
            }
        }
    }
}

- (void)_tip_didUpdateDebugVisibility
{
    if ([TIPImageViewFetchHelper isDebugInfoVisible]) {
        [self _tip_showDebugInfo];
    } else {
        [self _tip_hideDebugInfo];
    }
}

- (void)_tip_showDebugInfo
{
    if (_debugInfoView) {
        return;
    }

    UIImageView *fetchImageView = self.fetchImageView;

    UILabel *label = [[UILabel alloc] initWithFrame:fetchImageView.bounds];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:12];
    label.numberOfLines = 2;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.5;
    label.textColor = self.debugInfoTextColor ?: kDEBUG_TEXT_COLOR_DEFAULT;
    label.backgroundColor = self.debugImageHighlightColor ?: kDEBUG_HIGHLIGHT_COLOR_DEFAULT;

    _debugInfoView = label;
    [fetchImageView addSubview:_debugInfoView];
    [self setDebugInfoNeedsUpdate];
}

- (void)_tip_hideDebugInfo
{
    [_debugInfoView removeFromSuperview];
    _debugInfoView = nil;
}

- (NSString *)_tip_debugInfoString:(out NSInteger * __nonnull)lineCount
{
    NSArray<NSString *> *infos = [self debugInfoStrings];
    NSString *debugInfoString = [infos componentsJoinedByString:@"\n"];
    *lineCount = (NSInteger)infos.count;
    return debugInfoString;
}

@end

@implementation TIPImageViewFetchHelper (Debugging)

+ (void)setDebugInfoVisible:(BOOL)debugInfoVisible
{
    TIPAssert([NSThread isMainThread]);
    debugInfoVisible = !!debugInfoVisible; // isolate on 1-bit (0 or 1)
    if (sDebugInfoVisible != debugInfoVisible) {
        sDebugInfoVisible = debugInfoVisible;
        [[NSNotificationCenter defaultCenter] postNotificationName:TIPImageViewDidUpdateDebugInfoVisibilityNotification object:nil userInfo:@{ TIPImageViewDidUpdateDebugInfoVisibilityNotificationKeyVisible : @(sDebugInfoVisible) }];
    }
}

+ (BOOL)isDebugInfoVisible
{
    TIPAssert([NSThread isMainThread]);
    return sDebugInfoVisible;
}

- (void)setDebugInfoTextColor:(nullable UIColor *)debugInfoTextColor
{
    _debugInfoTextColor = debugInfoTextColor;
    if (_debugInfoView) {
        _debugInfoView.textColor = _debugInfoTextColor ?: kDEBUG_TEXT_COLOR_DEFAULT;
    }
}

- (nullable UIColor *)debugInfoTextColor
{
    return _debugInfoTextColor;
}

- (void)setDebugImageHighlightColor:(nullable UIColor *)debugImageHighlightColor
{
    _debugImageHighlightColor = debugImageHighlightColor;
    if (_debugInfoView) {
        _debugInfoView.backgroundColor = debugImageHighlightColor ?: kDEBUG_HIGHLIGHT_COLOR_DEFAULT;
    }
}

- (nullable UIColor *)debugImageHighlightColor
{
    return _debugImageHighlightColor;
}

- (NSMutableArray<NSString *> *)debugInfoStrings
{
    NSMutableArray<NSString *> *infos = [[NSMutableArray alloc] init];

    NSString *loadSource = @"Manual";
    NSString *loadType = @"";
    NSString *imageType = @"";
    NSString *imageBytes = @"";
    NSString *pixelsPerByte = nil;

    const BOOL loadedSomething = _flags.isLoadedImageScaled || _flags.isLoadedImagePreview || _flags.isLoadedImageProgressive || _flags.isLoadedImageFinal ;
    if (loadedSomething) {
        if (_flags.isLoadedImageFinal) {
            loadType = @"done";
        } else {
            if (_flags.isLoadedImageProgressive) {
                loadType = @"scan";
            } else if (_flags.isLoadedImagePreview) {
                loadType = @"preview";
            } else {
                loadType = @"scaled";
            }
        }

        switch (_fetchSource) {
            case TIPImageLoadSourceMemoryCache:
                loadSource = @"Mem";
                break;
            case TIPImageLoadSourceDiskCache:
                loadSource = @"Disk";
                break;
            case TIPImageLoadSourceAdditionalCache:
                loadSource = @"Other";
                break;
            case TIPImageLoadSourceNetwork:
                loadSource = @"Network";
                break;
            case TIPImageLoadSourceNetworkResumed:
                loadSource = @"NetResm";
                break;
            case TIPImageLoadSourceUnknown:
            default:
                loadSource = @"???";
                break;
        }

        if (_flags.isLoadedImageFinal || _flags.isLoadedImageProgressive) {
            if (_fetchSource >= TIPImageLoadSourceNetwork) {
                imageType = [NSString stringWithFormat:@" %@", (_loadedImageType ?: @"???")];

                if (_fetchMetrics) {
                    TIPImageFetchMetricInfo *info = [_fetchMetrics metricInfoForSource:_fetchSource];
                    if (info.networkImageSizeInBytes > 0) {
                        imageBytes = [@" " stringByAppendingString:[NSByteCountFormatter stringFromByteCount:(long long)info.networkImageSizeInBytes countStyle:NSByteCountFormatterCountStyleBinary]];
                    }
                    if (info.networkImagePixelsPerByte > 0) {
                        pixelsPerByte = [NSString stringWithFormat:@"Pixels/Byte: %.3f", info.networkImagePixelsPerByte];
                    }
                }
            }
        }
    } else if (_fetchOperation != nil) {
        loadSource = @"Loading";
    }

    [infos addObject:[NSString stringWithFormat:@"%3i%%%@%@", (int)(self.fetchProgress * 100), imageType, imageBytes]];
    [infos addObject:[NSString stringWithFormat:@"%@ %@", loadSource, loadType]];
    if (_fetchSource >= TIPImageLoadSourceNetwork && self.fetchMetrics.totalDuration > 0) {
        [infos addObject:[NSString stringWithFormat:@"Total: %.2fs", self.fetchMetrics.totalDuration]];
    }
    if (self.fetchError) {
        [infos addObject:[NSString stringWithFormat:@"%@:%ti", self.fetchError.domain, self.fetchError.code]];
    }
    if (pixelsPerByte) {
        [infos addObject:pixelsPerByte];
    }

    id<TIPImageViewFetchHelperDataSource> dataSource = self.dataSource;
    if ([dataSource respondsToSelector:@selector(tip_additionalDebugInfoStringsForFetchHelper:)]) {
        NSArray<NSString *> *extraInfo = [dataSource tip_additionalDebugInfoStringsForFetchHelper:self];
        if (extraInfo) {
            [infos addObjectsFromArray:extraInfo];
        }
    }

    return infos;
}

- (void)setDebugInfoNeedsUpdate
{
    if (_debugInfoView) {
        NSInteger lineCount = 1;
        NSString *info = [self _tip_debugInfoString:&lineCount];
        _debugInfoView.numberOfLines = lineCount;
        _debugInfoView.text = info;
    }
}

@end

@implementation TIPImageViewSimpleFetchRequest

- (instancetype)initWithImageURL:(NSURL *)imageURL targetView:(nullable UIView *)view
{
    if (self = [super init]) {
        _imageURL = imageURL;
        if (view) {
            _targetDimensions = TIPDimensionsFromView(view);
            _targetContentMode = view.contentMode;
        }
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
