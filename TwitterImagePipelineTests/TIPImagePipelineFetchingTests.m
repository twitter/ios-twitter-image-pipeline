//
//  TIPImagePipelineFetchingTests.m
//  TwitterImagePipeline
//
//  Created on 4/27/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPImageDiskCache.h"
#import "TIPImageMemoryCache.h"
#import "TIPImagePipeline+Project.h"
#import "TIPImageRenderedCache.h"
#import "TIPTestImageFetchDownloadInternalWithStubbing.h"
#import "TIPTests.h"
#import "TIPTestsSharedUtils.h"

typedef struct _TIPImageFetchTestStruct {
    __unsafe_unretained NSString *type;
    BOOL progressiveSource;
    BOOL isProgressive;
    BOOL isAnimated;
    uint64_t bps;
} TIPImageFetchTestStruct;

@interface TIPImagePipelineFetchingBaseTests : TIPImagePipelineBaseTests
- (void)runFetching:(TIPImageFetchTestStruct)imageStruct; // execute fetching test
@end

@interface TIPImagePipelineFetchingPNGTests : TIPImagePipelineFetchingBaseTests
@end

@interface TIPImagePipelineFetchingJPEGTests : TIPImagePipelineFetchingBaseTests
@end

@interface TIPImagePipelineFetchingJPEG2000Tests : TIPImagePipelineFetchingBaseTests
@end

@interface TIPImagePipelineFetchingGIFTests : TIPImagePipelineFetchingBaseTests
@end

@implementation TIPImagePipelineFetchingBaseTests

- (void)_validateFetchOperation:(TIPImageFetchOperation *)op
                        context:(TIPImagePipelineTestContext *)context
                         source:(TIPImageLoadSource)source
                          state:(TIPImageFetchOperationState)state
{
    const BOOL progressiveOn = context.shouldSupportProgressiveLoading;
    const BOOL animatedOn = context.shouldSupportAnimatedLoading;
    const BOOL shouldReachFinal = (TIPImageFetchOperationStateSucceeded == state);
    const BOOL metricsWillBeGathered = [[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider isKindOfClass:[TIPTestImageFetchDownloadProviderInternalWithStubbing class]];

    NSString *type = [(TIPImagePipelineTestFetchRequest*)op.request imageType];
    XCTAssertEqual(context.didStart, YES, @"imageType == %@", type);
    if (shouldReachFinal) {
        XCTAssertNotNil(context.finalImageContainer, @"imageType == %@", type);
        XCTAssertNil(context.finalError, @"imageType == %@", type);
        XCTAssertEqual(context.finalSource, source, @"imageType == %@", type);
        XCTAssertEqualObjects(context.finalImageContainer, op.finalResult.imageContainer, @"imageType == %@", type);
        XCTAssertEqual(context.finalSource, op.finalResult.imageSource, @"imageType == %@", type);
        for (TIPImageLoadSource expectedSource = TIPImageLoadSourceMemoryCache; expectedSource <= source; expectedSource++) {
            if (expectedSource == TIPImageLoadSourceNetworkResumed) {
                expectedSource++;
            }

            if (expectedSource == TIPImageLoadSourceNetwork) {
                // be less rigorous about network loading
                XCTAssertTrue([context.hitLoadSources containsObject:@(TIPImageLoadSourceNetworkResumed)] || [context.hitLoadSources containsObject:@(TIPImageLoadSourceNetwork)], @"Missing %@ or %@ in %@", @(TIPImageLoadSourceNetwork), @(TIPImageLoadSourceNetworkResumed), context.hitLoadSources);
            } else {
                // if the source is memory, could be sync load which won't set the "hitLoadSources" which is totally fine
                if (expectedSource == TIPImageLoadSourceMemoryCache && source == TIPImageLoadSourceMemoryCache && context.hitLoadSources) {
                    XCTAssertTrue([context.hitLoadSources containsObject:@(expectedSource)], @"Missing %@ in %@", @(expectedSource), context.hitLoadSources);
                }
            }
        }
        if (source == TIPImageLoadSourceNetwork) {
            TIPImageFetchMetrics *metrics = op.metrics;
            XCTAssertNotNil(metrics);
            if (metrics) {
                XCTAssertGreaterThan(metrics.totalDuration, 0.0);
                XCTAssertFalse(metrics.wasCancelled);

                TIPImageFetchMetricInfo *info = [metrics metricInfoForSource:source];
                XCTAssertNotNil(info);
                if (info) {
                    XCTAssertEqual(info.source, source);
                    XCTAssertEqual(info.result, TIPImageFetchLoadResultHitFinal);
                    XCTAssertFalse(info.wasCancelled);
                    XCTAssertGreaterThan(info.loadDuration, 0.0);
                    if (metricsWillBeGathered) {
                        XCTAssertNotNil(info.networkMetrics);
                    }
                    XCTAssertGreaterThan(info.totalNetworkLoadDuration, 0.0);
                    XCTAssertGreaterThan(info.networkImageSizeInBytes, (NSUInteger)0);
                    XCTAssertEqualObjects(info.networkImageType, type);
                    XCTAssertTrue(!CGSizeEqualToSize(CGSizeZero, info.networkImageDimensions));
                    XCTAssertGreaterThan(info.networkImagePixelsPerByte, 0.0f);
                }
            }
        }
    } else {
        XCTAssertNil(context.finalImageContainer, @"imageType == %@", type);
        XCTAssertNotNil(context.finalError, @"imageType == %@", type);
        XCTAssertNil(op.finalResult.imageContainer, @"imageType == %@", type);
        XCTAssertEqualObjects(context.finalError, op.error, @"imageType == %@", type);
        XCTAssertEqualObjects(context.finalError.domain, TIPImageFetchErrorDomain, @"imageType == %@", type);
    }
    if (progressiveOn && (TIPImageLoadSourceNetwork == source || TIPImageLoadSourceNetworkResumed == source) && [[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsProgressiveLoading:type]) {
        XCTAssertGreaterThan(context.progressiveProgressCount, (NSUInteger)0, @"imageType == %@", type);
    } else {
        XCTAssertEqual(context.progressiveProgressCount, (NSUInteger)0, @"imageType == %@", type);
    }
    if (animatedOn && TIPImageLoadSourceNetwork == source && [[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsAnimation:type] && context.expectedFrameCount > 1) {
        // only iOS 11 supports progressive animation loading due to a crashing bug in iOS 10
        if (tip_available_ios_11) {
            XCTAssertGreaterThan(context.firstAnimatedFrameProgress, (float)0.0f);
            XCTAssertLessThan(context.firstAnimatedFrameProgress, (float)1.0f);
        } else {
            XCTAssertEqualWithAccuracy(context.firstAnimatedFrameProgress, (float)0.0f, (float)0.001f);
        }
    }
    if (animatedOn) {
        if (context.finalImageContainer) {
            XCTAssertEqual(context.finalImageContainer.frameCount, context.expectedFrameCount);
            if (context.expectedFrameCount > 1) {
                XCTAssertTrue(context.finalImageContainer.isAnimated);
                XCTAssertEqual(context.finalImageContainer.frameDurations.count, context.expectedFrameCount);
                for (NSUInteger i = 0; i < context.finalImageContainer.frameCount; i++) {
                    XCTAssertEqualWithAccuracy([context.finalImageContainer frameDurationAtIndex:i], kFireworksAnimationDurations[i], 0.005);
                }
            } else {
                XCTAssertFalse(context.finalImageContainer.isAnimated);
            }
        }
    } else {
        if (context.finalImageContainer) {
            XCTAssertEqual(context.finalImageContainer.frameCount, (NSUInteger)1);
        }
    }
    XCTAssertEqual(op.state, state, @"imageType == %@", type);
}

- (void)runFetching:(TIPImageFetchTestStruct)imageStruct
{
    @autoreleasepool {
        BOOL progressive = imageStruct.isProgressive;
        BOOL animated = imageStruct.isAnimated;

        TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
        request.imageType = imageStruct.type;
        request.progressiveSource = imageStruct.progressiveSource;
        request.imageURL = [TIPImagePipelineBaseTests dummyURLWithPath:[NSUUID UUID].UUIDString];
        request.targetDimensions = ([imageStruct.type isEqualToString:TIPImageTypeGIF]) ? kFireworksImageDimensions : kCarnivalImageDimensions;
        request.targetContentMode = UIViewContentModeScaleAspectFit;

        TIPImageFetchOperation *op = nil;
        TIPImagePipelineTestContext *context = nil;

        [TIPImagePipelineTestFetchRequest stubRequest:request bitrate:imageStruct.bps * 10 resumable:YES]; // start fast
        [[TIPImagePipelineBaseTests sharedPipeline] clearDiskCache];
        [[TIPImagePipelineBaseTests sharedPipeline] clearMemoryCaches];

        // Network Load
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetwork state:TIPImageFetchOperationStateSucceeded];

        // NSLog(@"First image: %fs, Last image: %fs", op.metrics.firstImageLoadDuration, op.metrics.totalDuration);

        // Memory Cache Load
        [[[TIPImagePipelineBaseTests sharedPipeline] cacheOfType:TIPImageCacheTypeRendered] clearAllImages:NULL];
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceMemoryCache state:TIPImageFetchOperationStateSucceeded];

        // Rendered Cache Load
        [[[TIPImagePipelineBaseTests sharedPipeline] cacheOfType:TIPImageCacheTypeMemory] clearAllImages:NULL];
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceMemoryCache state:TIPImageFetchOperationStateSucceeded];

        // Disk Cache Load
        [[TIPImagePipelineBaseTests sharedPipeline] clearMemoryCaches];
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceDiskCache state:TIPImageFetchOperationStateSucceeded];


        [TIPImagePipelineTestFetchRequest stubRequest:request bitrate:imageStruct.bps resumable:YES]; // slow it down


        // Network Load Cancelled
        [[TIPImagePipelineBaseTests sharedPipeline] clearMemoryCaches];
        [[TIPImagePipelineBaseTests sharedPipeline] clearDiskCache];
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        context.cancelPoint = 0.2f;
        op = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetwork state:TIPImageFetchOperationStateCancelled];


        [TIPImagePipelineTestFetchRequest stubRequest:request bitrate:imageStruct.bps * 10 resumable:YES]; // speed it up


        // Network Load Resume
        float progress = op.progress;
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetworkResumed state:TIPImageFetchOperationStateSucceeded];
        XCTAssertGreaterThanOrEqual(context.firstProgress, progress);
        XCTAssertFalse(context.progressWasReset);


        [TIPImagePipelineTestFetchRequest stubRequest:request bitrate:imageStruct.bps resumable:NO]; // slow it down


        // Network Load Cancelled
        [[TIPImagePipelineBaseTests sharedPipeline] clearMemoryCaches];
        [[TIPImagePipelineBaseTests sharedPipeline] clearDiskCache];
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        context.cancelPoint = 0.2f;
        op = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetwork state:TIPImageFetchOperationStateCancelled];

        // Network Load Reset
        progress = op.progress;
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetwork state:TIPImageFetchOperationStateSucceeded];
        XCTAssertEqual(context.firstProgress, progress);
        XCTAssertTrue(context.progressWasReset);
    }
}

@end

@implementation TIPImagePipelineFetchingPNGTests

- (void)testFetchingPNG
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypePNG, NO, NO, NO, 3 * kMegaBits };
    [self runFetching:imageStruct];
}

@end

@implementation TIPImagePipelineFetchingJPEGTests

- (void)testFetchingJPEG
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeJPEG, NO, NO, NO, 2 * kMegaBits };
    [self runFetching:imageStruct];
}

- (void)testFetchingPJPEG_notProgressive
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeJPEG, YES, NO, NO, 1 * kMegaBits };
    [self runFetching:imageStruct];
}

- (void)testFetchingPJPEG_isProgressive
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeJPEG, YES, YES, NO, 1 * kMegaBits };
    [self runFetching:imageStruct];
}

@end

@implementation TIPImagePipelineFetchingJPEG2000Tests

- (void)testFetchingJPEG2000
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeJPEG2000, YES, NO, NO, 256 * kKiloBits };
    if (@available(iOS 11.1, tvOS 11.1, macOS 10.13.1, watchOS 4.1, *)) {
        NSLog(@"iOS 11.1 regressed JPEG2000 so that the image cannot be parsed until fully downloading thus breaking most expectations TIP unit tests have.  Radars have been filed but please file another radar against Apple if you care about JPEG2000 support.");
    } else {
        [self runFetching:imageStruct];
    }
}

- (void)testFetchingPJPEG2000
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeJPEG2000, YES, YES, NO, 256 * kKiloBits };
    if ([[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsProgressiveLoading:imageStruct.type]) {
        [self runFetching:imageStruct];
    } else {
        NSLog(@"Skipping unit test");
    }
}

@end

@implementation TIPImagePipelineFetchingGIFTests

- (void)testFetchingGIF
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeGIF, NO, NO, YES, 160 * kKiloBits };
    [self runFetching:imageStruct];
}

- (void)testFetchingSingleFrameGIF
{
    NSBundle *thisBundle = TIPTestsResourceBundle();
    NSString *singleFrameGIFPath = [thisBundle pathForResource:@"single_frame" ofType:@"gif"];

    @autoreleasepool {
        TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
        request.imageType = TIPImageTypeGIF;
        request.cannedImageFilePath = singleFrameGIFPath;
        request.imageURL = [TIPImagePipelineBaseTests dummyURLWithPath:[NSUUID UUID].UUIDString];
        request.targetDimensions = CGSizeMake(360, 200);
        request.targetContentMode = UIViewContentModeScaleAspectFit;

        BOOL progressive = NO;
        BOOL animated = YES;

        TIPImageFetchOperation *op = nil;
        TIPImagePipelineTestContext *context = nil;

        [TIPImagePipelineTestFetchRequest stubRequest:request bitrate:64 * kKiloBits resumable:YES];

        // Network Load
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        context.expectedFrameCount = 1;
        op = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetwork state:TIPImageFetchOperationStateSucceeded];
    }
}

@end
