//
//  TIPImageView.m
//  TwitterImagePipeline
//
//  Created on 3/19/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIPImageView.h"
#import "TIPImageViewFetchHelper.h"

@implementation TIPImageView

- (instancetype)initWithFetchHelper:(TIPImageViewFetchHelper *)fetchHelper
{
    if (self = [super init]) {
        [self _tip_setFetchHelper:fetchHelper];
    }
    return self;
}

- (void)_tip_setFetchHelper:(TIPImageViewFetchHelper *)fetchHelper
{
    if (_fetchHelper != fetchHelper) {
        TIPImageViewFetchHelper *oldFetchHelper = _fetchHelper;
        _fetchHelper = fetchHelper;
        [TIPImageViewFetchHelper transitionView:self fromFetchHelper:oldFetchHelper toFetchHelper:fetchHelper];
    }
}

- (void)setFetchHelper:(TIPImageViewFetchHelper *)fetchHelper
{
    [self _tip_setFetchHelper:fetchHelper];
}

#pragma mark Visibility Change

- (void)willMoveToWindow:(UIWindow *)newWindow
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
