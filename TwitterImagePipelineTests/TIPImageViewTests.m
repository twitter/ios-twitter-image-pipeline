//
//  TIPImageViewTests.m
//  TwitterImagePipeline
//
//  Created on 4/3/17.
//  Copyright © 2020 Twitter, Inc. All rights reserved.
//

#import "TIPImageViewFetchHelper.h"
#import "UIView+TIPImageFetchable.h"

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

- (void)testImageViewHidden
{
    // Visible from set up
    XCTAssertEqual(self.fetchHelper.triggerViewWillAppearCount, 1);
    XCTAssertEqual(self.fetchHelper.triggerViewDidAppearCount, 1);
    XCTAssertEqual(self.fetchHelper.triggerViewWillDisappearCount, 0);
    XCTAssertEqual(self.fetchHelper.triggerViewDidDisappearCount, 0);

    // Hide
    self.imageView.hidden = YES;
    XCTAssertEqual(self.fetchHelper.triggerViewWillAppearCount, 1);
    XCTAssertEqual(self.fetchHelper.triggerViewDidAppearCount, 1);
    XCTAssertEqual(self.fetchHelper.triggerViewWillDisappearCount, 1);
    XCTAssertEqual(self.fetchHelper.triggerViewDidDisappearCount, 1);

    // Show
    self.imageView.hidden = NO;
    XCTAssertEqual(self.fetchHelper.triggerViewWillAppearCount, 2);
    XCTAssertEqual(self.fetchHelper.triggerViewDidAppearCount, 2);
    XCTAssertEqual(self.fetchHelper.triggerViewWillDisappearCount, 1);
    XCTAssertEqual(self.fetchHelper.triggerViewDidDisappearCount, 1);
}

@end
