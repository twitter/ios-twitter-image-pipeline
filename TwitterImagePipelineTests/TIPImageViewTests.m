//
//  TIPImageViewTests.m
//  TwitterImagePipeline
//
//  Created by Brandon Carpenter on 4/3/17.
//  Copyright © 2017 Twitter, Inc. All rights reserved.
//

#import "TIPImageView.h"
#import "TIPImageViewFetchHelper.h"

@import XCTest;

#pragma mark -

@interface TestEventRecordingFetchHelper : TIPImageViewFetchHelper
@property (nonatomic, readonly) NSInteger triggerViewWillDisappearCount;
@property (nonatomic, readonly) NSInteger triggerViewDidDisappearCount;
@property (nonatomic, readonly) NSInteger triggerViewWillAppearCount;
@property (nonatomic, readonly) NSInteger triggerViewDidAppearCount;
@property (nonatomic, readonly) NSInteger triggerViewLayingOutSubviewsCount;
@end

@implementation TestEventRecordingFetchHelper

- (void)triggerViewWillDisappear
{
    _triggerViewWillDisappearCount++;
    [super triggerViewWillDisappear];
}

- (void)triggerViewDidDisappear
{
    _triggerViewDidDisappearCount++;
    [super triggerViewDidDisappear];
}

- (void)triggerViewWillAppear
{
    _triggerViewWillAppearCount++;
    [super triggerViewWillAppear];
}

- (void)triggerViewDidAppear
{
    _triggerViewDidAppearCount++;
    [super triggerViewDidAppear];
}

- (void)triggerViewLayingOutSubviews
{
    _triggerViewLayingOutSubviewsCount++;
    [super triggerViewLayingOutSubviews];
}

@end

#pragma mark -

@interface UIImageView_TIPImageViewFetchHelperTest : XCTestCase
@property (nonatomic) UIWindow *window;
@property (nonatomic) UIImageView *imageView;
@property (nonatomic) TestEventRecordingFetchHelper *fetchHelper;
@end

@implementation UIImageView_TIPImageViewFetchHelperTest

- (void)setUp
{
    [super setUp];
    TestEventRecordingFetchHelper *fetchHelper = [[TestEventRecordingFetchHelper alloc] init];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 300.0, 300.0)];
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(50.0, 50.0, 50.0, 50.0)];
    imageView.tip_fetchHelper = fetchHelper;
    [window addSubview:imageView];
    self.window = window;
    self.imageView = imageView;
    self.fetchHelper = fetchHelper;
}

- (void)tearDown
{
    self.window = nil;
    self.imageView = nil;
    self.fetchHelper = nil;
    [super tearDown];
}

- (void)testImageViewBecameVisible
{
    // Image view became visible during setUp.
    XCTAssertEqual(self.fetchHelper.triggerViewWillAppearCount, 1);
    XCTAssertEqual(self.fetchHelper.triggerViewDidAppearCount, 1);
}

- (void)testImageViewBecameInvisible
{
    [self.imageView removeFromSuperview];
    XCTAssertEqual(self.fetchHelper.triggerViewWillDisappearCount, 1);
    XCTAssertEqual(self.fetchHelper.triggerViewDidDisappearCount, 1);
}

- (void)testImageViewResized
{
    self.imageView.frame = CGRectMake(50.0, 50.0, 200.0, 200.0);
    [self.imageView layoutIfNeeded];
    XCTAssertEqual(self.fetchHelper.triggerViewLayingOutSubviewsCount, 1);
}

@end
