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
#import "TIPGlobalConfiguration.h"
#import "TIPImageFetchable.h"
#import "TIPImageFetchMetrics.h"
#import "TIPImageFetchOperation+Project.h"
#import "TIPImageFetchRequest.h"
#import "TIPImagePipeline.h"
#import "TIPImageViewFetchHelper.h"

#import "UIImage+TIPAdditions.h"

NS_ASSUME_NONNULL_BEGIN

// Primary class gets the SELF_ARG
#define SELF_ARG PRIVATE_SELF(TIPImageViewFetchHelper)

NSString * const TIPImageViewDidUpdateDebugInfoVisibilityNotification = @"TIPImageViewDidUpdateDebugInfoVisibility";
NSString * const TIPImageViewDidUpdateDebugInfoVisibilityNotificationKeyVisible = @"visible";

static NSString * const kRetryFailedLoadsNotification = @"tip.retry.fetchHelpers";

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

static BOOL _shouldUpdateImage(SELF_ARG,
                               id<TIPImageFetchResult> previewImageResult);
static BOOL _shouldContinueLoading(SELF_ARG,
                                   id<TIPImageFetchResult> previewImageResult);
static BOOL _shouldLoadProgressively(SELF_ARG,
                                     NSString *identifier,
                                     NSURL *URL,
                                     NSString *imageType,
                                     CGSize originalDimensions);
static BOOL _shouldReloadAfterDifferentFetchCompleted(SELF_ARG,
                                                      UIImage *image,
                                                      CGSize dimensions,
                                                      NSString *identifier,
                                                      NSURL *URL,
                                                      BOOL treatedAsPlaceholder,
                                                      BOOL manuallyStored);

static void _didStartLoading(SELF_ARG);
static void _didUpdateProgress(SELF_ARG,
                               float progress);
static void _didUpdateDisplayedImage(SELF_ARG,
                                     UIImage *image,
                                     CGSize sourceDimensions,
                                     BOOL isFinal);
static void _didLoadFinalImage(SELF_ARG,
                               TIPImageLoadSource source);
static void _didFailToLoadFinalImage(SELF_ARG,
                                     NSError *error);
static void _didReset(SELF_ARG);

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

- (instancetype)initWithDelegate:(nullable id<TIPImageViewFetchHelperDelegate>)delegate
                      dataSource:(nullable id<TIPImageViewFetchHelperDataSource>)dataSource
{
    if (self = [super init]) {
        _setDelegate(self, delegate);
        _dataSource = dataSource;
        _prep(self);
    }
    return self;
}

- (void)dealloc
{
    _tearDown(self);
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
    return _flags.isLoadedImageFinal ||
           _flags.isLoadedImageScaled ||
           _flags.isLoadedImageProgressive ||
           _flags.isLoadedImagePreview;
}

- (void)setDelegate:(nullable id<TIPImageViewFetchHelperDelegate>)delegate
{
    _setDelegate(self, delegate);
}

static void _setDelegate(SELF_ARG,
                         id<TIPImageViewFetchHelperDelegate> __nullable delegate)
{
    if (!self) {
        return;
    }

    self->_delegate = delegate;

    // Certain callbacks are made via non-main thread and require atomic property backing
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:)]) {
        self.atomicDelegate = delegate;
    } else {
        self.atomicDelegate = nil;
    }
}

- (void)setFetchView:(nullable UIView<TIPImageFetchable> *)fetchView
{
    TIPAssert(!fetchView || [fetchView respondsToSelector:@selector(setTip_fetchedImage:)]);

    UIView<TIPImageFetchable> *oldView = _fetchView;
    if (oldView != fetchView) {
        const BOOL triggerDisappear = TIPIsViewVisible(oldView);
        const BOOL triggerAppear = TIPIsViewVisible(fetchView);

        if (triggerDisappear) {
            if (_debugInfoView) {
                [_debugInfoView removeFromSuperview];
            }
            [self triggerViewWillDisappear];
            [self triggerViewDidDisappear];
        }

        _fetchView = fetchView;
        if (_debugInfoView && fetchView) {
            _debugInfoView.frame = fetchView.bounds;
            [fetchView addSubview:_debugInfoView];
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
    _cancelFetch(self);
    self.fetchRequest = nil;
}

- (void)clearImage
{
    _resetImage(self, nil /*image*/);
}

- (void)reload
{
    _refetch(self, nil /* peeked request */);
}

#pragma mark Override methods

- (void)setImageAsIfLoaded:(UIImage *)image
{
    [self cancelFetchRequest];
    _startObservingImagePipeline(self, nil /*image pipeline*/);
    _markAsIfLoaded(self);
    self.fetchView.tip_fetchedImage = image;
}

- (void)markAsIfLoaded
{
    if (self.fetchView.tip_fetchedImage) {
        _markAsIfLoaded(self);
    }
}

static void _markAsIfLoaded(SELF_ARG)
{
    if (self) {
        self->_flags.isLoadedImageFinal = YES;
        self->_flags.isLoadedImageScaled = NO;
        self->_flags.isLoadedImagePreview = NO;
        self->_flags.isLoadedImageProgressive = NO;
        self->_flags.treatAsPlaceholder = NO;
    }
}

- (void)setImageAsIfPlaceholder:(UIImage *)image
{
    [self cancelFetchRequest];
    _startObservingImagePipeline(self, nil /*image pipeline*/);
    _markAsIfPlaceholder(self);
    self.fetchView.tip_fetchedImage = image;
}

- (void)markAsIfPlaceholder
{
    if (self.fetchView.tip_fetchedImage) {
        _markAsIfPlaceholder(self);
    }
}

static void _markAsIfPlaceholder(SELF_ARG)
{
    if (self) {
        self->_flags.isLoadedImageFinal = NO;
        self->_flags.isLoadedImageScaled = NO;
        self->_flags.isLoadedImagePreview = NO;
        self->_flags.isLoadedImageProgressive = NO;
        self->_flags.treatAsPlaceholder = YES;
    }
}

#pragma mark Helpers

+ (void)transitionView:(UIView<TIPImageFetchable> *)fetchableView
       fromFetchHelper:(nullable TIPImageViewFetchHelper *)fromHelper
         toFetchHelper:(nullable TIPImageViewFetchHelper *)toHelper
{
    if (fromHelper == toHelper || !toHelper) {
        return;
    }

    if (fromHelper && fromHelper.fetchView != fetchableView) {
        return;
    }

    toHelper.fetchView = fetchableView;
    TIPImageFetchOperation *oldOp = fromHelper ? fromHelper->_fetchOperation : nil;
    if (oldOp) {
        [oldOp discardDelegate];

        // we want the old operation be coalesced with the new one (from the new fetch helper),
        // so defer the cancellation until after a coalescing can happen
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [oldOp cancel];
        });
    }
    fromHelper.fetchView = nil;
}


- (void)triggerViewWillChangeHidden
{
    UIView *view = self.fetchView;
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
    UIView *view = self.fetchView;
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
    UIView *imageView = self.fetchView;
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
    UIView *imageView = self.fetchView;
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
    if (!self.fetchRequest || _resizeRequestIfNeeded(self)) {
        id<TIPImageFetchRequest> peekRequest = nil;
        if (_flags.isLoadedImageFinal) {
            // downgrade what we have from being "final" to a "preview"
            _flags.isLoadedImageFinal = 0;
            _flags.isLoadedImagePreview = 1;
            _cancelFetch(self);
        } else if (_fetchOperation) {
            id<TIPImageViewFetchHelperDataSource> dataSource = self.dataSource;
            peekRequest = _extractRequest(self, dataSource);

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
        _refetch(self, peekRequest);
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
                _cancelFetch(self);
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
            _startObservingImagePipeline(self, nil /* image pipeline */);
            _refetch(self, nil /* peeked requests */);
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

static BOOL _shouldUpdateImage(SELF_ARG,
                               id<TIPImageFetchResult> previewImageResult)
{
    if (!self) {
        return NO;
    }

    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldUpdateImageWithPreviewImageResult:)]) {
        return [delegate tip_fetchHelper:self
                         shouldUpdateImageWithPreviewImageResult:previewImageResult];
    }
    return NO;
}

static BOOL _shouldContinueLoading(SELF_ARG,
                                   id<TIPImageFetchResult> previewImageResult)
{
    if (!self) {
        return NO;
    }

    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldContinueLoadingAfterFetchingPreviewImageResult:)]) {
        return [delegate tip_fetchHelper:self
                         shouldContinueLoadingAfterFetchingPreviewImageResult:previewImageResult];
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
    const CGSize viewDimensions = TIPDimensionsFromView(self.fetchView);
    if (originalDimensions.height >= viewDimensions.height && originalDimensions.width >= viewDimensions.width) {
        return NO;
    }

    return YES;
}

static BOOL _shouldLoadProgressively(SELF_ARG,
                                     NSString *identifier,
                                     NSURL *URL,
                                     NSString *imageType,
                                     CGSize originalDimensions)
{
    if (!self) {
        return NO;
    }

    id<TIPImageViewFetchHelperDelegate> delegate = self.atomicDelegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:)]) {
        return [delegate tip_fetchHelper:self
   shouldLoadProgressivelyWithIdentifier:identifier
                                     URL:URL
                               imageType:imageType
                      originalDimensions:originalDimensions];
    }
    return NO;
}

static BOOL _shouldReloadAfterDifferentFetchCompleted(SELF_ARG,
                                                      UIImage *image,
                                                      CGSize dimensions,
                                                      NSString *identifier,
                                                      NSURL *URL,
                                                      BOOL placeholder,
                                                      BOOL manuallyStored)
{
    if (!self) {
        return NO;
    }

    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldReloadAfterDifferentFetchCompletedWithImage:dimensions:identifier:URL:treatedAsPlaceholder:manuallyStored:)]) {
        return [delegate tip_fetchHelper:self
                         shouldReloadAfterDifferentFetchCompletedWithImage:image
                         dimensions:dimensions
                         identifier:identifier
                         URL:URL
                         treatedAsPlaceholder:placeholder
                         manuallyStored:manuallyStored];
    }

    id<TIPImageFetchRequest> request = self.fetchRequest;
    if (!self.fetchView.tip_fetchedImage && [request.imageURL isEqual:URL]) {
        // auto handle when the image loaded someplace else
        return YES;
    }

    if (self.fetchedImageTreatedAsPlaceholder && !placeholder) {
        // take the non-placeholder over the placeholder
        return YES;
    }

    return NO;
}

static void _didStartLoading(SELF_ARG)
{
    if (!self) {
        return;
    }

    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelperDidStartLoading:)]) {
        [delegate tip_fetchHelperDidStartLoading:self];
    }
}

static void _didUpdateProgress(SELF_ARG,
                               float progress)
{
    if (!self) {
        return;
    }

    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didUpdateProgress:)]) {
        [delegate tip_fetchHelper:self didUpdateProgress:progress];
    }
}

static void _didUpdateDisplayedImage(SELF_ARG,
                                     UIImage *image,
                                     CGSize sourceDimensions,
                                     BOOL isFinal)
{
    if (!self) {
        return;
    }

    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didUpdateDisplayedImage:fromSourceDimensions:isFinal:)]) {
        [delegate tip_fetchHelper:self
          didUpdateDisplayedImage:image
             fromSourceDimensions:sourceDimensions
                          isFinal:isFinal];
    }
}

static void _didLoadFinalImage(SELF_ARG,
                               TIPImageLoadSource source)
{
    if (!self) {
        return;
    }

    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didLoadFinalImageFromSource:)]) {
        [delegate tip_fetchHelper:self didLoadFinalImageFromSource:source];
    }
}

static void _didFailToLoadFinalImage(SELF_ARG,
                                     NSError *error)
{
    if (!self) {
        return;
    }

    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didFailToLoadFinalImage:)]) {
        [delegate tip_fetchHelper:self didFailToLoadFinalImage:error];
    }
}

static void _didReset(SELF_ARG)
{
    if (!self) {
        return;
    }

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

    _didStartLoading(self);
    [self setDebugInfoNeedsUpdate];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
            didLoadPreviewImage:(id<TIPImageFetchResult>)previewResult
                     completion:(TIPImageFetchDidLoadPreviewCallback)completion
{
    BOOL continueLoading = (op == _fetchOperation);
    if (continueLoading) {
        const BOOL shouldUpdate = _shouldUpdateImage(self, previewResult);
        if (shouldUpdate) {
            continueLoading = !!_shouldContinueLoading(self, previewResult);

            _update(self,
                    previewResult.imageContainer.image,
                    previewResult.imageOriginalDimensions,
                    previewResult.imageURL,
                    previewResult.imageSource,
                    nil /*image type*/,
                    (continueLoading) ? 0.0f : 1.0f /*progress*/,
                    nil /*error*/,
                    (continueLoading) ? nil : op.metrics,
                    !continueLoading /*final*/,
                    !continueLoading /*scaled*/,
                    NO /*progressive*/,
                    continueLoading /*preview*/,
                    !!previewResult.imageIsTreatedAsPlaceholder);

        }
    }

    completion(continueLoading ? TIPImageFetchPreviewLoadedBehaviorContinueLoading : TIPImageFetchPreviewLoadedBehaviorStopLoading);
}

- (BOOL)tip_imageFetchOperation:(TIPImageFetchOperation *)op
        shouldLoadProgressivelyWithIdentifier:(NSString *)identifier
        URL:(NSURL *)URL
        imageType:(NSString *)imageType
        originalDimensions:(CGSize)originalDimensions
{
    if (op != _fetchOperation) {
        return NO;
    }

    return _shouldLoadProgressively(self,
                                    identifier,
                                    URL,
                                    imageType,
                                    originalDimensions);
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
      didUpdateProgressiveImage:(id<TIPImageFetchResult>)progressiveResult
                       progress:(float)progress
{
    if (op != _fetchOperation) {
        return;
    }

    _update(self,
            progressiveResult.imageContainer.image,
            op.networkImageOriginalDimensions /*sourceImageDimensions*/,
            progressiveResult.imageURL,
            progressiveResult.imageSource,
            op.networkLoadImageType,
            progress,
            nil /*error*/,
            nil /*metrics*/,
            NO /*final*/,
            NO /*scaled*/,
            YES /*progressive*/,
            NO /*preview*/,
            YES /*placeholder*/ /*TODO: investigate whether there are conditions when we can pass NO*/);
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFirstAnimatedImageFrame:(id<TIPImageFetchResult>)progressiveResult progress:(float)progress
{
    if (op != _fetchOperation) {
        return;
    }

    _update(self,
            progressiveResult.imageContainer.image,
            op.networkImageOriginalDimensions /*sourceImageDimensions*/,
            op.request.imageURL,
            progressiveResult.imageSource,
            op.networkLoadImageType,
            progress,
            nil /*error*/,
            nil /*metrics*/,
            NO /*final*/,
            NO /*scaled*/,
            YES /*progressive*/,
            NO /*preview*/,
            YES /*placeholder*/ /*TODO: investigate whether there are conditions when we can pass NO*/);
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didUpdateProgress:(float)progress
{
    if (op != _fetchOperation) {
        return;
    }

    self.fetchProgress = progress;
    _loadedImageType = op.networkLoadImageType;
    _didUpdateProgress(self, progress);
    [self setDebugInfoNeedsUpdate];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFinalImage:(id<TIPImageFetchResult>)finalResult
{
    if (op != _fetchOperation) {
        return;
    }

    TIPImageContainer *imageContainer = finalResult.imageContainer;

    _fetchOperation = nil;
    _update(self,
            imageContainer.image,
            finalResult.imageOriginalDimensions /*sourceImageDimensions*/,
            finalResult.imageURL,
            finalResult.imageSource,
            op.networkLoadImageType,
            1.0f /*progress*/,
            nil /*error*/,
            op.metrics,
            YES /*final*/,
            NO /*scaled*/,
            NO /*progressive*/,
            NO /*preview*/,
            !!finalResult.imageIsTreatedAsPlaceholder);
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
        _didFailToLoadFinalImage(self, error);
    }
    [self setDebugInfoNeedsUpdate];
}

#pragma mark Private

static void _tearDown(SELF_ARG)
{
    if (!self) {
        return;
    }

    _cancelFetch(self);
    _startObservingImagePipeline(self, nil /* image pipeline */);
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self
                  name:TIPImageViewDidUpdateDebugInfoVisibilityNotification
                object:nil];
    [nc removeObserver:self
                  name:kRetryFailedLoadsNotification
                object:nil];
    [self->_debugInfoView removeFromSuperview];
}

static void _prep(SELF_ARG)
{
    if (!self) {
        return;
    }

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(_tip_didUpdateDebugVisibility)
               name:TIPImageViewDidUpdateDebugInfoVisibilityNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(_tip_retryFailedLoadsNotification:)
               name:kRetryFailedLoadsNotification
             object:nil];
    [self _tip_didUpdateDebugVisibility];
    self->_fetchDisappearanceBehavior = TIPImageViewDisappearanceBehaviorCancelImageFetch;
    _resetImage(self, nil /*image*/);
}

static BOOL _resizeRequestIfNeeded(SELF_ARG)
{
    if (!self) {
        return NO;
    }

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
        UIView *fetchView = self.fetchView;
        const CGSize viewDimensions = TIPDimensionsFromView(fetchView);
        const UIViewContentMode viewContentMode = fetchView.contentMode;
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

static void _update(SELF_ARG,
                    UIImage * __nullable image,
                    CGSize sourceDimensions,
                    NSURL * __nullable URL,
                    TIPImageLoadSource source,
                    NSString * __nullable type,
                    float progress,
                    NSError * __nullable error,
                    TIPImageFetchMetrics * __nullable metrics,
                    BOOL final,
                    BOOL scaled,
                    BOOL progressive,
                    BOOL preview,
                    BOOL placeholder)
{
    if (!self) {
        return;
    }

    if (gTwitterImagePipelineAssertEnabled) {
        TIPAssertMessage((0b11111110 & final) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & preview) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & progressive) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & scaled) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & placeholder) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
    }

    self.fetchSource = source;
    self->_fetchedImageURL = URL;
    self->_flags.isLoadedImageFinal = final;
    self->_flags.isLoadedImageScaled = scaled;
    self->_flags.isLoadedImageProgressive = progressive;
    self->_flags.isLoadedImagePreview = preview;
    self->_flags.treatAsPlaceholder = placeholder;
    self->_loadedImageType = [type copy];
    self.fetchError = error;
    self.fetchMetrics = metrics;
    if (metrics && image) {
        self.fetchResultDimensions = sourceDimensions;
    } else {
        self.fetchResultDimensions = CGSizeZero;
    }
    const float oldProgress = self.fetchProgress;
    if ((progress > oldProgress) || (progress == oldProgress && oldProgress > 0.f) || !self.didLoadAny) {
        self.fetchProgress = progress;
        _didUpdateProgress(self, progress);
    }
    self.fetchView.tip_fetchedImage = image;
    if (image) {
        _didUpdateDisplayedImage(self,
                                 image,
                                 sourceDimensions,
                                 (final || scaled) /*isFinal*/);
    }
    if (final || scaled) {
        _didLoadFinalImage(self, source);
    }
    if (!self.didLoadAny) {
        _didReset(self);
    }
    [self setDebugInfoNeedsUpdate];
}

static void _resetImage(SELF_ARG,
                        UIImage * __nullable image)
{
    if (!self) {
        return;
    }

    _cancelFetch(self);
    _startObservingImagePipeline(self, nil /*image pipelines*/);
    _update(self,
            image,
            CGSizeZero /*sourceDimensions*/,
            nil /*URL*/,
            TIPImageLoadSourceUnknown,
            nil /*image type*/,
            (image != nil) ? 1.f : 0.f /*progress*/,
            nil /*error*/,
            nil /*metrics*/,
            NO /*final*/,
            NO /*scaled*/,
            NO /*progressive*/,
            NO /*preview*/,
            NO /*placeholder*/);
}

static void _cancelFetch(SELF_ARG)
{
    if (!self) {
        return;
    }

    [self->_fetchOperation cancelAndDiscardDelegate];
    self->_fetchOperation = nil;
}

static void _refetch(SELF_ARG,
                     id<TIPImageFetchRequest> __nullable peekedRequest)
{
    if (!self) {
        return;
    }

    if (!self->_fetchOperation) {
        UIView<TIPImageFetchable> *fetchView = self.fetchView;
        if (TIPIsViewVisible(fetchView) || self->_flags.transitioningAppearance) {
            const CGSize size = fetchView.bounds.size;
            if (size.width > 0 && size.height > 0) {
                if (!fetchView.tip_fetchedImage || !self->_flags.isLoadedImageFinal) {
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
                        request = _extractRequest(self, dataSource);
                    }

                    if (request && [dataSource respondsToSelector:@selector(tip_imagePipelineForFetchHelper:)]) {
                        self.fetchRequest = request;
                        TIPImagePipeline *pipeline = [dataSource tip_imagePipelineForFetchHelper:self];

                        if (!pipeline) {
                            self.fetchRequest = nil;
                            return;
                        }

                        self->_fetchOperation = [pipeline operationWithRequest:request
                                                                       context:nil
                                                                      delegate:self];
                        if ([dataSource respondsToSelector:@selector(tip_fetchOperationPriorityForFetchHelper:)]) {
                            const NSOperationQueuePriority priority = [dataSource tip_fetchOperationPriorityForFetchHelper:self];
                            self->_fetchOperation.priority = priority;
                        }
                        _startObservingImagePipeline(self, pipeline);
                        [pipeline fetchImageWithOperation:self->_fetchOperation];
                    }
                }
            }
        }
    }
}

static id<TIPImageFetchRequest> __nullable _extractRequest(SELF_ARG,
                                                           id<TIPImageViewFetchHelperDataSource> __nullable dataSource)
{
    if (!self) {
        return nil;
    }

    id<TIPImageFetchRequest> request = nil;
    if (!request && [dataSource respondsToSelector:@selector(tip_imageFetchRequestForFetchHelper:)]) {
        request = [dataSource tip_imageFetchRequestForFetchHelper:self];
    }
    if (!request && [dataSource respondsToSelector:@selector(tip_imageURLForFetchHelper:)]) {
        NSURL *imageURL = [dataSource tip_imageURLForFetchHelper:self];
        if (imageURL) {
            request = _createRequest(self, imageURL);
        }
    }
    return request;
}

static id<TIPImageFetchRequest> _createRequest(SELF_ARG,
                                               NSURL *imageURL)
{
    TIPAssert(self);
    if (!self) {
        return nil;
    }
    return [[TIPImageViewSimpleFetchRequest alloc] initWithImageURL:imageURL targetView:self.fetchView];
}

static void _startObservingImagePipeline(SELF_ARG,
                                         TIPImagePipeline * __nullable pipeline)
{
    if (!self) {
        return;
    }

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    // Clear related observing
    [nc removeObserver:self name:TIPImagePipelineDidStoreCachedImageNotification object:nil];

    // Start observing
    if (pipeline) {
        [nc addObserver:self
               selector:@selector(_tip_imageDidUpdate:)
                   name:TIPImagePipelineDidStoreCachedImageNotification
                 object:pipeline];
    }
}

- (void)_tip_imageDidUpdate:(NSNotification *)note
{
    if (!_fetchOperation) {
        id<TIPImageFetchRequest> request = self.fetchRequest;
        NSString *requestIdentifier = TIPImageFetchRequestGetImageIdentifier(request);

        NSDictionary *userInfo = note.userInfo;
        NSString *identifier = userInfo[TIPImagePipelineImageIdentifierNotificationKey];

        if ([requestIdentifier isEqualToString:identifier]) {

            const BOOL manuallyStored = [userInfo[TIPImagePipelineImageWasManuallyStoredNotificationKey] boolValue];
            const BOOL placeholder = [userInfo[TIPImagePipelineImageTreatAsPlaceholderNofiticationKey] boolValue];
            NSURL *URL = userInfo[TIPImagePipelineImageURLNotificationKey];
            CGSize dimensions = [(NSValue *)userInfo[TIPImagePipelineImageDimensionsNotificationKey] CGSizeValue];
            TIPImageContainer *container = userInfo[TIPImagePipelineImageContainerNotificationKey];
            UIImage *image = container.image;

            const BOOL shouldReload = _shouldReloadAfterDifferentFetchCompleted(self,
                                                                                image,
                                                                                dimensions,
                                                                                identifier,
                                                                                URL,
                                                                                placeholder,
                                                                                manuallyStored);
            if (shouldReload) {
                UIView<TIPImageFetchable> *fetchView = self.fetchView;
                if (!TIPIsViewVisible(fetchView)) {
                    self->_flags.didCancelOnDisapper = 1;
                }
                _cancelFetch(self);
                _startObservingImagePipeline(self, nil /*image pipeline*/);
                self->_flags.isLoadedImageFinal = 0;
                tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
                    // clear the render cache, but async so other render cache stores can complete first
                    [[TIPGlobalConfiguration sharedInstance] clearAllRenderedMemoryCacheImagesWithIdentifier:identifier];
                    _refetch(self, nil /*peeked request*/);
                });
            }
        }
    }
}

- (void)_tip_didUpdateDebugVisibility
{
    if ([TIPImageViewFetchHelper isDebugInfoVisible]) {
        _showDebugInfo(self);
    } else {
        _hideDebugInfo(self);
    }
}

static void _showDebugInfo(SELF_ARG)
{
    if (!self) {
        return;
    }
    if (self->_debugInfoView) {
        return;
    }

    UIView *fetchView = self.fetchView;

    UILabel *label = [[UILabel alloc] initWithFrame:fetchView.bounds];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:12];
    label.numberOfLines = 2;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.5;
    label.textColor = self.debugInfoTextColor ?: kDEBUG_TEXT_COLOR_DEFAULT;
    label.backgroundColor = self.debugImageHighlightColor ?: kDEBUG_HIGHLIGHT_COLOR_DEFAULT;

    self->_debugInfoView = label;
    [fetchView addSubview:self->_debugInfoView];
    [self setDebugInfoNeedsUpdate];
}

static void _hideDebugInfo(SELF_ARG)
{
    if (!self) {
        return;
    }

    [self->_debugInfoView removeFromSuperview];
    self->_debugInfoView = nil;
}

static NSString *_getDebugInfoString(SELF_ARG,
                                     /*out*/ NSInteger * __nonnull lineCount)
{
    TIPAssert(self);
    if (!self) {
        return nil;
    }
    NSArray<NSString *> *infos = [self debugInfoStrings];
    NSString *debugInfoString = [infos componentsJoinedByString:@"\n"];
    *lineCount = (NSInteger)infos.count;
    return debugInfoString;
}

#pragma mark Retry Event

+ (void)notifyAllFetchHelpersToRetryFailedLoads
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kRetryFailedLoadsNotification
                                                            object:nil
                                                          userInfo:nil];
    });
}

- (void)_tip_retryFailedLoadsNotification:(NSNotification *)note
{
    if (self.fetchError != nil && !self.isLoading) {
        _refetch(self, nil);
    }
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

    const BOOL loadedSomething = _flags.isLoadedImageScaled ||
                                 _flags.isLoadedImagePreview ||
                                 _flags.isLoadedImageProgressive ||
                                 _flags.isLoadedImageFinal ;
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
                loadSource = [self.fetchMetrics metricInfoForSource:_fetchSource].wasLoadedSynchronously ? @"RMem" : @"Mem";
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
        NSString *info = _getDebugInfoString(self, &lineCount);
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
