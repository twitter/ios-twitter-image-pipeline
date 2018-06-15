//
//  TIPImagePipelineTests.m
//  TwitterImagePipeline
//
//  Created on 4/27/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <TwitterImagePipeline/TwitterImagePipeline.h>
#import <XCTest/XCTest.h>

#import "TIP_Project.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageDiskCache.h"
#import "TIPImageFetchOperation+Project.h"
#import "TIPImageMemoryCache.h"
#import "TIPImagePipeline+Project.h"
#import "TIPImageRenderedCache.h"

#import "TIPTestImageFetchDownloadInternalWithStubbing.h"

#import "TIPTests.h"

@import MobileCoreServices;

static const uint64_t kKiloBits = 1024 * 8;
static const uint64_t kMegaBits = 1024 * kKiloBits;
static const CGSize kCarnivalImageDimensions = { (CGFloat)1880.f, (CGFloat)1253.f };
static const CGSize kFireworksImageDimensions = { (CGFloat)480.f, (CGFloat)320.f };
static const NSUInteger kFireworksFrameCount = 10;
static const NSTimeInterval kFireworksAnimationDurations [10] =
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

typedef struct _TIPImageFetchTestStruct {
    __unsafe_unretained NSString *type;
    BOOL progressiveSource;
    BOOL isProgressive;
    BOOL isAnimated;
    uint64_t bps;
} TIPImageFetchTestStruct;

@interface TestImageStoreRequest : NSObject <TIPImageStoreRequest>
@property (nonatomic) NSURL *imageURL;
@property (nonatomic, copy) NSString *imageFilePath;
@end

@implementation TestImageStoreRequest
@end

@interface TIPImagePipelineTestFetchRequest : NSObject <TIPImageFetchRequest>
@property (nonatomic) NSURL *imageURL;
@property (nonatomic, copy) NSString *imageIdentifier;
@property (nonatomic, copy) TIPImageFetchHydrationBlock imageRequestHydrationBlock;
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

@interface TIPImagePipelineTests : XCTestCase <TIPImageFetchDelegate>
@end

static TIPImagePipeline *sPipeline = nil;

@implementation TIPImagePipelineTests

+ (NSString *)pathForImageOfType:(NSString *)type progressive:(BOOL)progressive
{
    NSString *imagePath = nil;
    NSBundle *thisBundle = TIPTestsResourceBundle();

    if ([type isEqualToString:TIPImageTypeGIF]) {
        imagePath = [thisBundle pathForResource:@"fireworks" ofType:@"gif"];
    } else {
        NSString *extension = nil;

        if ([type isEqualToString:TIPImageTypeJPEG]) {
            extension = (progressive) ? @"pjpg" : @"jpg";
        } else if ([type isEqualToString:TIPImageTypeJPEG2000]) {
            extension = @"jp2";
        } else if ([type isEqualToString:TIPImageTypePNG]) {
            extension = @"png";
        }

        if (extension) {
            imagePath = [thisBundle pathForResource:@"carnival" ofType:extension];
        }
    }

    return imagePath;
}

+ (NSURL *)dummyURLWithPath:(NSString *)path
{
    if (!path) {
        path = @"";
    }
    if (![path hasPrefix:@"/"]) {
        path = [@"/" stringByAppendingString:path];
    }
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://www.dummy.com%@", path]];
}

+ (void)setUp
{
    TIPGlobalConfiguration *globalConfig = [TIPGlobalConfiguration sharedInstance];
    TIPSetDebugSTOPOnAssertEnabled(NO);
    TIPSetShouldAssertDuringPipelineRegistation(NO);
    sPipeline = [[TIPImagePipeline alloc] initWithIdentifier:NSStringFromClass(self)];
    globalConfig.imageFetchDownloadProvider = [[TIPTestsImageFetchDownloadProviderOverrideClass() alloc] init];
    globalConfig.maxConcurrentImagePipelineDownloadCount = 4;
    globalConfig.maxBytesForAllRenderedCaches = 12 * 1024 * 1024;
    globalConfig.maxBytesForAllMemoryCaches = 36 * 1024 * 1024;
    globalConfig.maxBytesForAllDiskCaches = 16 * 1024 * 1024;
    globalConfig.maxRatioSizeOfCacheEntry = 0;
}

+ (void)tearDown
{
    TIPGlobalConfiguration *globalConfig = [TIPGlobalConfiguration sharedInstance];
    TIPSetDebugSTOPOnAssertEnabled(YES);
    TIPSetShouldAssertDuringPipelineRegistation(YES);
    [sPipeline.renderedCache clearAllImages:NULL];
    [sPipeline.memoryCache clearAllImages:NULL];
    [sPipeline.diskCache clearAllImages:NULL];
    globalConfig.imageFetchDownloadProvider = nil;
    globalConfig.maxBytesForAllRenderedCaches = -1;
    globalConfig.maxBytesForAllMemoryCaches = -1;
    globalConfig.maxBytesForAllDiskCaches = -1;
    globalConfig.maxConcurrentImagePipelineDownloadCount = TIPMaxConcurrentImagePipelineDownloadCountDefault;
    globalConfig.maxRatioSizeOfCacheEntry = -1;

    sPipeline = nil;
}

- (void)tearDown
{
    [sPipeline.renderedCache clearAllImages:NULL];
    [sPipeline.memoryCache clearAllImages:NULL];
    [sPipeline.diskCache clearAllImages:NULL];

    id<TIPImageFetchDownloadProviderWithStubbingSupport> provider = (id<TIPImageFetchDownloadProviderWithStubbingSupport>)[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider;
    [provider removeAllDownloadStubs];

    // Flush ALL pipelines
    __block BOOL didInspect = NO;
    [[TIPGlobalConfiguration sharedInstance] inspect:^(NSDictionary *results) {
        didInspect = YES;
    }];
    while (!didInspect) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    [super tearDown];
}

- (void)testImagePipelineConstruction
{
    NSString *identifier = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ.abcdefghijklmnopqrstuvwxyz_0123456789-";
    TIPImagePipeline *pipeline = nil;

    @autoreleasepool {
        pipeline = [[TIPImagePipeline alloc] initWithIdentifier:identifier];
        XCTAssertNotNil(pipeline);
        pipeline = nil;
    }

    @autoreleasepool {
        pipeline = [[TIPImagePipeline alloc] initWithIdentifier:identifier];
        XCTAssertNotNil(pipeline);
    }

    @autoreleasepool {
        TIPImagePipeline *pipeline2 = [[TIPImagePipeline alloc] initWithIdentifier:identifier];
        XCTAssertNil(pipeline2);
        pipeline = nil;
    }

    @autoreleasepool {
        pipeline = [[TIPImagePipeline alloc] initWithIdentifier:[identifier stringByReplacingOccurrencesOfString:@"." withString:@" "]];
        XCTAssertNil(pipeline);
        pipeline = nil;
    }

    @autoreleasepool {
        pipeline = [[TIPImagePipeline alloc] initWithIdentifier:sPipeline.identifier];
        XCTAssertNil(pipeline);
        pipeline = nil;
    }
}

- (void)_validateFetchOperation:(TIPImageFetchOperation *)op
                        context:(TIPImagePipelineTestContext *)context
                         source:(TIPImageLoadSource)source
                          state:(TIPImageFetchOperationState)state
{
    const BOOL progressiveOn = context.shouldSupportProgressiveLoading;
    const BOOL animatedOn = context.shouldSupportAnimatedLoading;
    const BOOL shouldReachFinal = (TIPImageFetchOperationStateSucceeded == state);
    const BOOL metricsWillBeGathered = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 10 && [[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider isKindOfClass:[TIPTestImageFetchDownloadProviderInternalWithStubbing class]];
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
        if (@available(iOS 11.0, *)) {
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

- (void)_stubRequest:(TIPImagePipelineTestFetchRequest *)request bitrate:(uint64_t)bitrate resumable:(BOOL)resumable
{
    NSData *data = [NSData dataWithContentsOfFile:request.cannedImageFilePath options:NSDataReadingMappedIfSafe error:NULL];
    NSString *MIMEType = (NSString *)CFBridgingRelease(UTTypeIsDeclared((__bridge CFStringRef)request.imageType) ? UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)request.imageType, kUTTagClassMIMEType) : nil);
    id<TIPImageFetchDownloadProviderWithStubbingSupport> provider = (id<TIPImageFetchDownloadProviderWithStubbingSupport>)[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider;
    [provider addDownloadStubForRequestURL:request.imageURL responseData:data responseMIMEType:MIMEType shouldSupportResuming:resumable suggestedBitrate:bitrate];
}

- (void)_runFetching:(TIPImageFetchTestStruct)imageStruct
{
    @autoreleasepool {
        BOOL progressive = imageStruct.isProgressive;
        BOOL animated = imageStruct.isAnimated;

        TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
        request.imageType = imageStruct.type;
        request.progressiveSource = imageStruct.progressiveSource;
        request.imageURL = [TIPImagePipelineTests dummyURLWithPath:[NSUUID UUID].UUIDString];
        request.targetDimensions = ([imageStruct.type isEqualToString:TIPImageTypeGIF]) ? kFireworksImageDimensions : kCarnivalImageDimensions;
        request.targetContentMode = UIViewContentModeScaleAspectFit;

        TIPImageFetchOperation *op = nil;
        TIPImagePipelineTestContext *context = nil;

        [self _stubRequest:request bitrate:imageStruct.bps * 10 resumable:YES]; // start fast
        [sPipeline clearDiskCache];
        [sPipeline clearMemoryCaches];

        // Network Load
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [sPipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetwork state:TIPImageFetchOperationStateSucceeded];

        // NSLog(@"First image: %fs, Last image: %fs", op.metrics.firstImageLoadDuration, op.metrics.totalDuration);

        // Memory Cache Load
        [sPipeline.renderedCache clearAllImages:NULL];
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [sPipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceMemoryCache state:TIPImageFetchOperationStateSucceeded];

        // Rendered Cache Load
        [sPipeline.memoryCache clearAllImages:NULL];
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [sPipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceMemoryCache state:TIPImageFetchOperationStateSucceeded];

        // Disk Cache Load
        [sPipeline.memoryCache clearAllImages:NULL];
        [sPipeline.renderedCache clearAllImages:NULL];
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [sPipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceDiskCache state:TIPImageFetchOperationStateSucceeded];


        [self _stubRequest:request bitrate:imageStruct.bps resumable:YES]; // slow it down


        // Network Load Cancelled
        [sPipeline.memoryCache clearAllImages:NULL];
        [sPipeline.diskCache clearAllImages:NULL];
        [sPipeline.renderedCache clearAllImages:NULL];
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        context.cancelPoint = 0.2f;
        op = [sPipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetwork state:TIPImageFetchOperationStateCancelled];


        [self _stubRequest:request bitrate:imageStruct.bps * 10 resumable:YES]; // speed it up


        // Network Load Resume
        float progress = op.progress;
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [sPipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetworkResumed state:TIPImageFetchOperationStateSucceeded];
        XCTAssertGreaterThanOrEqual(context.firstProgress, progress);


        [self _stubRequest:request bitrate:imageStruct.bps resumable:NO]; // slow it down


        // Network Load Cancelled
        [sPipeline.memoryCache clearAllImages:NULL];
        [sPipeline.diskCache clearAllImages:NULL];
        [sPipeline.renderedCache clearAllImages:NULL];
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        context.cancelPoint = 0.2f;
        op = [sPipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetwork state:TIPImageFetchOperationStateCancelled];

        // Network Load Reset
        progress = op.progress;
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        op = [sPipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetwork state:TIPImageFetchOperationStateSucceeded];
        XCTAssertLessThan(context.firstProgress, progress);
    }
}

- (void)testFetchingPNG
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypePNG, NO, NO, NO, 3 * kMegaBits };
    [self _runFetching:imageStruct];
}

- (void)testFetchingJPEG
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeJPEG, NO, NO, NO, 2 * kMegaBits };
    [self _runFetching:imageStruct];
}

- (void)testFetchingPJPEG_notProgressive
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeJPEG, YES, NO, NO, 1 * kMegaBits };
    [self _runFetching:imageStruct];
}

- (void)testFetchingPJPEG_isProgressive
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeJPEG, YES, YES, NO, 1 * kMegaBits };
    [self _runFetching:imageStruct];
}

- (void)testFetchingJPEG2000
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeJPEG2000, YES, NO, NO, 256 * kKiloBits };
    if (@available(iOS 11.1, *)) {
        NSLog(@"iOS 11.1 regressed JPEG2000 so that the image cannot be parsed until fully downloading thus breaking most expectations TIP unit tests have.  Radars have been filed but please file another radar against Apple if you care about JPEG2000 support.");
    } else {
        [self _runFetching:imageStruct];
    }
}

- (void)testFetchingPJPEG2000
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeJPEG2000, YES, YES, NO, 256 * kKiloBits };
    if ([[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsProgressiveLoading:imageStruct.type]) {
        [self _runFetching:imageStruct];
    } else {
        NSLog(@"Skipping unit test");
    }
}

- (void)testFetchingGIF
{
    TIPImageFetchTestStruct imageStruct = { TIPImageTypeGIF, NO, NO, YES, 160 * kKiloBits };
    [self _runFetching:imageStruct];
}

- (void)testFetchingSingleFrameGIF
{
    NSBundle *thisBundle = TIPTestsResourceBundle();
    NSString *singleFrameGIFPath = [thisBundle pathForResource:@"single_frame" ofType:@"gif"];

    @autoreleasepool {
        TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
        request.imageType = TIPImageTypeGIF;
        request.cannedImageFilePath = singleFrameGIFPath;
        request.imageURL = [TIPImagePipelineTests dummyURLWithPath:[NSUUID UUID].UUIDString];
        request.targetDimensions = CGSizeMake(360, 200);
        request.targetContentMode = UIViewContentModeScaleAspectFit;

        BOOL progressive = NO;
        BOOL animated = YES;

        TIPImageFetchOperation *op = nil;
        TIPImagePipelineTestContext *context = nil;

        [self _stubRequest:request bitrate:64 * kKiloBits resumable:YES];

        // Network Load
        context = [[TIPImagePipelineTestContext alloc] init];
        context.shouldSupportProgressiveLoading = progressive;
        context.shouldSupportAnimatedLoading = animated;
        context.expectedFrameCount = 1;
        op = [sPipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
        [op waitUntilFinishedWithoutBlockingRunLoop];
        [self _validateFetchOperation:op context:context source:TIPImageLoadSourceNetwork state:TIPImageFetchOperationStateSucceeded];
    }
}

- (void)testFillingTheCaches
{
    [self _runFillingTheCaches:sPipeline bps:1024 * kMegaBits testCacheHits:YES];
}

- (void)testFillingMultipeCaches
{
    TIPGlobalConfiguration *config = [TIPGlobalConfiguration sharedInstance];

    __block SInt64 preDeallocDiskSize;
    __block SInt64 preDeallocMemSize;
    __block SInt64 preDeallocRendSize;

    __block SInt64 preDeallocPipelineDiskSize;
    __block SInt64 preDeallocPipelineMemSize;
    __block SInt64 preDeallocPipelineRendSize;

    NSString *tmpPipelineIdentifier = @"temp.pipeline.identifier";
    XCTestExpectation *expectation = [self expectationForNotification:TIPImagePipelineDidTearDownImagePipelineNotification object:nil handler:^BOOL(NSNotification *note) {
        return [tmpPipelineIdentifier isEqualToString:note.userInfo[TIPImagePipelineImagePipelineIdentifierNotificationKey]];
    }];

    @autoreleasepool {
        [sPipeline clearMemoryCaches];
        [sPipeline clearDiskCache];
        TIPImagePipeline *temporaryPipeline = [[TIPImagePipeline alloc] initWithIdentifier:tmpPipelineIdentifier];

        [self _runFillingTheCaches:sPipeline bps:1024 * kMegaBits testCacheHits:NO];

        TIPGlobalConfiguration *globalConfig = [TIPGlobalConfiguration sharedInstance];

        XCTAssertGreaterThan(sPipeline.renderedCache.manifest.numberOfEntries, (NSUInteger)0);
        dispatch_sync(globalConfig.queueForMemoryCaches, ^{
            XCTAssertGreaterThan(sPipeline.memoryCache.manifest.numberOfEntries, (NSUInteger)0);
        });
        dispatch_sync(globalConfig.queueForDiskCaches, ^{
            XCTAssertGreaterThan(sPipeline.diskCache.manifest.numberOfEntries, (NSUInteger)0);
        });

        [self _runFillingTheCaches:temporaryPipeline bps:1024 * kMegaBits testCacheHits:NO];
        XCTAssertGreaterThan(temporaryPipeline.renderedCache.manifest.numberOfEntries, (NSUInteger)0);
        XCTAssertEqual(sPipeline.renderedCache.manifest.numberOfEntries, (NSUInteger)0);
        dispatch_sync(globalConfig.queueForMemoryCaches, ^{
            XCTAssertGreaterThan(temporaryPipeline.memoryCache.manifest.numberOfEntries, (NSUInteger)0);
            XCTAssertEqual(sPipeline.memoryCache.manifest.numberOfEntries, (NSUInteger)0);
        });
        dispatch_sync(globalConfig.queueForMemoryCaches, ^{
            XCTAssertGreaterThan(temporaryPipeline.diskCache.manifest.numberOfEntries, (NSUInteger)0);
            XCTAssertEqual(sPipeline.diskCache.manifest.numberOfEntries, (NSUInteger)0);
        });

        dispatch_sync(globalConfig.queueForDiskCaches, ^{
            preDeallocDiskSize = config.internalTotalBytesForAllDiskCaches;
        });
        dispatch_sync(globalConfig.queueForMemoryCaches, ^{
            preDeallocMemSize = config.internalTotalBytesForAllMemoryCaches;
        });
        preDeallocRendSize = config.internalTotalBytesForAllRenderedCaches;

        preDeallocPipelineDiskSize = (SInt64)temporaryPipeline.diskCache.totalCost;
        preDeallocPipelineMemSize = (SInt64)temporaryPipeline.memoryCache.totalCost;
        preDeallocPipelineRendSize = (SInt64)temporaryPipeline.renderedCache.totalCost;

        temporaryPipeline = nil;
    }

    NSLog(@"Waiting for %@", TIPImagePipelineDidTearDownImagePipelineNotification);

    // Wait for the pipeline to release
    [self waitForExpectationsWithTimeout:120.0 handler:^(NSError *error) {
        if (error) {
            NSLog(@"%@", error);
        } else {
            NSLog(@"Received %@", TIPImagePipelineDidTearDownImagePipelineNotification);
        }
    }];
    expectation = nil;

    __block SInt64 postDeallocDiskSize;
    __block SInt64 postDeallocMemSize;
    __block SInt64 postDeallocRendSize;

    const NSUInteger cacheSizeCheckMax = 30;
    NSUInteger cacheSizeCheck;
    for (cacheSizeCheck = 1; cacheSizeCheck <= cacheSizeCheckMax; cacheSizeCheck++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

        dispatch_sync([TIPGlobalConfiguration sharedInstance].queueForDiskCaches, ^{
            postDeallocDiskSize = config.internalTotalBytesForAllDiskCaches;
        });
        dispatch_sync([TIPGlobalConfiguration sharedInstance].queueForMemoryCaches, ^{
            postDeallocMemSize = config.internalTotalBytesForAllMemoryCaches;
        });
        postDeallocRendSize = config.internalTotalBytesForAllRenderedCaches;

        if (postDeallocDiskSize == 0 && postDeallocMemSize == 0 && postDeallocRendSize == 0) {
            break;
        }
    }

    if (cacheSizeCheck <= cacheSizeCheckMax) {
        NSLog(@"Caches were relieved after %tu seconds", cacheSizeCheck);
    } else {
        NSLog(@"ERR: Caches were not relieved after %tu seconds", cacheSizeCheck - 1);
    }

    XCTAssertEqual(postDeallocDiskSize, preDeallocDiskSize - preDeallocPipelineDiskSize);
    XCTAssertEqual(postDeallocMemSize, preDeallocMemSize - preDeallocPipelineMemSize);
    XCTAssertEqual(postDeallocRendSize, preDeallocRendSize - preDeallocPipelineRendSize);
}

- (void)testConcurrentManifestLoad
{
    NSArray *(^buildComparablesFromPipeline)(TIPImagePipeline *) = ^(TIPImagePipeline *pipeline) {
        __block NSArray *comparables = nil;
        XCTestExpectation *builtComparables = [self expectationWithDescription:@"built comparables"];

        [pipeline inspect:^(TIPImagePipelineInspectionResult * _Nullable result) {
            NSArray *entries = [result.completeDiskEntries arrayByAddingObjectsFromArray:result.partialDiskEntries];

            NSMutableArray *comparablesMutable = [NSMutableArray arrayWithCapacity:entries.count];
            for (id<TIPImagePipelineInspectionResultEntry> entry in entries) {
                [comparablesMutable addObject:@[[entry identifier], [entry URL], [NSValue valueWithCGSize:[entry dimensions]], @([entry bytesUsed]), @([entry progress])]];
            };

            comparables = comparablesMutable;
            [builtComparables fulfill];
        }];

        [self waitForExpectationsWithTimeout:20 handler:nil];
        builtComparables = nil;
        return comparables;
    };

    NSString *identifier = @"concurrentManifestLoadTest";

    [self _safelyOpenPipelineWithIdentifier:identifier executingBlock:^(TIPImagePipeline *initialPipeline) {

        TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
        request.cannedImageFilePath = [TIPTestsResourceBundle() pathForResource:@"twitterfied" ofType:@"pjpg"];

        id<TIPImageFetchDownloadProviderWithStubbingSupport> provider = (id<TIPImageFetchDownloadProviderWithStubbingSupport>)[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider;

        NSMutableArray<NSURL *> *stubbedRequestURLs = [NSMutableArray array];
        NSOperation *blockOp = [NSBlockOperation blockOperationWithBlock:^{}];
        for (NSUInteger i = 0; i < 150; i++) {
            request.imageURL = [TIPImagePipelineTests dummyURLWithPath:[NSUUID UUID].UUIDString];
            [self _stubRequest:request bitrate:UINT64_MAX resumable:YES];
            [stubbedRequestURLs addObject:request.imageURL];
            TIPImageFetchOperation *op = [initialPipeline undeprecatedFetchImageWithRequest:request context:nil delegate:nil];
            [blockOp addDependency:op];
        }

        NSOperationQueue *opQ = [[NSOperationQueue alloc] init];
        opQ.maxConcurrentOperationCount = 1;
        [opQ addOperation:blockOp];
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        while (!blockOp.isFinished) {
            [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.250]];
        }

        for (NSURL *URL in stubbedRequestURLs) {
            [provider removeDownloadStubForRequestURL:URL];
        }

    }];

    __block NSArray *concurrentComparables1 = nil;
    [self _safelyOpenPipelineWithIdentifier:identifier executingBlock:^(TIPImagePipeline *concurrentlyLoadedPipeline) {
        concurrentComparables1 = buildComparablesFromPipeline(concurrentlyLoadedPipeline);
    }];
    XCTAssertNotNil(concurrentComparables1);

    __block NSArray *concurrentComparables2 = nil;
    [self _safelyOpenPipelineWithIdentifier:identifier executingBlock:^(TIPImagePipeline *concurrentlyLoadedPipeline) {
        concurrentComparables2 = buildComparablesFromPipeline(concurrentlyLoadedPipeline);
    }];
    XCTAssertNotNil(concurrentComparables2);

    XCTAssertEqualObjects([NSSet setWithArray:concurrentComparables1], [NSSet setWithArray:concurrentComparables2]);

    TIPImagePipeline *pipeline = [[TIPImagePipeline alloc] initWithIdentifier:identifier];
    [pipeline clearDiskCache];
    [pipeline inspect:^(TIPImagePipelineInspectionResult * _Nullable result) {}];
    XCTestExpectation *expectation = [self expectationForNotification:TIPImagePipelineDidTearDownImagePipelineNotification object:nil handler:^BOOL(NSNotification *note) {
        return [identifier isEqualToString:note.userInfo[TIPImagePipelineImagePipelineIdentifierNotificationKey]];
    }];
    pipeline = nil;
    [self waitForExpectationsWithTimeout:20 handler:NULL];
    expectation = nil;
}

- (void)_safelyOpenPipelineWithIdentifier:(NSString *)identifier executingBlock:(void (^)(TIPImagePipeline *pipeline))executingBlock
{
    @autoreleasepool {
        TIPImagePipeline *pipeline = [[TIPImagePipeline alloc] initWithIdentifier:identifier];
        XCTAssertNotNil(pipeline);

        executingBlock(pipeline);

        [self expectationForNotification:TIPImagePipelineDidTearDownImagePipelineNotification object:nil handler:^BOOL(NSNotification *note) {
            return [identifier isEqualToString:note.userInfo[TIPImagePipelineImagePipelineIdentifierNotificationKey]];
        }];
        [pipeline inspect:^(TIPImagePipelineInspectionResult * _Nullable result) {}];
        pipeline = nil;
    }
    [self waitForExpectationsWithTimeout:20 handler:nil];
}

- (void)_runFillingTheCaches:(TIPImagePipeline *)pipeline bps:(uint64_t)bps testCacheHits:(BOOL)testCacheHits
{
    id<TIPImageFetchDownloadProviderWithStubbingSupport> provider = (id<TIPImageFetchDownloadProviderWithStubbingSupport>)[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider;

    NSMutableArray *URLs = [NSMutableArray array];
    for (NSUInteger i = 0; i < 10; i++) {
        [URLs addObject:[TIPImagePipelineTests dummyURLWithPath:[NSUUID UUID].UUIDString]];
    }

    // First pass, load em up
    // Second pass (if testCacheHits), reload since older version will have been purged by full cache
    const NSUInteger numberOfRuns = (testCacheHits) ? 2 : 1;
    for (NSUInteger i = 0; i < numberOfRuns; i++) {
        for (NSURL *URL in URLs) {
            @autoreleasepool {
                TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
                request.imageType = TIPImageTypeJPEG;
                request.progressiveSource = YES;
                request.imageURL = URL;
                request.targetDimensions = kCarnivalImageDimensions;
                request.targetContentMode = UIViewContentModeScaleToFill;
                TIPImagePipelineTestContext *context = [[TIPImagePipelineTestContext alloc] init];
                [self _stubRequest:request bitrate:bps resumable:YES];
                TIPImageFetchOperation *op = [pipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
                [op waitUntilFinishedWithoutBlockingRunLoop];
                [provider removeDownloadStubForRequestURL:request.imageURL];
                XCTAssertEqual(op.state, TIPImageFetchOperationStateSucceeded);
                XCTAssertEqual(context.finalSource, TIPImageLoadSourceNetwork);
            }
        }
    }

    // visit in reverse order
    NSUInteger memMatches = 0;
    NSUInteger diskMatches = 0;
    for (NSURL *URL in URLs.reverseObjectEnumerator) {
        TIPImageLoadSource source = TIPImageLoadSourceUnknown;
        @autoreleasepool {
            TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
            request.imageType = TIPImageTypeJPEG;
            request.progressiveSource = YES;
            request.imageURL = URL;
            request.targetDimensions = kCarnivalImageDimensions;
            request.targetContentMode = UIViewContentModeScaleToFill;
            TIPImagePipelineTestContext *context = [[TIPImagePipelineTestContext alloc] init];
            [self _stubRequest:request bitrate:bps resumable:YES];
            TIPImageFetchOperation *op = [pipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
            [op waitUntilFinishedWithoutBlockingRunLoop];
            [provider removeDownloadStubForRequestURL:request.imageURL];
            XCTAssertEqual(op.state, TIPImageFetchOperationStateSucceeded);
            source = op.finalResult.imageSource;
            if (source == TIPImageLoadSourceMemoryCache) {
                memMatches++;
            } else if (source == TIPImageLoadSourceDiskCache) {
                diskMatches++;
            } else {
                break;
            }
        }
    }

    if (testCacheHits) {
        XCTAssertGreaterThan(memMatches, (NSUInteger)0);
        XCTAssertGreaterThan(diskMatches, (NSUInteger)0);
    }
}

- (void)testMergingFetches
{
    TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
    request.imageType = TIPImageTypeJPEG;
    request.progressiveSource = YES;
    request.imageURL = [TIPImagePipelineTests dummyURLWithPath:[NSUUID UUID].UUIDString];
    request.targetDimensions = kCarnivalImageDimensions;
    request.targetContentMode = UIViewContentModeScaleAspectFit;

    [self _stubRequest:request bitrate:2 * kMegaBits resumable:YES];

    TIPImageFetchOperation *op1 = nil;
    TIPImageFetchOperation *op2 = nil;
    TIPImagePipelineTestContext *context1 = nil;
    TIPImagePipelineTestContext *context2 = nil;

    [sPipeline.memoryCache clearAllImages:NULL];
    [sPipeline.diskCache clearAllImages:NULL];
    [sPipeline.renderedCache clearAllImages:NULL];
    context1 = [[TIPImagePipelineTestContext alloc] init];
    context2 = [[TIPImagePipelineTestContext alloc] init];
    context1.otherContext = context2;
    op1 = [sPipeline undeprecatedFetchImageWithRequest:request context:context1 delegate:self];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    op2 = [sPipeline undeprecatedFetchImageWithRequest:request context:context2 delegate:self];
    [op1 waitUntilFinishedWithoutBlockingRunLoop];
    [op2 waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertEqual(context1.didStart, YES);
    XCTAssertNotNil(context1.finalImageContainer);
    XCTAssertNil(context1.finalError);
    XCTAssertEqual(context1.finalSource, TIPImageLoadSourceNetwork);
    XCTAssertEqualObjects(context1.finalImageContainer, op1.finalResult.imageContainer);
    XCTAssertEqual(context1.finalSource, op1.finalResult.imageSource);
    XCTAssertEqual(op1.state, TIPImageFetchOperationStateSucceeded);
    XCTAssertNotNil(context1.associatedDownloadContext);

    XCTAssertEqual(context2.didStart, YES);
    XCTAssertNotNil(context2.finalImageContainer);
    XCTAssertNil(context2.finalError);
    XCTAssertEqual(context2.finalSource, TIPImageLoadSourceNetwork);
    XCTAssertEqualObjects(context2.finalImageContainer, op2.finalResult.imageContainer);
    XCTAssertEqual(context2.finalSource, op2.finalResult.imageSource);
    XCTAssertEqual(op2.state, TIPImageFetchOperationStateSucceeded);
    XCTAssertNotNil(context2.associatedDownloadContext);

    XCTAssertEqual((__bridge void *)context1.associatedDownloadContext, (__bridge void *)context2.associatedDownloadContext);

    // Cancel original

    [sPipeline.memoryCache clearAllImages:NULL];
    [sPipeline.diskCache clearAllImages:NULL];
    [sPipeline.renderedCache clearAllImages:NULL];
    context1 = [[TIPImagePipelineTestContext alloc] init];
    context1.shouldCancelOnOtherContextFirstProgress = YES;
    context2 = [[TIPImagePipelineTestContext alloc] init];
    context1.otherContext = context2;
    op1 = [sPipeline undeprecatedFetchImageWithRequest:request context:context1 delegate:self];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    op2 = [sPipeline undeprecatedFetchImageWithRequest:request context:context2 delegate:self];
    [op1 waitUntilFinishedWithoutBlockingRunLoop];
    [op2 waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertEqual(context1.didStart, YES);
    XCTAssertNil(context1.finalImageContainer);
    XCTAssertNotNil(context1.finalError);
    XCTAssertEqual(op1.state, TIPImageFetchOperationStateCancelled);
    XCTAssertNotNil(context1.associatedDownloadContext);

    XCTAssertEqual(context2.didStart, YES);
    XCTAssertNotNil(context2.finalImageContainer);
    XCTAssertNil(context2.finalError);
    XCTAssertEqual(context2.finalSource, TIPImageLoadSourceNetwork);
    XCTAssertEqualObjects(context2.finalImageContainer, op2.finalResult.imageContainer);
    XCTAssertEqual(context2.finalSource, op2.finalResult.imageSource);
    XCTAssertEqual(op2.state, TIPImageFetchOperationStateSucceeded);
    XCTAssertNotNil(context2.associatedDownloadContext);

    XCTAssertEqual((__bridge void *)context1.associatedDownloadContext, (__bridge void *)context2.associatedDownloadContext);
}

- (void)testCopyingDiskEntry
{
    [sPipeline clearDiskCache];
    [sPipeline clearMemoryCaches];

    NSString *copyFinishedNotificationName = @"copy_finished";

    TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
    request.imageURL = [TIPImagePipelineTests dummyURLWithPath:[NSUUID UUID].UUIDString];
    request.imageType = TIPImageTypeJPEG;
    request.progressiveSource = NO;

    __block NSString *tempFile = nil;
    __block NSError *copyError = nil;
    XCTestExpectation *finisedCopyExpectation = nil;
    TIPImagePipelineCopyFileCompletionBlock completion = ^(NSString *temporaryFilePath, NSError *error) {
        tempFile = temporaryFilePath;
        copyError = error;

        NSTimeInterval delay = (tempFile != nil) ? 0.5 : 0.1;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:copyFinishedNotificationName object:request];
        });
    };

    [self _stubRequest:request bitrate:1024 * kMegaBits resumable:YES];

    // Attempt with empty caches

    tempFile = nil;
    copyError = nil;
    finisedCopyExpectation = [self expectationForNotification:copyFinishedNotificationName object:nil handler:NULL];
    [sPipeline copyDiskCacheFileWithIdentifier:request.imageURL.absoluteString completion:completion];
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];
    XCTAssertNil(tempFile);
    XCTAssertNotNil(copyError);

    // Fill cache with item

    TIPImageFetchOperation *op = [sPipeline operationWithRequest:request context:nil completion:NULL];
    [sPipeline fetchImageWithOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertNotNil(op.finalResult.imageContainer);

    // Attempt with cache entries

    tempFile = nil;
    copyError = nil;
    finisedCopyExpectation = [self expectationForNotification:copyFinishedNotificationName object:nil handler:NULL];
    [sPipeline copyDiskCacheFileWithIdentifier:request.imageURL.absoluteString completion:completion];
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];
    XCTAssertNotNil(tempFile);
    XCTAssertNil(copyError);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:tempFile]);

    // Attempt with no disk cache entry

    tempFile = nil;
    copyError = nil;
    [sPipeline clearDiskCache];
    finisedCopyExpectation = [self expectationForNotification:copyFinishedNotificationName object:nil handler:NULL];
    [sPipeline copyDiskCacheFileWithIdentifier:request.imageURL.absoluteString completion:completion];
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];
    XCTAssertNil(tempFile);
    XCTAssertNotNil(copyError);
}

- (void)testGettingKnownPipelines
{
    TestImageStoreRequest *storeRequest = [[TestImageStoreRequest alloc] init];
    storeRequest.imageFilePath = [[self class] pathForImageOfType:TIPImageTypeJPEG progressive:NO];
    storeRequest.imageURL = [[self class] dummyURLWithPath:@"dummy.image.jpg"];
    NSString *signalIdentifier = [NSString stringWithFormat:@"%@", @(time(NULL))];
    __block XCTestExpectation *expectation = nil;
    __block NSSet *knownIds = nil;
    __block BOOL didStore = NO;
    void (^getKnownImagePiplineIdentifiers)(void) = ^ {
        expectation = [self expectationWithDescription:@"Waiting for known image pipeline identifiers"];
        [TIPImagePipeline getKnownImagePipelineIdentifiers:^(NSSet *identifiers) {
            knownIds = [identifiers copy];
            /*NSLog(@"Known Image Pipeline Identifiers: %@", knownIds.allObjects);*/
            [expectation fulfill];
        }];
        [self waitForExpectationsWithTimeout:20.0 handler:NULL];
    };

    // 1) Assert the pipeline we are looking for doesn't exist

    getKnownImagePiplineIdentifiers();
    XCTAssertFalse([knownIds containsObject:signalIdentifier]);

    // 2) Create a pipeline and store an image, assert it does now exist

    expectation = [self expectationWithDescription:@"Storing Image"];
    TIPImagePipeline *pipeline = [[TIPImagePipeline alloc] initWithIdentifier:signalIdentifier];
    [pipeline storeImageWithRequest:storeRequest completion:^(NSObject<TIPDependencyOperation> *storeOp, BOOL succeeded, NSError *error) {
        didStore = succeeded;
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:20.0 handler:NULL];
    getKnownImagePiplineIdentifiers();
    XCTAssertTrue([knownIds containsObject:signalIdentifier]);

    // 3) Clear the pipeline and dealloc, assert it no longer exists

    [pipeline clearDiskCache];
    pipeline = nil;
    getKnownImagePiplineIdentifiers();
    XCTAssertFalse([knownIds containsObject:signalIdentifier]);
}

- (void)testCrossPipelineLoad
{
    NSString *pipelineIdentifier1 = @"cross.pipeline.1";
    NSString *pipelineIdentifier2 = @"cross.pipeline.2";
    TIPImagePipeline *pipeline1 = [[TIPImagePipeline alloc] initWithIdentifier:pipelineIdentifier1];
    TIPImagePipeline *pipeline2 = [[TIPImagePipeline alloc] initWithIdentifier:pipelineIdentifier2];
    [pipeline1 clearDiskCache];
    [pipeline2 clearDiskCache];

    __block TIPImageLoadSource loadSource;
    XCTestExpectation *expectation;
    TIPImageFetchOperation *op;
    NSURL *URL = [NSURL URLWithString:@"http://cross.pipeline.com/image.jpg"];
    NSString *imagePath = [[self class] pathForImageOfType:TIPImageTypeJPEG progressive:NO];
    TestImageStoreRequest *storeRequest = [[TestImageStoreRequest alloc] init];
    storeRequest.imageURL = URL;
    storeRequest.imageFilePath = imagePath;
    TIPImagePipelineTestFetchRequest *fetchRequest = [[TIPImagePipelineTestFetchRequest alloc] init];
    fetchRequest.imageURL = URL;
    fetchRequest.imageType = TIPImageTypeJPEG;
    fetchRequest.progressiveSource = NO;

    [self _stubRequest:fetchRequest bitrate:0 resumable:YES];

    expectation = [self expectationWithDescription:@"Cross Pipeline Fetch Image 1"];
    op = [pipeline2 operationWithRequest:fetchRequest context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        [expectation fulfill];
    }];
    [pipeline2 fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceNetwork, loadSource);

    [pipeline2 clearDiskCache];
    [pipeline2 clearMemoryCaches];
    expectation = [self expectationWithDescription:@"Clear Caches"];
    [pipeline2 inspect:^(TIPImagePipelineInspectionResult *result) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];

    expectation = [self expectationWithDescription:@"Cross Pipeline Store Image"];
    [pipeline1 storeImageWithRequest:storeRequest completion:^(NSObject<TIPDependencyOperation> *storeOp, BOOL succeeded, NSError *error) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];

    expectation = [self expectationWithDescription:@"Cross Pipeline Fetch Image 2"];
    op = [pipeline2 operationWithRequest:fetchRequest context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        [expectation fulfill];
    }];
    [pipeline2 fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceDiskCache, loadSource);

    [pipeline1 clearDiskCache];
    [pipeline2 clearDiskCache];
    pipeline1 = nil;
    pipeline2 = nil;
}

- (void)testRenamedEntry
{
    NSString *pipelineIdentifier = @"dummy.pipeline";
    TIPImagePipeline *pipeline = [[TIPImagePipeline alloc] initWithIdentifier:pipelineIdentifier];
    [pipeline clearDiskCache];

    __block TIPImageLoadSource loadSource;
    __block NSError *loadError;
    XCTestExpectation *expectation;
    TIPImageFetchOperation *op;
    NSURL *URL1 = [NSURL URLWithString:@"http://dummy.pipeline.com/image.jpg"];
    NSURL *URL2 = [NSURL URLWithString:@"fake://fake.pipeline.com/fake.jpg"];

    TIPImagePipelineTestFetchRequest *fetchRequest1 = [[TIPImagePipelineTestFetchRequest alloc] init];
    fetchRequest1.imageURL = URL1;
    fetchRequest1.imageType = TIPImageTypeJPEG;
    fetchRequest1.progressiveSource = NO;

    TIPImagePipelineTestFetchRequest *fetchRequest2 = [[TIPImagePipelineTestFetchRequest alloc] init];
    fetchRequest2.imageURL = URL1;
    fetchRequest2.imageIdentifier = [URL2 absoluteString];
    fetchRequest2.imageType = TIPImageTypeJPEG;
    fetchRequest2.progressiveSource = NO;
    fetchRequest2.loadingSources = TIPImageFetchLoadingSourcesAll & ~(TIPImageFetchLoadingSourceNetwork | TIPImageFetchLoadingSourceNetworkResumed); // no network!

    [self _stubRequest:fetchRequest1 bitrate:0 resumable:YES];
    [self _stubRequest:fetchRequest2 bitrate:0 resumable:NO]; // just to ensure we don't hit the network

    expectation = [self expectationWithDescription:@"Pipeline Fetch Image 1"];
    op = [pipeline operationWithRequest:fetchRequest1 context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        loadError = error;
        [expectation fulfill];
    }];
    [pipeline fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceNetwork, loadSource);
    XCTAssertNil(loadError);

    expectation = [self expectationWithDescription:@"Pipeline Fetch Image 2"];
    op = [pipeline operationWithRequest:fetchRequest2 context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        loadError = error;
        [expectation fulfill];
    }];
    [pipeline fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceUnknown, loadSource);
    XCTAssertNotNil(loadError);

    expectation = [self expectationWithDescription:@"Move Image"];
    [pipeline changeIdentifierForImageWithIdentifier:[URL1 absoluteString] toIdentifier:[URL2 absoluteString] completion:^(NSObject<TIPDependencyOperation> *moveOp, BOOL succeeded, NSError *error) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];

    expectation = [self expectationWithDescription:@"Pipeline Fetch Image 2"];
    op = [pipeline operationWithRequest:fetchRequest2 context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        loadError = error;
        [expectation fulfill];
    }];
    [pipeline fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceDiskCache, loadSource);
    XCTAssertNil(loadError);

    expectation = [self expectationWithDescription:@"Pipeline Fetch Image 1"];
    op = [pipeline operationWithRequest:fetchRequest1 context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        loadError = error;
        [expectation fulfill];
    }];
    [pipeline fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceNetwork, loadSource); // Not cache!
    XCTAssertNil(loadError);

    [pipeline clearDiskCache];
    [pipeline clearMemoryCaches];
    expectation = [self expectationWithDescription:@"Clear Caches"];
    [pipeline inspect:^(TIPImagePipelineInspectionResult *result) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    pipeline = nil;
}

- (void)testInvalidPseudoFilePathFetch
{
    TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
    request.imageType = TIPImageTypeJPEG;
    request.progressiveSource = YES;
    request.imageURL = [TIPImagePipelineTests dummyURLWithPath:[NSUUID UUID].UUIDString];
    request.targetDimensions = kCarnivalImageDimensions;
    request.targetContentMode = UIViewContentModeScaleAspectFit;
    request.cannedImageFilePath = [request.cannedImageFilePath stringByAppendingPathExtension:@"dne"];

    [self _stubRequest:request bitrate:1 * kMegaBits resumable:YES];

    TIPImageFetchOperation *op = nil;
    TIPImagePipelineTestContext *context = nil;

    [sPipeline.memoryCache clearAllImages:NULL];
    [sPipeline.diskCache clearAllImages:NULL];
    [sPipeline.renderedCache clearAllImages:NULL];
    context = [[TIPImagePipelineTestContext alloc] init];
    op = [sPipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
    [op waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertNil(op.finalResult.imageContainer);
    XCTAssertNotNil(op.error);

    TIPImageFetchMetricInfo *metricInfo = [op.metrics metricInfoForSource:TIPImageLoadSourceNetwork];
    (void)metricInfo;
}

#pragma mark Delegate

- (void)tip_imageFetchOperationDidStart:(TIPImageFetchOperation *)op
{
    TIPImagePipelineTestContext *context = op.context;
    context.didStart = YES;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op willAttemptToLoadFromSource:(TIPImageLoadSource)source
{
    TIPImagePipelineTestContext *context = op.context;
    NSArray *existing = context.hitLoadSources ?: @[];
    context.hitLoadSources = [existing arrayByAddingObject:@(source)];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadPreviewImage:(id<TIPImageFetchResult>)previewResult completion:(TIPImageFetchDidLoadPreviewCallback)completion
{
    TIPImagePipelineTestContext *context = op.context;
    context.didProvidePreviewCheck = YES;

    completion(context.shouldCancelOnPreview ? TIPImageFetchPreviewLoadedBehaviorStopLoading : TIPImageFetchPreviewLoadedBehaviorContinueLoading);
}

- (BOOL)tip_imageFetchOperation:(TIPImageFetchOperation *)op shouldLoadProgressivelyWithIdentifier:(NSString *)identifier URL:(NSURL *)URL imageType:(NSString *)imageType originalDimensions:(CGSize)originalDimensions
{
    TIPImagePipelineTestContext *context = op.context;
    context.didMakeProgressiveCheck = YES;
    return context.shouldSupportProgressiveLoading;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didUpdateProgressiveImage:(id<TIPImageFetchResult>)progressiveResult progress:(float)progress
{
    TIPImagePipelineTestContext *context = op.context;
    context.progressiveProgressCount++;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFirstAnimatedImageFrame:(id<TIPImageFetchResult>)progressiveResult progress:(float)progress
{
    TIPImagePipelineTestContext *context = op.context;
    context.firstAnimatedFrameProgress = progress;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didUpdateProgress:(float)progress
{
    TIPImagePipelineTestContext *context = op.context;
    context.normalProgressCount++;
    if (context.firstProgress == 0.0f) {
        context.firstProgress = progress;
    }
    if (!context.associatedDownloadContext) {
        context.associatedDownloadContext = [op associatedDownloadContext];
    }
    if (progress > context.cancelPoint) {
        [op cancel];
    }
    if (context.shouldCancelOnOtherContextFirstProgress && context.otherContext.firstProgress > 0.0f) {
        [op cancel];
    }
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFinalImage:(id<TIPImageFetchResult>)finalResult
{
    TIPImagePipelineTestContext *context = op.context;
    context.finalImageContainer = finalResult.imageContainer;
    context.finalSource = finalResult.imageSource;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didFailToLoadFinalImage:(NSError *)error
{
    TIPImagePipelineTestContext *context = op.context;
    context.finalError = error;
}

@end

@implementation TIPImagePipelineTestFetchRequest

- (instancetype)init
{
    self = [super init];
    if (self) {
        _options = TIPImageFetchNoOptions;
        _targetContentMode = UIViewContentModeCenter;
        _targetDimensions = CGSizeZero;
        _loadingSources = TIPImageFetchLoadingSourcesAll;
    }
    return self;
}

- (NSString *)cannedImageFilePath
{
    return _cannedImageFilePath ?: [TIPImagePipelineTests pathForImageOfType:self.imageType progressive:self.progressiveSource];
}

- (NSDictionary *)progressiveLoadingPolicies
{
    NSMutableDictionary *policies = [NSMutableDictionary dictionaryWithCapacity:2];
    if (self.jp2ProgressiveLoadingPolicy) {
        policies[TIPImageTypeJPEG2000] = self.jp2ProgressiveLoadingPolicy;
    }
    if (self.jpegProgressiveLoadingPolicy) {
        policies[TIPImageTypeJPEG] = self.jpegProgressiveLoadingPolicy;
    }
    return policies;
}

@end

@implementation TIPImagePipelineTestContext

- (instancetype)init
{
    if (self = [super init]) {
        _cancelPoint = 2.0f;
    }
    return self;
}

- (NSUInteger)expectedFrameCount
{
    if (_expectedFrameCount) {
        return _expectedFrameCount;
    }

    return self.shouldSupportAnimatedLoading ? kFireworksFrameCount : 1;
}

@end

@implementation TIPImagePipeline (Undeprecated)

- (nonnull TIPImageFetchOperation *)undeprecatedFetchImageWithRequest:(nonnull id<TIPImageFetchRequest>)request context:(nullable id)context delegate:(nullable id<TIPImageFetchDelegate>)delegate
{
    TIPImageFetchOperation *op = [self operationWithRequest:request context:context delegate:delegate];
    [self fetchImageWithOperation:op];
    return op;
}

- (nonnull TIPImageFetchOperation *)undeprecatedFetchImageWithRequest:(nonnull id<TIPImageFetchRequest>)request context:(nullable id)context completion:(nullable TIPImagePipelineFetchCompletionBlock)completion
{
    TIPImageFetchOperation *op = [self operationWithRequest:request context:context completion:completion];
    [self fetchImageWithOperation:op];
    return op;
}

@end
