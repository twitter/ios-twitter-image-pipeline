//
//  ZoomingTweetImageViewController.m
//  TwitterImagePipeline
//
//  Created on 2/11/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterImagePipeline.h>

#import "AppDelegate.h"
#import "TweetImageFetchRequest.h"
#import "TwitterAPI.h"
#import "ZoomingTweetImageViewController.h"

@interface ZoomingTweetImageViewController () <UIScrollViewDelegate, TIPImageFetchDelegate>
@property (nonatomic, readonly) TweetImageInfo *tweetImageInfo;
@end

@implementation ZoomingTweetImageViewController
{
    UIScrollView *_scrollView;
    UIImageView *_imageView;
    UIProgressView *_progressView;
    UITapGestureRecognizer *_doubleTapGuestureRecognizer;

    TIPImageFetchOperation *_fetchOp;
}

- (instancetype)initWithTweetImage:(TweetImageInfo *)imageInfo
{
    if (self = [self init]) {
        _tweetImageInfo = imageInfo;
    }
    return self;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (self = [super initWithNibName:nil bundle:nil]) {
        self.navigationItem.title = @"Tweet Image";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    CGSize targetSize = _tweetImageInfo.originalDimensions;
    const CGFloat scale = [UIScreen mainScreen].scale;
    if (scale != 1) {
        targetSize.height /= scale;
        targetSize.width /= scale;
    }

    _progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 4.)];
    _progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    _progressView.tintColor = [UIColor yellowColor];
    _progressView.progress = 0;

    _imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, targetSize.width, targetSize.height)];
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    _imageView.clipsToBounds = YES;
    _imageView.backgroundColor = [UIColor grayColor];
    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.backgroundColor = [UIColor blackColor];

    _doubleTapGuestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapTriggered:)];
    _doubleTapGuestureRecognizer.numberOfTapsRequired = 2;
    _imageView.image = nil;
    [_imageView addGestureRecognizer:_doubleTapGuestureRecognizer];
    _imageView.userInteractionEnabled = YES;
    _scrollView.delegate = self;
    _scrollView.minimumZoomScale = 0.01f; // start VERY small
    _scrollView.maximumZoomScale = 2.0;
    _scrollView.contentSize = targetSize;

    [self.view addSubview:_scrollView];
    [self.view addSubview:_progressView];
    [_scrollView addSubview:_imageView];
    [_scrollView zoomToRect:_imageView.frame animated:NO];
    _scrollView.minimumZoomScale = _scrollView.zoomScale; // readjust minimum
    if (_scrollView.minimumZoomScale > _scrollView.maximumZoomScale) {
        _scrollView.maximumZoomScale = _scrollView.minimumZoomScale;
    }
    [self scrollViewDidZoom:_scrollView];
    [self _private_load];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self scrollViewDidZoom:_scrollView];
    CGRect frame = _progressView.frame;
    frame.origin.y = _scrollView.contentInset.top;
    _progressView.frame = frame;
}

- (void)_private_load
{
    id<TIPImageFetchRequest> request = [[TweetImageFetchRequest alloc] initWithTweetImage:_tweetImageInfo targetView:_imageView];
    _fetchOp = [APP_DELEGATE.imagePipeline operationWithRequest:request context:nil delegate:self];
    [APP_DELEGATE.imagePipeline fetchImageWithOperation:_fetchOp];
}

#pragma mark Scroll view delegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return _imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    CGFloat offsetX = MAX((scrollView.bounds.size.width - scrollView.contentInset.left - scrollView.contentInset.right - scrollView.contentSize.width) * 0.5f, 0.f);
    CGFloat offsetY = MAX((scrollView.bounds.size.height - scrollView.contentInset.top - scrollView.contentInset.bottom - scrollView.contentSize.height) * 0.5f, 0.f);

    _imageView.center = CGPointMake(scrollView.contentSize.width * 0.5f + offsetX, scrollView.contentSize.height * 0.5f + offsetY);
}

#pragma mark Double tap

- (void)doubleTapTriggered:(UITapGestureRecognizer *)tapper
{
    if (tapper.state == UIGestureRecognizerStateRecognized) {
        if (_scrollView.zoomScale == _scrollView.maximumZoomScale) {
            [_scrollView setZoomScale:_scrollView.minimumZoomScale animated:YES];
        } else {
            [_scrollView setZoomScale:_scrollView.maximumZoomScale animated:YES];
        }
    }
}

#pragma mark TIP delegate

- (void)tip_imageFetchOperationDidStart:(TIPImageFetchOperation *)op
{
    NSLog(@"starting Zoom fetch...");
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op willAttemptToLoadFromSource:(TIPImageLoadSource)source
{
    NSLog(@"...attempting load from next source: %zi...", source);
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadPreviewImage:(id<TIPImageFetchResult>)previewResult completion:(TIPImageFetchDidLoadPreviewCallback)completion
{
    NSLog(@"...preview loaded...");
    _progressView.tintColor = [UIColor blueColor];
    _imageView.image = previewResult.imageContainer.image;
    completion(TIPImageFetchPreviewLoadedBehaviorContinueLoading);
}

- (BOOL)tip_imageFetchOperation:(TIPImageFetchOperation *)op shouldLoadProgressivelyWithIdentifier:(NSString *)identifier URL:(NSURL *)URL imageType:(NSString *)imageType originalDimensions:(CGSize)originalDimensions
{
    if (_imageView.image) {
        return NO;
    }
    return YES;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didUpdateProgressiveImage:(id<TIPImageFetchResult>)progressiveResult progress:(float)progress
{
    NSLog(@"...progressive update (%.3f)...", progress);
    _progressView.tintColor = [UIColor orangeColor];
    [_progressView setProgress:progress animated:YES];
    _imageView.image = progressiveResult.imageContainer.image;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFirstAnimatedImageFrame:(id<TIPImageFetchResult>)progressiveResult progress:(float)progress
{
    NSLog(@"...animated first frame (%.3f)...", progress);
    _imageView.image = progressiveResult.imageContainer.image;
    _progressView.tintColor = [UIColor purpleColor];
    [_progressView setProgress:progress animated:YES];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didUpdateProgress:(float)progress
{
    NSLog(@"...progress (%.3f)...", progress);
    [_progressView setProgress:progress animated:YES];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFinalImage:(id<TIPImageFetchResult>)finalResult
{
    NSLog(@"...completed zoom fetch");
    _progressView.tintColor = [UIColor greenColor];
    [_progressView setProgress:1.f animated:YES];
    _imageView.image = finalResult.imageContainer.image;
    _fetchOp = nil;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didFailToLoadFinalImage:(NSError *)error
{
    NSLog(@"...failed zoom fetch: %@", error);
    _progressView.tintColor = [UIColor redColor];
    _fetchOp = nil;
}

@end
