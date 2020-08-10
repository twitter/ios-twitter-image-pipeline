//
//  UIView+TIPImageFetchable.m
//  TwitterImagePipeline
//
//  Created on 3/19/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <objc/runtime.h>
#import "TIP_Project.h"
#import "TIPImageViewFetchHelper.h"
#import "UIView+TIPImageFetchable.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Observes layout and visibilty events of the view heirarchy and forwards to the `fetchHelper`.
 */
TIP_OBJC_FINAL TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageViewObserver : UIView
@property (nullable, nonatomic) TIPImageViewFetchHelper *fetchHelper;
@end

#pragma mark -

static const char sTIPImageFetchableViewObserverKey[] = "TIPImageFetchableViewObserverKey";

@implementation UIView (TIPImageFetchable)

- (void)setTip_fetchHelper:(nullable TIPImageViewFetchHelper *)fetchHelper
{
    TIPAssert([self respondsToSelector:@selector(setTip_fetchedImage:)] || [self respondsToSelector:@selector(setTip_fetchedImageContainer:)]);
    TIPAssert([self respondsToSelector:@selector(tip_fetchedImage)] || [self respondsToSelector:@selector(tip_fetchedImageContainer)]);
    if (![self respondsToSelector:@selector(setTip_fetchedImage:)] && ![self respondsToSelector:@selector(setTip_fetchedImageContainer:)]) {
        return;
    }
    if (![self respondsToSelector:@selector(tip_fetchedImage)] && ![self respondsToSelector:@selector(tip_fetchedImageContainer)]) {
        return;
    }

    TIPImageViewObserver *observer = self.tip_imageViewObserver;
    TIPImageViewFetchHelper *oldFetchHelper = observer.fetchHelper;
    observer.fetchHelper = fetchHelper;
    [TIPImageViewFetchHelper transitionView:(UIView<TIPImageFetchable> *)self
                            fromFetchHelper:oldFetchHelper
                              toFetchHelper:fetchHelper];
}

- (nullable TIPImageViewFetchHelper *)tip_fetchHelper
{
    return self.tip_imageViewObserver.fetchHelper;
}

- (TIPImageViewObserver *)tip_imageViewObserver
{
    TIPImageViewObserver *observer = objc_getAssociatedObject(self, sTIPImageFetchableViewObserverKey);
    if (!observer) {
        observer = [[TIPImageViewObserver alloc] initWithFrame:self.bounds];
        observer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:observer];
        objc_setAssociatedObject(self, sTIPImageFetchableViewObserverKey, observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return observer;
}

- (void)_tip_clearImageViewObserver:(nonnull TIPImageViewObserver *)observer
{
    if (observer == objc_getAssociatedObject(self, sTIPImageFetchableViewObserverKey)) {
        objc_setAssociatedObject(self, sTIPImageFetchableViewObserverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

@end

#pragma mark -

@implementation UIImageView (TIPImageFetchable)

- (nullable UIImage *)tip_fetchedImage
{
    return self.image;
}

- (void)setTip_fetchedImage:(nullable UIImage *)image
{
    self.image = image;
}

@end

#pragma mark -

@implementation TIPImageViewObserver
{
    BOOL _didGetAddedToSuperview;
    BOOL _observingSuperview;
    id _appBackgroundObserver;
    id _appForegroundObserver;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self _prep];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super initWithCoder:coder]) {
        [self _prep];
    }
    return self;
}

- (void)_prep TIP_OBJC_DIRECT
{
    __unsafe_unretained typeof(self) unsafeSelf = self;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    _appForegroundObserver = [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                                             object:nil
                                              queue:[NSOperationQueue mainQueue]
                                         usingBlock:^(NSNotification * _Nonnull note) {
        [unsafeSelf.fetchHelper triggerApplicationWillEnterForeground];
    }];
    _appBackgroundObserver = [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                                             object:nil
                                              queue:[NSOperationQueue mainQueue]
                                         usingBlock:^(NSNotification * _Nonnull note) {
        [unsafeSelf.fetchHelper triggerApplicationDidEnterBackground];
    }];
}

- (void)dealloc
{
    TIPAssert(!_observingSuperview);
    if (_observingSuperview) {
        _observingSuperview = NO;
        [self.superview removeObserver:self forKeyPath:@"hidden"];
    }
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:_appForegroundObserver];
    [nc removeObserver:_appBackgroundObserver];
}

+ (Class)layerClass
{
    return [CATransformLayer class];
}

- (void)setOpaque:(BOOL)opaque
{
    // Opacity is not supported by CATransformLayer
}

- (void)setBackgroundColor:(nullable UIColor *)backgroundColor
{
    // Background color is not supported by CATransformLayer
}

- (void)willMoveToWindow:(nullable UIWindow *)newWindow
{
    [self.fetchHelper triggerViewWillMoveToWindow:newWindow];
}

- (void)didMoveToWindow
{
    [self.fetchHelper triggerViewDidMoveToWindow];
}

- (void)willMoveToSuperview:(nullable UIImageView *)newSuperview
{
    UIImageView *oldSuperview = (id)self.superview;
    if (oldSuperview && _observingSuperview) {
        _observingSuperview = NO;
        [oldSuperview removeObserver:self forKeyPath:@"hidden"];
        [oldSuperview _tip_clearImageViewObserver:self];
    }
    if (newSuperview && !_didGetAddedToSuperview) {
        _observingSuperview = YES;
        [newSuperview addObserver:self
                       forKeyPath:@"hidden"
                          options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
                          context:NULL];
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self.fetchHelper triggerViewLayingOutSubviews];
}

- (nullable UIView *)hitTest:(CGPoint)point withEvent:(nullable UIEvent *)event
{
    return nil;
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey,id> *)change context:(nullable void *)context
{
    if ([keyPath isEqualToString:@"hidden"]) {
        TIPAssert(object == self.superview);
        const BOOL wasHidden = [change[NSKeyValueChangeOldKey] boolValue];
        const BOOL willHide = [change[NSKeyValueChangeNewKey] boolValue];
        if (wasHidden == willHide) {
            // no change
            return;
        }

        UIView *view = object;
        if (view.window == nil) {
            // no window -- won't actually appear then
            return;
        }

        if (willHide) {
            [self.fetchHelper triggerViewWillDisappear];
            [self.fetchHelper triggerViewDidDisappear];
        } else /* will show */ {
            [self.fetchHelper triggerViewWillAppear];
            [self.fetchHelper triggerViewDidAppear];
        }
    }
}

@end

NS_ASSUME_NONNULL_END
