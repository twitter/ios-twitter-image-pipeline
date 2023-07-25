//
//  TIPTestsSharedUtils.h
//  TwitterImagePipeline
//
//  Created on 8/30/18.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "TIPImageDownloader.h"

NS_ASSUME_NONNULL_BEGIN

static const uint64_t kKiloBits = 1024 * 8;
static const uint64_t kMegaBits = 1024 * kKiloBits;
static const CGSize kCarnivalImageDimensions = { (CGFloat)1880.f, (CGFloat)1253.f };
static const CGSize kFireworksImageDimensions = { (CGFloat)480.f, (CGFloat)320.f };
static const NSUInteger kFireworksFrameCount = 10;
static const NSTimeInterval kFireworksAnimationDurations[10] =
{
    .1f,
    .15f,
    .2f,
    .25f,
    .3f,
    .35f,
    .4f,
    .45f,
    .5f,
    .55f,
};

@interface TIPImagePipelineTestFetchRequest : NSObject <TIPImageFetchRequest>

@property (nonatomic) NSURL *imageURL;
@property (nonatomic, copy, nullable) NSString *imageIdentifier;
@property (nonatomic, copy, nullable) TIPImageFetchHydrationBlock imageRequestHydrationBlock;
@property (nonatomic, copy, nullable) TIPImageFetchAuthorizationBlock imageRequestAuthorizationBlock;
@property (nonatomic) CGSize targetDimensions;
@property (nonatomic) UIViewContentMode targetContentMode;
@property (nonatomic) NSTimeInterval timeToLive;
@property (nonatomic) TIPImageFetchOptions options;
@property (nonatomic) TIPImageFetchLoadingSources loadingSources;
@property (nonatomic) id<TIPImageFetchProgressiveLoadingPolicy> jp2ProgressiveLoadingPolicy;
@property (nonatomic) id<TIPImageFetchProgressiveLoadingPolicy> jpegProgressiveLoadingPolicy;

@property (nonatomic, copy) NSString *imageType;
@property (nonatomic) BOOL progressiveSource;
@property (nonatomic, copy) NSString *cannedImageFilePath;

+ (void)stubRequest:(TIPImagePipelineTestFetchRequest *)request
            bitrate:(uint64_t)bitrate
          resumable:(BOOL)resumable;

@end

@interface TIPImagePipelineTestContext : NSObject

// Populated to configure behavior
@property (nonatomic) BOOL shouldCancelOnPreview;
@property (nonatomic) BOOL shouldSupportProgressiveLoading;
@property (nonatomic) BOOL shouldSupportAnimatedLoading;
@property (nonatomic) float cancelPoint;
@property (nonatomic, weak) TIPImagePipelineTestContext *otherContext;
@property (nonatomic) BOOL shouldCancelOnOtherContextFirstProgress;
@property (nonatomic) NSUInteger expectedFrameCount;

// Populated by delegate
@property (nonatomic) BOOL didStart;
@property (nonatomic) BOOL didProvidePreviewCheck;
@property (nonatomic) BOOL didMakeProgressiveCheck;
@property (nonatomic) float firstProgress;
@property (nonatomic) float firstAnimatedFrameProgress;
@property (nonatomic) BOOL progressWasReset;
@property (nonatomic) id<TIPImageDownloadContext> associatedDownloadContext;
@property (nonatomic) NSUInteger progressiveProgressCount;
@property (nonatomic) NSUInteger normalProgressCount;
@property (nonatomic) TIPImageContainer *finalImageContainer;
@property (nonatomic) NSError *finalError;
@property (nonatomic) TIPImageLoadSource finalSource;
@property (nonatomic, copy) NSArray *hitLoadSources;

@end

@interface TIPImagePipeline (Undeprecated)
- (nonnull TIPImageFetchOperation *)undeprecatedFetchImageWithRequest:(nonnull id<TIPImageFetchRequest>)request context:(nullable id)context delegate:(nullable id<TIPImageFetchDelegate>)delegate;
- (nonnull TIPImageFetchOperation *)undeprecatedFetchImageWithRequest:(nonnull id<TIPImageFetchRequest>)request context:(nullable id)context completion:(nullable TIPImagePipelineFetchCompletionBlock)completion;
@end

@interface TIPImagePipelineBaseTests : XCTestCase <TIPImageFetchDelegate>
+ (nullable NSString *)pathForImageOfType:(NSString *)type progressive:(BOOL)progressive;
+ (NSURL *)dummyURLWithPath:(NSString *)path;
+ (TIPImagePipeline *)sharedPipeline;
@end

NS_ASSUME_NONNULL_END
