//
//  TIPImageView.m
//  TwitterImagePipeline
//
//  Created on 3/19/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <objc/runtime.h>
#import "TIPImageView.h"
#import "TIPImageViewFetchHelper.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TIPImageView

- (instancetype)initWithFetchHelper:(nullable TIPImageViewFetchHelper *)fetchHelper
{
    if (self = [super init]) {
        [self _tip_setFetchHelper:fetchHelper];
    }
    return self;
}

- (void)_tip_setFetchHelper:(nullable TIPImageViewFetchHelper *)fetchHelper
{
    if (_fetchHelper != fetchHelper) {
        TIPImageViewFetchHelper *oldFetchHelper = _fetchHelper;
        _fetchHelper = fetchHelper;
        [TIPImageViewFetchHelper transitionView:self fromFetchHelper:oldFetchHelper toFetchHelper:fetchHelper];
    }
}

- (void)setFetchHelper:(nullable TIPImageViewFetchHelper *)fetchHelper
{
    [self _tip_setFetchHelper:fetchHelper];
}

#pragma mark Visibility Change

- (void)willMoveToWindow:(nullable UIWindow *)newWindow
{
    [self.fetchHelper viewWillMoveToWindow:newWindow];
}

- (void)didMoveToWindow
{
    [self.fetchHelper viewDidMoveToWindow];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self.fetchHelper triggerViewLayingOutSubviews];
}

@end

// Contribution c/o Brandon Carpenter

#pragma mark -

/**
 Observes layout and visibilty events of the view heirarchy and forwards to the `fetchHelper`.
 */
@interface TIPImageViewObserver : UIView
@property (nullable, nonatomic) TIPImageViewFetchHelper *fetchHelper;
@end

#pragma mark -

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
    TIPImageViewObserver *observer = objc_getAssociatedObject(self, _cmd);
    if (!observer) {
        observer = [[TIPImageViewObserver alloc] initWithFrame:self.bounds];
        observer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:observer];
        objc_setAssociatedObject(self, _cmd, observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return observer;
}

@end

#pragma mark -

@implementation TIPImageViewObserver

+ (Class)layerClass
{
    return [CATransformLayer class];
}

- (void)willMoveToWindow:(nullable UIWindow *)newWindow
{
    [self.fetchHelper viewWillMoveToWindow:newWindow];
}

- (void)didMoveToWindow
{
    [self.fetchHelper viewDidMoveToWindow];
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

@end

NS_ASSUME_NONNULL_END
