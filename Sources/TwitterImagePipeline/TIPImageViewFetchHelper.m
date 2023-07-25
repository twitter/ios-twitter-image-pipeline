//
//  TIPImageViewFetchHelper.m
//  TwitterImagePipeline
//
//  Created on 4/18/16.
//  Copyright © 2020 Twitter. All rights reserved.
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
- (instancetype)initWithImageURL:(NSURL *)imageURL targetView:(nullable UIView *)view TIP_OBJC_DIRECT;
@end

@interface TIPImageViewFetchHelper ()

@property (nonatomic) float fetchProgress;
@property (nonatomic, nullable) NSError *fetchError;
@property (nonatomic, nullable) TIPImageFetchMetrics *fetchMetrics;
@property (nonatomic) CGSize fetchResultDimensions;
@property (nonatomic) TIPImageLoadSource fetchSource;
@property (nonatomic, nullable) id<TIPImageFetchRequest> fetchRequest;
@property (tip_atomic_direct, weak, nullable) id<TIPImageViewFetchHelperDelegate> atomicDelegate;

- (void)_setDelegateInternal:(nullable id<TIPImageViewFetchHelperDelegate>)delegate TIP_OBJC_DIRECT;
- (void)_markAsIfLoaded TIP_OBJC_DIRECT;
- (void)_markAsIfPlaceholder TIP_OBJC_DIRECT;

@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageViewFetchHelper (Events)

- (BOOL)_shouldUpdateImageWithResult:(id<TIPImageFetchResult>)previewImageResult;
- (BOOL)_shouldContinueLoadingWithResult:(id<TIPImageFetchResult>)previewImageResult;
- (BOOL)_shouldLoadProgressivelyWithIdentifier:(NSString *)identifier
                                      imageURL:(NSURL *)URL
                                     imageType:(NSString *)imageType
                            originalDimensions:(CGSize)originalDimensions;
- (BOOL)_shouldReloadAfterDifferentFetchCompletedWithImageContainer:(TIPImageContainer *)image
                                                         dimensions:(CGSize)dimensions
                                                         identifier:(NSString *)identifier
                                                           imageURL:(NSURL *)URL
                                               treatedAsPlaceholder:(BOOL)treatedAsPlaceholder
                                                     manuallyStored:(BOOL)manuallyStored;

- (void)_didStartLoading;
- (void)_didUpdateProgress:(float)progress;
- (void)_didUpdateDisplayedImageContainer:(TIPImageContainer *)imageContainer
                         sourceDimensions:(CGSize)sourceDimensions
                                  isFinal:(BOOL)isFinal;
- (void)_didLoadFinalImageFromSource:(TIPImageLoadSource)source;
- (void)_didFailToLoadFinalImageWithError:(NSError *)error;
- (void)_didReset;

@end

@interface TIPImageViewFetchHelper (TIPImageFetchDelegate) <TIPImageFetchDelegate>
@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageViewFetchHelper (Private)
- (void)_tearDown;
- (void)_prep;
- (void)_handleViewResizeEvent;
- (BOOL)_resizeRequestIfNeeded;
- (void)_updateImageContainer:(nullable TIPImageContainer *)imageContainer
             sourceDimensions:(CGSize)sourceDimensions
                          URL:(nullable NSURL *)URL
                       source:(TIPImageLoadSource)source
                         type:(nullable NSString *)type
                     progress:(float)progress
                        error:(nullable NSError *)error
                      metrics:(nullable TIPImageFetchMetrics *)metrics
                        final:(BOOL)final
                       scaled:(BOOL)scaled
                  progressive:(BOOL)progressive
                      preview:(BOOL)preview
                  placeholder:(BOOL)placeholder;
- (void)_resetToImageContainer:(nullable TIPImageContainer *)imageContainer;
- (void)_cancelFetch;
- (void)_refetchWithPeek:(nullable id<TIPImageFetchRequest>)peekedRequest;
- (nullable id<TIPImageFetchRequest>)_extractRequestFromDataSource:(nullable id<TIPImageViewFetchHelperDataSource>)dataSource;
- (id<TIPImageFetchRequest>)_createRequestWithURL:(NSURL *)imageURL;
- (void)_startObservingImagePipeline:(nullable TIPImagePipeline *)pipeline;
- (void)_showDebugInfo;
- (void)_hideDebugInfo;
- (NSString *)_buildDebugInfoString:(nonnull out NSInteger *)lineCount;
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
        BOOL didTreatBackgroundingAsDisappearance:1;
    } _flags;
    NSString *_loadedImageType;
    UIColor *_debugImageHighlightColor;
    UIColor *_debugInfoTextColor;

    id _Nullable _opaqueNotificationObserver;
    NSString * _Nullable _observedPipelineIdentifier;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (void)setFetchDisappearanceBehavior:(TIPImageViewDisappearanceBehavior)fetchDisappearanceBehavior
#pragma clang diagnostic pop
{
    self.disappearanceBehavior = fetchDisappearanceBehavior;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (TIPImageViewDisappearanceBehavior)fetchDisappearanceBehavior
#pragma clang diagnostic pop
{
    return self.disappearanceBehavior;
}

- (instancetype)init
{
    return [self initWithDelegate:nil dataSource:nil];
}

- (instancetype)initWithDelegate:(nullable id<TIPImageViewFetchHelperDelegate>)delegate
                      dataSource:(nullable id<TIPImageViewFetchHelperDataSource>)dataSource
{
    if (self = [super init]) {
        [self _setDelegateInternal:delegate];
        _dataSource = dataSource;
        [self _prep];
    }
    return self;
}

- (void)dealloc
{
    if (_opaqueNotificationObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:_opaqueNotificationObserver];
    }

    [self _tearDown];
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
    [self _setDelegateInternal:delegate];
}

- (void)_setDelegateInternal:(nullable id<TIPImageViewFetchHelperDelegate>)delegate
{
    _delegate = delegate;

    // Certain callbacks are made via non-main thread and require atomic property backing
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:)]) {
        self.atomicDelegate = delegate;
    } else {
        self.atomicDelegate = nil;
    }
}

- (void)setFetchView:(nullable UIView<TIPImageFetchable> *)fetchView
{
    TIPAssert(!fetchView || [fetchView respondsToSelector:@selector(setTip_fetchedImage:)] || [fetchView respondsToSelector:@selector(setTip_fetchedImageContainer:)]);

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
    [self _cancelFetch];
    self.fetchRequest = nil;
}

- (void)clearImage
{
    [self _resetToImageContainer:nil];
}

- (void)reload
{
    [self _refetchWithPeek:nil];
}

#pragma mark Override methods

- (void)setImageAsIfLoaded:(UIImage *)image
{
    TIPImageContainer *container = (image) ? [[TIPImageContainer alloc] initWithImage:image] : nil;
    [self setImageContainerAsIfLoaded:container];
}

- (void)setImageContainerAsIfLoaded:(TIPImageContainer *)imageContainer
{
    [self cancelFetchRequest];
    [self _startObservingImagePipeline:nil];
    [self _markAsIfLoaded];
    TIPImageFetchableSetImageContainer(self.fetchView, imageContainer);
}

- (void)markAsIfLoaded
{
    if (TIPImageFetchableHasImage(self.fetchView)) {
        [self _markAsIfLoaded];
    }
}

- (void)_markAsIfLoaded
{
    _flags.isLoadedImageFinal = YES;
    _flags.isLoadedImageScaled = NO;
    _flags.isLoadedImagePreview = NO;
    _flags.isLoadedImageProgressive = NO;
    _flags.treatAsPlaceholder = NO;
}

- (void)setImageAsIfPlaceholder:(UIImage *)image
{
    TIPImageContainer *container = (image) ? [[TIPImageContainer alloc] initWithImage:image] : nil;
    [self setImageContainerAsIfPlaceholder:container];
}

- (void)setImageContainerAsIfPlaceholder:(TIPImageContainer *)imageContainer
{
    [self cancelFetchRequest];
    [self _startObservingImagePipeline:nil];
    [self _markAsIfPlaceholder];
    TIPImageFetchableSetImageContainer(self.fetchView, imageContainer);
}

- (void)markAsIfPlaceholder
{
    if (TIPImageFetchableHasImage(self.fetchView)) {
        [self _markAsIfPlaceholder];
    }
}

- (void)_markAsIfPlaceholder
{
    _flags.isLoadedImageFinal = NO;
    _flags.isLoadedImageScaled = NO;
    _flags.isLoadedImagePreview = NO;
    _flags.isLoadedImageProgressive = NO;
    _flags.treatAsPlaceholder = YES;
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
            @autoreleasepool {
                [oldOp cancel];
            }
        });
    }
    fromHelper.fetchView = nil;
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

- (void)triggerApplicationDidEnterBackground
{
    if (self.shouldTreatApplicationBackgroundAsViewDisappearance && TIPIsViewVisible(self.fetchView) && !TIPIsExtension()) {

        /**
         Call `triggerViewWillDisappear` and `triggerViewDidDisappear`, but do so async.

         This is because on app background the OS will take a snapshot of our app for previewing and resuming.
         If we run those triggers synchronously, they can yield UI changes (images being unloaded) which
         will affect the snapshot.

         Instead, dispatch async to the main queue (with a delay) and wrap the work in a background task.
         */

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIApplication *app = [NSClassFromString(@"UIApplication") performSelector:NSSelectorFromString(@"sharedApplication")];
#pragma clang diagnostic pop
        UIBackgroundTaskIdentifier bgId = [app beginBackgroundTaskWithName:@"tip.defer.unload.image"
                                                         expirationHandler:^{}];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @autoreleasepool {
                self->_flags.didTreatBackgroundingAsDisappearance = 1;
                [self triggerViewWillDisappear];
                [self triggerViewDidDisappear];
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [app endBackgroundTask:bgId];
            });
        });
    }
}

- (void)triggerApplicationWillEnterForeground
{
    if (_flags.didTreatBackgroundingAsDisappearance) {
        _flags.didTreatBackgroundingAsDisappearance = 0;
        if (TIPIsViewVisible(self.fetchView)) {
            [self triggerViewWillAppear];
            [self triggerViewDidAppear];
        }
    }
}

#pragma mark Triggers

- (void)triggerViewLayingOutSubviews
{
    [self _handleViewResizeEvent];
}

- (void)triggerViewWillDisappear
{
    _flags.transitioningAppearance = 1;
}

- (void)triggerViewDidDisappear
{
    _flags.transitioningAppearance = 0;
    switch (self.disappearanceBehavior) {
        case TIPImageViewDisappearanceBehaviorNone:
            break;
        case TIPImageViewDisappearanceBehaviorCancelImageFetch:
        {
            if (_fetchOperation) {
                [self _cancelFetch];
                _flags.didCancelOnDisapper = 1;
            }
            break;
        }
        case TIPImageViewDisappearanceBehaviorLowerImageFetchPriority:
        {
            if (_fetchOperation) {
                _priorPriority = _fetchOperation.priority;
                _fetchOperation.priority = NSOperationQueuePriorityVeryLow + 2;
                _flags.didChangePriorityOnDisappear = 1;
            }
            break;
        }
        case TIPImageViewDisappearanceBehaviorUnload:
        {
            if (_fetchRequest != nil) {
                // Unload
                [self _resetToImageContainer:nil];
            }
            break;
        }
        case TIPImageViewDisappearanceBehaviorReplaceWithPlaceholder:
        {
            if (_fetchRequest != nil) {
                // Replace with a Placeholder
                UIView<TIPImageFetchable> *fetchView = self.fetchView;

                // 1) get the placeholder
                static const CGFloat kPlaceholderDimension = 180.0;
                TIPImageContainer *placeholder = TIPImageFetchableGetImageContainer(fetchView);
                if (placeholder.dimensions.width > kPlaceholderDimension || placeholder.dimensions.height > kPlaceholderDimension) {
                    placeholder = [placeholder scaleToTargetDimensions:CGSizeMake(kPlaceholderDimension, kPlaceholderDimension)
                                                           contentMode:UIViewContentModeScaleAspectFit];
                }

                // 2) unload the image
                [self _resetToImageContainer:nil];

                // 3) set the placeholder
                TIPImageFetchableSetImageContainer(fetchView, placeholder);
                [self markAsIfPlaceholder];
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
            [self _startObservingImagePipeline:nil];
            [self _refetchWithPeek:nil];
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

+ (void)notifyAllFetchHelpersToRetryFailedLoads
{
    tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kRetryFailedLoadsNotification
                                                            object:nil
                                                          userInfo:nil];
    });
}

@end

@implementation TIPImageViewFetchHelper (Events)

#pragma mark Events

- (BOOL)_shouldUpdateImageWithResult:(id<TIPImageFetchResult>)previewImageResult
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldUpdateImageWithPreviewImageResult:)]) {
        return [delegate tip_fetchHelper:self
                         shouldUpdateImageWithPreviewImageResult:previewImageResult];
    }
    return NO;
}

- (BOOL)_shouldContinueLoadingWithResult:(id<TIPImageFetchResult>)previewImageResult
{
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

- (BOOL)_shouldLoadProgressivelyWithIdentifier:(NSString *)identifier
                                      imageURL:(NSURL *)URL
                                     imageType:(NSString *)imageType
                            originalDimensions:(CGSize)originalDimensions
{
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

- (BOOL)_shouldReloadAfterDifferentFetchCompletedWithImageContainer:(TIPImageContainer *)imageContainer
                                                         dimensions:(CGSize)dimensions
                                                         identifier:(NSString *)identifier
                                                           imageURL:(NSURL *)URL
                                               treatedAsPlaceholder:(BOOL)placeholder
                                                     manuallyStored:(BOOL)manuallyStored
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldReloadAfterDifferentFetchCompletedWithImageContainer:dimensions:identifier:URL:treatedAsPlaceholder:manuallyStored:)]) {
        return [delegate tip_fetchHelper:self
                         shouldReloadAfterDifferentFetchCompletedWithImageContainer:imageContainer
                         dimensions:dimensions
                         identifier:identifier
                         URL:URL
                         treatedAsPlaceholder:placeholder
                         manuallyStored:manuallyStored];
    } else if ([delegate respondsToSelector:@selector(tip_fetchHelper:shouldReloadAfterDifferentFetchCompletedWithImage:dimensions:identifier:URL:treatedAsPlaceholder:manuallyStored:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return [delegate tip_fetchHelper:self
                         shouldReloadAfterDifferentFetchCompletedWithImage:imageContainer.image
                         dimensions:dimensions
                         identifier:identifier
                         URL:URL
                         treatedAsPlaceholder:placeholder
                         manuallyStored:manuallyStored];
#pragma clang diagnostic pop
    }

    id<TIPImageFetchRequest> request = self.fetchRequest;
    if (!TIPImageFetchableHasImage(self.fetchView) && [request.imageURL isEqual:URL]) {
        // auto handle when the image loaded someplace else
        return YES;
    }

    if (self.fetchedImageTreatedAsPlaceholder && !placeholder) {
        // take the non-placeholder over the placeholder
        return YES;
    }

    return NO;
}

- (void)_didStartLoading
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelperDidStartLoading:)]) {
        [delegate tip_fetchHelperDidStartLoading:self];
    }
}

- (void)_didUpdateProgress:(float)progress
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didUpdateProgress:)]) {
        [delegate tip_fetchHelper:self didUpdateProgress:progress];
    }
}

- (void)_didUpdateDisplayedImageContainer:(TIPImageContainer *)imageContainer
                         sourceDimensions:(CGSize)sourceDimensions
                                  isFinal:(BOOL)isFinal
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didUpdateDisplayedImageContainer:fromSourceDimensions:isFinal:)]) {
        [delegate tip_fetchHelper:self
 didUpdateDisplayedImageContainer:imageContainer
             fromSourceDimensions:sourceDimensions
                          isFinal:isFinal];
    } else if ([delegate respondsToSelector:@selector(tip_fetchHelper:didUpdateDisplayedImage:fromSourceDimensions:isFinal:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [delegate tip_fetchHelper:self
          didUpdateDisplayedImage:imageContainer.image
             fromSourceDimensions:sourceDimensions
                          isFinal:isFinal];
#pragma clang diagnostic pop
    }
}

- (void)_didLoadFinalImageFromSource:(TIPImageLoadSource)source
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didLoadFinalImageFromSource:)]) {
        [delegate tip_fetchHelper:self didLoadFinalImageFromSource:source];
    }
}

- (void)_didFailToLoadFinalImageWithError:(NSError *)error
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelper:didFailToLoadFinalImage:)]) {
        [delegate tip_fetchHelper:self didFailToLoadFinalImage:error];
    }
}

- (void)_didReset
{
    id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tip_fetchHelperDidReset:)]) {
        [delegate tip_fetchHelperDidReset:self];
    }
}

@end

@implementation TIPImageViewFetchHelper (TIPImageFetchDelegate)

#pragma mark Fetch Delegate

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
       didLoadDirtyPreviewImage:(id<TIPImageFetchResult>)result
{
    if (op != _fetchOperation) {
        return;
    }

    const BOOL shouldUpdate = [self _shouldUpdateImageWithResult:result];
    if (shouldUpdate) {
        [self _updateImageContainer:result.imageContainer
                   sourceDimensions:result.imageOriginalDimensions
                                URL:result.imageURL
                             source:result.imageSource
                               type:nil
                           progress:0.f
                              error:nil
                            metrics:nil
                              final:NO
                             scaled:NO
                        progressive:NO
                            preview:YES
                        placeholder:!!result.imageIsTreatedAsPlaceholder];
    }
}

- (void)tip_imageFetchOperationDidStart:(TIPImageFetchOperation *)op
{
    if (op != _fetchOperation) {
        return;
    }

    [self _didStartLoading];
    [self setDebugInfoNeedsUpdate];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
            didLoadPreviewImage:(id<TIPImageFetchResult>)previewResult
                     completion:(TIPImageFetchDidLoadPreviewCallback)completion
{
    BOOL continueLoading = (op == _fetchOperation);
    if (continueLoading) {
        const BOOL shouldUpdate = [self _shouldUpdateImageWithResult:previewResult];
        if (shouldUpdate) {
            continueLoading = !![self _shouldContinueLoadingWithResult:previewResult];

            [self _updateImageContainer:previewResult.imageContainer
                       sourceDimensions:previewResult.imageOriginalDimensions
                                    URL:previewResult.imageURL
                                 source:previewResult.imageSource
                                   type:nil
                               progress:(continueLoading) ? 0.f : 1.f
                                  error:nil
                                metrics:(continueLoading) ? nil : op.metrics
                                  final:!continueLoading
                                 scaled:!continueLoading
                            progressive:NO
                                preview:continueLoading
                            placeholder:!!previewResult.imageIsTreatedAsPlaceholder];
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

    return [self _shouldLoadProgressivelyWithIdentifier:identifier
                                               imageURL:URL
                                              imageType:imageType
                                     originalDimensions:originalDimensions];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
      didUpdateProgressiveImage:(id<TIPImageFetchResult>)progressiveResult
                       progress:(float)progress
{
    if (op != _fetchOperation) {
        return;
    }

    [self _updateImageContainer:progressiveResult.imageContainer
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

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
 didLoadFirstAnimatedImageFrame:(id<TIPImageFetchResult>)progressiveResult
                       progress:(float)progress
{
    if (op != _fetchOperation) {
        return;
    }

    [self _updateImageContainer:progressiveResult.imageContainer
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
    [self _didUpdateProgress:progress];
    [self setDebugInfoNeedsUpdate];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFinalImage:(id<TIPImageFetchResult>)finalResult
{
    if (op != _fetchOperation) {
        return;
    }

    TIPImageContainer *imageContainer = finalResult.imageContainer;

    _fetchOperation = nil;
    [self _updateImageContainer:imageContainer
               sourceDimensions:finalResult.imageOriginalDimensions
                            URL:finalResult.imageURL
                         source:finalResult.imageSource
                           type:op.networkLoadImageType
                       progress:1.f
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
        [self _didFailToLoadFinalImageWithError:error];
    }
    [self setDebugInfoNeedsUpdate];
}

- (void)tip_imageFetchOperation:(nonnull TIPImageFetchOperation *)op
    willAttemptToLoadFromSource:(TIPImageLoadSource)source
{
    if (op != _fetchOperation) {
        return;
    }

    if (source >= TIPImageLoadSourceNetwork) {
        id<TIPImageViewFetchHelperDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(tip_fetchHelperDidStartLoadingFromNetwork:)]) {
            [delegate tip_fetchHelperDidStartLoadingFromNetwork:self];
        }
    }
}

@end

@implementation TIPImageViewFetchHelper (Private)

- (void)_tearDown
{
    [self _cancelFetch];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self
                  name:TIPImageViewDidUpdateDebugInfoVisibilityNotification
                object:nil];
    [nc removeObserver:self
                  name:kRetryFailedLoadsNotification
                object:nil];

    if (_opaqueNotificationObserver) {
        [nc removeObserver:_opaqueNotificationObserver];
    }

    [_debugInfoView removeFromSuperview];
}

- (void)_prep
{
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
    _disappearanceBehavior = TIPImageViewDisappearanceBehaviorUnload;
    _shouldTreatApplicationBackgroundAsViewDisappearance = NO;
    [self _resetToImageContainer:nil];
}

- (void)_handleViewResizeEvent
{
    if (!self.fetchRequest || [self _resizeRequestIfNeeded]) {
        id<TIPImageFetchRequest> peekRequest = nil;
        if (_flags.isLoadedImageFinal) {
            // downgrade what we have from being "final" to a "preview"
            _flags.isLoadedImageFinal = 0;
            _flags.isLoadedImagePreview = 1;
            [self _cancelFetch];
        } else if (_fetchOperation) {
            id<TIPImageViewFetchHelperDataSource> dataSource = self.dataSource;
            peekRequest = [self _extractRequestFromDataSource:dataSource];

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
        [self _refetchWithPeek:peekRequest];
    }
}

- (BOOL)_resizeRequestIfNeeded
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

- (void)_updateImageContainer:(nullable TIPImageContainer *)imageContainer
             sourceDimensions:(CGSize)sourceDimensions
                          URL:(nullable NSURL *)URL
                       source:(TIPImageLoadSource)source
                         type:(nullable NSString *)type
                     progress:(float)progress
                        error:(nullable NSError *)error
                      metrics:(nullable TIPImageFetchMetrics *)metrics
                        final:(BOOL)final
                       scaled:(BOOL)scaled
                  progressive:(BOOL)progressive
                      preview:(BOOL)preview
                  placeholder:(BOOL)placeholder
{
    if (gTwitterImagePipelineAssertEnabled) {
        TIPAssertMessage((0b11111110 & final) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & preview) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & progressive) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & scaled) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
        TIPAssertMessage((0b11111110 & placeholder) == 0b0, @"Cannot set a 1-bit flag with a BOOL that isn't 1 bit");
    }

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
    if (metrics && imageContainer) {
        self.fetchResultDimensions = sourceDimensions;
    } else {
        self.fetchResultDimensions = CGSizeZero;
    }
    BOOL didUpdateProgress = NO;
    const float oldProgress = self.fetchProgress;
    if ((progress > oldProgress) || (progress == oldProgress && oldProgress > 0.f) || !self.didLoadAny) {
        self.fetchProgress = progress;
        didUpdateProgress = YES;
    }
    TIPImageFetchableSetImageContainer(self.fetchView, imageContainer);
    if (didUpdateProgress) {
        [self _didUpdateProgress:progress];
    }
    if (imageContainer) {
        [self _didUpdateDisplayedImageContainer:imageContainer
                               sourceDimensions:sourceDimensions
                                        isFinal:(final || scaled)];
    }
    if (final || scaled) {
        [self _didLoadFinalImageFromSource:source];
    }
    if (!self.didLoadAny) {
        [self _didReset];
    }
    [self setDebugInfoNeedsUpdate];
}

- (void)_resetToImageContainer:(nullable TIPImageContainer *)imageContainer
{
    [self _cancelFetch];
    [self _startObservingImagePipeline:nil];
    [self _updateImageContainer:imageContainer
               sourceDimensions:CGSizeZero
                            URL:nil
                         source:TIPImageLoadSourceUnknown
                           type:nil
                       progress:(imageContainer != nil) ? 1.f : 0.f
                          error:nil
                        metrics:nil
                          final:NO
                         scaled:NO
                    progressive:NO
                        preview:NO
                    placeholder:NO];
}

- (void)_cancelFetch
{
    [_fetchOperation cancelAndDiscardDelegate];
    _fetchOperation = nil;
}

- (void)_refetchWithPeek:(nullable id<TIPImageFetchRequest>)peekedRequest
{
    if (!_fetchOperation) {
        UIView<TIPImageFetchable> *fetchView = self.fetchView;
        if (TIPIsViewVisible(fetchView) || _flags.transitioningAppearance) {
            const CGSize size = fetchView.bounds.size;
            if (size.width > 0 && size.height > 0) {
                if (!TIPImageFetchableHasImage(fetchView) || !_flags.isLoadedImageFinal) {
                    id<TIPImageViewFetchHelperDataSource> dataSource = self.dataSource;

                    // Attempt static load first

                    if ([dataSource respondsToSelector:@selector(tip_imageContainerForFetchHelper:)]) {
                        TIPImageContainer *container = [dataSource tip_imageContainerForFetchHelper:self];
                        if (container) {
                            [self setImageContainerAsIfLoaded:container];
                            return;
                        }
                    }

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
                        request = [self _extractRequestFromDataSource:dataSource];
                    }

                    if (request && [dataSource respondsToSelector:@selector(tip_imagePipelineForFetchHelper:)]) {
                        self.fetchRequest = request;
                        TIPImagePipeline *pipeline = [dataSource tip_imagePipelineForFetchHelper:self];

                        if (!pipeline) {
                            self.fetchRequest = nil;
                            return;
                        }

                        _fetchOperation = [pipeline operationWithRequest:request
                                                                 context:nil
                                                                delegate:self];
                        if ([dataSource respondsToSelector:@selector(tip_fetchOperationPriorityForFetchHelper:)]) {
                            const NSOperationQueuePriority priority = [dataSource tip_fetchOperationPriorityForFetchHelper:self];
                            _fetchOperation.priority = priority;
                        }
                        [self _startObservingImagePipeline:pipeline];
                        [pipeline fetchImageWithOperation:_fetchOperation];
                    }
                }
            }
        }
    }
}

- (nullable id<TIPImageFetchRequest>)_extractRequestFromDataSource:(nullable id<TIPImageViewFetchHelperDataSource>)dataSource
{
    id<TIPImageFetchRequest> request = nil;
    if (!request && [dataSource respondsToSelector:@selector(tip_imageFetchRequestForFetchHelper:)]) {
        request = [dataSource tip_imageFetchRequestForFetchHelper:self];
    }
    if (!request && [dataSource respondsToSelector:@selector(tip_imageURLForFetchHelper:)]) {
        NSURL *imageURL = [dataSource tip_imageURLForFetchHelper:self];
        if (imageURL) {
            request = [self _createRequestWithURL:imageURL];
        }
    }
    return request;
}

- (id<TIPImageFetchRequest>)_createRequestWithURL:(NSURL *)imageURL
{
    return [[TIPImageViewSimpleFetchRequest alloc] initWithImageURL:imageURL targetView:self.fetchView];
}

- (void)_startObservingImagePipeline:(nullable TIPImagePipeline *)pipeline
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (!_opaqueNotificationObserver) {
        __weak typeof(self) weakSelf = self;
        _opaqueNotificationObserver = [nc addObserverForName:TIPImagePipelineDidStoreCachedImageNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            [weakSelf _tip_imageDidUpdate:note];
        }];
    }

    // save the pipeline identifier for use in `_tip_imageDidUpdate:`
    _observedPipelineIdentifier = [[pipeline identifier] copy];
}

- (void)_tip_imageDidUpdate:(NSNotification *)note
{
    if (!_fetchOperation) {
        if (![[note object] isKindOfClass:TIPImagePipeline.class]) {
            return;
        }
        TIPImagePipeline *pipeline = note.object;

        id<TIPImageFetchRequest> request = self.fetchRequest;
        NSString *requestIdentifier = TIPImageFetchRequestGetImageIdentifier(request);

        NSDictionary *userInfo = note.userInfo;
        NSString *identifier = userInfo[TIPImagePipelineImageIdentifierNotificationKey];

        if ([requestIdentifier isEqualToString:identifier] && [pipeline.identifier isEqualToString:_observedPipelineIdentifier]) {

            const BOOL manuallyStored = [userInfo[TIPImagePipelineImageWasManuallyStoredNotificationKey] boolValue];
            const BOOL placeholder = [userInfo[TIPImagePipelineImageTreatAsPlaceholderNofiticationKey] boolValue];
            NSURL *URL = userInfo[TIPImagePipelineImageURLNotificationKey];
            CGSize dimensions = [(NSValue *)userInfo[TIPImagePipelineImageDimensionsNotificationKey] CGSizeValue];
            TIPImageContainer *container = userInfo[TIPImagePipelineImageContainerNotificationKey];

            const BOOL shouldReload = [self _shouldReloadAfterDifferentFetchCompletedWithImageContainer:container
                                                                                             dimensions:dimensions
                                                                                             identifier:identifier
                                                                                               imageURL:URL
                                                                                   treatedAsPlaceholder:placeholder
                                                                                         manuallyStored:manuallyStored];
            if (shouldReload) {
                UIView<TIPImageFetchable> *fetchView = self.fetchView;
                if (!TIPIsViewVisible(fetchView)) {
                    _flags.didCancelOnDisapper = 1;
                }
                [self _cancelFetch];
                [self _startObservingImagePipeline:nil];
                _flags.isLoadedImageFinal = 0;
                tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
                    // Dirty the render cache, but async so other render cache stores can complete first
                    [[TIPGlobalConfiguration sharedInstance] dirtyAllRenderedMemoryCacheImagesWithIdentifier:identifier];
                    // Async refetch
                    [self _refetchWithPeek:nil];
                });
            }
        }
    }
}

- (void)_tip_didUpdateDebugVisibility
{
    if ([TIPImageViewFetchHelper isDebugInfoVisible]) {
        [self _showDebugInfo];
    } else {
        [self _hideDebugInfo];
    }
}

- (void)_showDebugInfo
{
    if (_debugInfoView != nil) {
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

    _debugInfoView = label;
    [fetchView addSubview:_debugInfoView];
    [self setDebugInfoNeedsUpdate];
}

- (void)_hideDebugInfo
{
    [_debugInfoView removeFromSuperview];
    _debugInfoView = nil;
}

- (NSString *)_buildDebugInfoString:(nonnull out NSInteger *)lineCount
{
    NSArray<NSString *> *infos = [self debugInfoStrings];
    NSString *debugInfoString = [infos componentsJoinedByString:@"\n"];
    *lineCount = (NSInteger)infos.count;
    return debugInfoString;
}

#pragma mark Retry Event

- (void)_tip_retryFailedLoadsNotification:(NSNotification *)note
{
    if (self.fetchError != nil && !self.isLoading) {
        [self _refetchWithPeek:nil];
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
        NSString *info = [self _buildDebugInfoString:&lineCount];
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
