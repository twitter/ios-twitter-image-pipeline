//
//  UIImageView+TIPImageViewFetchHelper.m
//  TwitterImagePipeline
//
//  Created on 3/19/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <objc/runtime.h>
#import "TIP_Project.h"
#import "TIPImageViewFetchHelper.h"
#import "UIImageView+TIPImageViewFetchHelper.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Observes layout and visibilty events of the view heirarchy and forwards to the `fetchHelper`.
 */
@interface TIPImageViewObserver : UIView
@property (nullable, nonatomic) TIPImageViewFetchHelper *fetchHelper;
@end

#pragma mark -

static const char sTIPImageViewObserverKey[] = "TIPImageViewObserverKey";

@implementation UIImageView (TIPImageViewFetchHelper)

- (void)setTip_fetchHelper:(nullable TIPImageViewFetchHelper *)fetchHelper
{
    TIPImageViewObserver *observer = self.tip_imageViewObserver;
    TIPImageViewFetchHelper *oldFetchHelper = observer.fetchHelper;
    observer.fetchHelper = fetchHelper;
    [TIPImageViewFetchHelper transitionView:self fromFetchHelper:oldFetchHelper toFetchHelper:fetchHelper];
}

- (nullable TIPImageViewFetchHelper *)tip_fetchHelper
{
    return self.tip_imageViewObserver.fetchHelper;
}

- (TIPImageViewObserver *)tip_imageViewObserver
{
    TIPImageViewObserver *observer = objc_getAssociatedObject(self, sTIPImageViewObserverKey);
    if (!observer) {
        observer = [[TIPImageViewObserver alloc] initWithFrame:self.bounds];
        observer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:observer];
        objc_setAssociatedObject(self, sTIPImageViewObserverKey, observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return observer;
}

- (void)_tip_clearImageViewObserver:(nonnull TIPImageViewObserver *)observer
{
    if (observer == objc_getAssociatedObject(self, sTIPImageViewObserverKey)) {
        objc_setAssociatedObject(self, sTIPImageViewObserverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

@end

#pragma mark -

@implementation TIPImageViewObserver
{
    BOOL _didGetAddedToSuperview;
    BOOL _observingSuperview;
}

- (void)dealloc
{
    TIPAssert(!_observingSuperview);
    if (_observingSuperview) {
        _observingSuperview = NO;
        [self.superview removeObserver:self forKeyPath:@"hidden"];
    }
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
        [newSuperview addObserver:self forKeyPath:@"hidden" options:NSKeyValueObservingOptionPrior context:NULL];
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
        NSNumber *prior = change[NSKeyValueChangeNotificationIsPriorKey];
        if (prior.boolValue) {
            [self.fetchHelper triggerViewWillChangeHidden];
        } else {
            [self.fetchHelper triggerViewDidChangeHidden];
        }
    }
}

@end

NS_ASSUME_NONNULL_END
