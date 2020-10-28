//
//  TIPProblematicImagesTest.m
//  TwitterImagePipeline
//
//  Created on 6/1/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPGlobalConfiguration.h"
#import "TIPImageFetchDownloadInternal.h"
#import "TIPImageFetchMetrics.h"
#import "TIPImageFetchOperation+Project.h"
#import "TIPImageFetchRequest.h"
#import "TIPImagePipeline+Project.h"
#import "TIPPartialImage.h"
#import "TIPTests.h"
#import "UIImage+TIPAdditions.h"

@import CoreImage;
@import ImageIO;
@import MobileCoreServices;
@import XCTest;

NS_INLINE NSData * __nullable UIImagePNGRepresentationUndeprecated(UIImage * __nonnull image)
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return UIImagePNGRepresentation(image);
#pragma clang diagnostic pop
}

@interface TIPImagePipelineTestSuccessWithErrorDownloadProvider : NSObject <TIPImageFetchDownloadProvider>
@property (nonatomic) NSData *downloadData;
@property (nonatomic) NSError *downloadError;
@end

@interface TIPImagePipelineTestProblemHandler : NSObject <TIPProblemObserver>
@property (nonatomic) XCTestExpectation *expectation;
@property (nonatomic, copy) NSString *problemToExpect;
@property (nonatomic, copy) NSDictionary *problemUserInfoSeen;
@end

@interface TIPImagePipelineTestFetchRequest : NSObject <TIPImageFetchRequest>
@property (nonatomic) NSURL *imageURL;
@property (nonatomic, copy) NSString *cannedImageFilePath;
@end

@interface TIPProblematicImagesTest : XCTestCase
@end

// https://o.twimg.com/2/proxy.jpg?t=HBhcaHR0cHM6Ly9jZG4uc2hvcGlmeS5jb20vcy9maWxlcy8xLzExNDkvNDc4MC9wcm9kdWN0cy8yNTE1XzEwMjR4MTAyNC5qcGc_MTIwOTg2OTg3MzMxMzE4ODM2MTgUwAcUxAgAFgASAA&s=KsBAcdWnqBlhzTqfi80_rZ4Yek7YubqUu0MLIBeuZpE
#define kPINK_OUTFIT_JPEG_IMAGE_NAME            @"pink_outfit"
#define kPINK_OUTFIT_DIMENSIONS                 CGSizeMake(480, 546)
#define kPINK_OUTFIT_TARGET_DIMENSIONS          CGSizeMake(135, 153)
#define kPINK_OUTFIT_TARGET_CONTENT_MODE        UIViewContentModeScaleAspectFit
#define kPINK_OUTFIT_EXPECTED_SCALED_DIMENSIONS CGSizeMake(135, 153)

typedef struct {
    CGSize originalSize;
    CGSize targetSize;
    CGSize expectedScaledFitSizes[4];
    CGSize expectedScaledFillSizes[4];
} TIPImageScalingTestCase;

static UIImage *sPinkOutfitOriginalImage = nil;
static NSData *sProblematicAvatarData = nil;
static NSString *sProblematicAvatarPath = nil;

@implementation TIPProblematicImagesTest

+ (void)setUp
{
    NSBundle *thisBundle = TIPTestsResourceBundle();

    NSString *pinkImagePath = [thisBundle pathForResource:kPINK_OUTFIT_JPEG_IMAGE_NAME ofType:@"jpg"];
    sPinkOutfitOriginalImage = [UIImage imageWithContentsOfFile:pinkImagePath];

    sProblematicAvatarPath = [thisBundle pathForResource:@"logo_only_final_reasonably_small" ofType:@"jpg"];
    sProblematicAvatarData = [NSData dataWithContentsOfFile:sProblematicAvatarPath];

    TIPGlobalConfiguration *globalConfig = [TIPGlobalConfiguration sharedInstance];
    globalConfig.imageFetchDownloadProvider = [[TIPTestsImageFetchDownloadProviderOverrideClass() alloc] init];
}

+ (void)tearDown
{
    sPinkOutfitOriginalImage = nil;
    sProblematicAvatarData = nil;
    sProblematicAvatarPath = nil;
    [TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider = nil;
}

- (void)testSizingImage
{
    UIImage *scaledImage = [sPinkOutfitOriginalImage tip_scaledImageWithTargetDimensions:kPINK_OUTFIT_TARGET_DIMENSIONS contentMode:kPINK_OUTFIT_TARGET_CONTENT_MODE];
    CGSize computedDimensions = TIPDimensionsScaledToTargetSizing(kPINK_OUTFIT_DIMENSIONS, kPINK_OUTFIT_TARGET_DIMENSIONS, kPINK_OUTFIT_TARGET_CONTENT_MODE);
    CGSize endDimensions = TIPDimensionsFromSizeScaled(scaledImage.size, scaledImage.scale);
    XCTAssertTrue(CGSizeEqualToSize(kPINK_OUTFIT_EXPECTED_SCALED_DIMENSIONS, endDimensions), @"%@ != %@", NSStringFromCGSize(kPINK_OUTFIT_EXPECTED_SCALED_DIMENSIONS), NSStringFromCGSize(endDimensions));
    XCTAssertTrue(CGSizeEqualToSize(kPINK_OUTFIT_EXPECTED_SCALED_DIMENSIONS, computedDimensions), @"%@ != %@", NSStringFromCGSize(kPINK_OUTFIT_EXPECTED_SCALED_DIMENSIONS), NSStringFromCGSize(computedDimensions));
}

- (void)testSizingDimensions
{
    const CGFloat scales[] = { 0.5, 1.0, 2.0, 3.0 };
    const UIViewContentMode contentModes[] = { UIViewContentModeScaleAspectFit, UIViewContentModeScaleAspectFill };

    TIPImageScalingTestCase cases[] = {
        {
            .originalSize = CGSizeMake(480, 546),
            .targetSize = CGSizeMake(135, 153),
            .expectedScaledFitSizes = {
                CGSizeMake(136, 154), // 0.5
                CGSizeMake(135, 153), // 1.0
                CGSizeMake(134.5, 153), // 2.0
                CGSizeMake(134.66666f, 153), // 3.0
            },
            .expectedScaledFillSizes = {
                CGSizeMake(136, 154), // 0.5
                CGSizeMake(135, 154), // 1.0
                CGSizeMake(135, 153.5f), // 2.0
                CGSizeMake(135, 153.6666f), // 3.0
            },
        },
        {
            .originalSize = CGSizeMake(135, 153),
            .targetSize = CGSizeMake(480, 546),
            .expectedScaledFitSizes = {
                CGSizeMake(480, 544), // 0.5
                CGSizeMake(480, 544), // 1.0
                CGSizeMake(480, 544), // 2.0
                CGSizeMake(480, 544), // 3.0
            },
            .expectedScaledFillSizes = {
                CGSizeMake(482, 546), // 0.5
                CGSizeMake(482, 546), // 1.0
                CGSizeMake(482, 546), // 2.0
                CGSizeMake(481.66666f, 546), // 3.0
            },
        },
        {
            .originalSize = CGSizeMake(135, 154),
            .targetSize = CGSizeMake(480, 546),
            .expectedScaledFitSizes = {
                CGSizeMake(480, 544), // 0.5
                CGSizeMake(479, 546), // 1.0
                CGSizeMake(478.5, 546), // 2.0
                CGSizeMake(478.66666f, 546), // 3.0
            },
            .expectedScaledFillSizes = {
                CGSizeMake(482, 546), // 0.5
                CGSizeMake(480, 548), // 1.0
                CGSizeMake(480, 547.5f), // 2.0
                CGSizeMake(480, 547.6666f), // 3.0
            },
        },
    };

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        TIPImageScalingTestCase testCase = cases[i];
        for (size_t scaleI = 0; scaleI < 4; scaleI++) {
            CGFloat scale = scales[scaleI];
            for (size_t contentModeI = 0; contentModeI < 2; contentModeI++) {
                UIViewContentMode contentMode = contentModes[contentModeI];
                CGSize expectedScaledSize = (UIViewContentModeScaleAspectFit == contentMode) ? testCase.expectedScaledFitSizes[scaleI] : testCase.expectedScaledFillSizes[scaleI];
                CGSize scaledSize = TIPSizeScaledToTargetSizing(testCase.originalSize, testCase.targetSize, contentMode, scale);
                XCTAssertEqualWithAccuracy(scaledSize.width, expectedScaledSize.width, 0.001, @"%@ != %@ (for scale %f)", NSStringFromCGSize(scaledSize), NSStringFromCGSize(expectedScaledSize), scale);
                XCTAssertEqualWithAccuracy(scaledSize.height, expectedScaledSize.height, 0.001, @"%@ != %@ (for scale %f)", NSStringFromCGSize(scaledSize), NSStringFromCGSize(expectedScaledSize), scale);
            }
        }
    }
}

- (void)testProblematicAvatarThrows
{
    if (sizeof(NSInteger) == sizeof(int32_t)) {
        // 32-bit devices yield an abort instead of an exception :(
        return;
    }

    NSData *imageData = sProblematicAvatarData;
    NSDictionary *options = @{ (NSString *)kCGImageSourceShouldCache : @NO };
    CGImageSourceRef imageSourceRef = CGImageSourceCreateIncremental((__bridge CFDictionaryRef)options);
    CGImageSourceUpdateData(imageSourceRef, (__bridge CFDataRef)imageData, NO);
    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSourceRef, 0, NULL);
    XCTAssertTrue(properties != NULL);
    if (properties) {
        XCTAssertGreaterThan(CFDictionaryGetCount(properties), (CFIndex)0);
        CFRelease(properties);
    }
    CFRelease(imageSourceRef);
}

- (void)testProblematicAvatarHandledByTIP
{
    /**
     This avatar caused big issues on iOS 9 and below.
     Now that TIP is iOS 10+, it should no longer be an issue,
     but we will keep the unit test to ensure we don't regress.
     */

    if (sizeof(NSInteger) == sizeof(int32_t)) {
        // 32-bit devices yield an abort instead of an exception :(
        return;
    }

    UIImage *image2 = nil;
    UIImage *image1 = [UIImage imageWithData:sProblematicAvatarData];

    TIPPartialImage *partialImage = [[TIPPartialImage alloc] initWithExpectedContentLength:sProblematicAvatarData.length];
    [partialImage appendData:sProblematicAvatarData final:NO];
    image2 = [[partialImage renderImageWithMode:TIPImageDecoderRenderModeFullFrameProgress targetDimensions:CGSizeZero targetContentMode:UIViewContentModeCenter decoded:YES] image];
    XCTAssertNotNil(image2); // image can render

    [partialImage appendData:nil final:YES];
    image2 = [[partialImage renderImageWithMode:TIPImageDecoderRenderModeFullFrameProgress targetDimensions:CGSizeZero targetContentMode:UIViewContentModeCenter decoded:YES] image];
    XCTAssertNotNil(image2);

    XCTAssertTrue(CGSizeEqualToSize([image1 tip_dimensions], [image2 tip_dimensions]));

    NSData *pngData1 = UIImagePNGRepresentationUndeprecated(image1);
    NSData *pngData2 = UIImagePNGRepresentationUndeprecated(image2);

    // (╯°□°)╯︵ ┻━┻
    // These images will serialize to different bytes (wasn't an issue prior to iOS 10)...
    // ...specifically an image with scale will have DPI info and PixelsPerMeter info.
    // Recreating an imageWithData: image with a scale will get them to be consistent.
    if (image1.scale != image2.scale) {
        UIImage *roundTrip1 = [UIImage imageWithData:pngData1];
        UIImage *roundTrip2 = [UIImage imageWithData:pngData2];
        XCTAssertEqual(roundTrip1.scale, roundTrip2.scale);
        XCTAssertTrue(CGSizeEqualToSize(roundTrip1.size, roundTrip2.size));

        image1 = [UIImage imageWithData:sProblematicAvatarData scale:image2.scale];
        pngData1 = UIImagePNGRepresentationUndeprecated(image1);

        UIImage *imageTest = [UIImage imageWithData:pngData1 scale:image2.scale];
        XCTAssertTrue(CGSizeEqualToSize(imageTest.size, image2.size));
    }

    XCTAssertEqualObjects(pngData1, pngData2);
}

- (void)testProblematicAvatarFetch
{
    if (sizeof(NSInteger) == sizeof(int32_t)) {
        // 32-bit devices yield an abort instead of an exception :(
        return;
    }

    // Prior to iOS 10 (when this issue was fixed) it was possible
    // to have a malformed image trigger an exception (32-bit unit
    // tests won't catch the exception).
    //
    // TIP adds a protection around ImageIO code (in the codecs) to
    // avoid crashing and salvage the decoding.

    id<TIPImageFetchDownloadProviderWithStubbingSupport> provider = (id<TIPImageFetchDownloadProviderWithStubbingSupport>)[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider;

    XCTAssertNotNil(sProblematicAvatarPath);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:sProblematicAvatarPath], @"%@", sProblematicAvatarPath);
    TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
    request.imageURL = [NSURL URLWithString:@"https://pbs.twimg.com/profile_images/1205320369/logo_only_final_reasonably_small.jpg"];
    request.cannedImageFilePath = sProblematicAvatarPath;
    NSData *cannedImageData = [NSData dataWithContentsOfFile:request.cannedImageFilePath options:NSDataReadingMappedIfSafe error:NULL];

    __block NSError *error;
    __block TIPImageContainer *container;
    TIPImagePipeline *pipeline = [[TIPImagePipeline alloc] initWithIdentifier:@"problem.avatar"];
    TIPImageFetchOperation *op = nil;
    TIPImageFetchMetricInfo *metricInfo = nil;
    [pipeline clearDiskCache];
    [pipeline clearMemoryCaches];

    // Slow load may or may not encounter an exception
    // Either way, the image should be loaded on completion

    [provider addDownloadStubForRequestURL:request.imageURL responseData:cannedImageData responseMIMEType:@"image/jpeg" shouldSupportResuming:YES suggestedBitrate:512 * 1000];
    op = [pipeline operationWithRequest:request context:nil completion:^(id<TIPImageFetchResult> result, NSError *theError) {
        container = result.imageContainer;
        error = theError;
    }];
    [pipeline fetchImageWithOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    [provider removeDownloadStubForRequestURL:request.imageURL];
    XCTAssertNil(error);
    XCTAssertNotNil(container.image);

    metricInfo = [op.metrics metricInfoForSource:TIPImageLoadSourceNetwork];
    XCTAssertNotNil(metricInfo);
    XCTAssertNil(error, @"%@\n%@", metricInfo.networkRequest, metricInfo.networkRequest.allHTTPHeaderFields);

    [pipeline clearDiskCache];
    [pipeline clearMemoryCaches];

    // Fast load DOES encounter an issue
    // But will be handled and still load

    [provider addDownloadStubForRequestURL:request.imageURL responseData:cannedImageData responseMIMEType:@"image/jpeg" shouldSupportResuming:YES suggestedBitrate:0];

    op = [pipeline operationWithRequest:request context:nil completion:^(id<TIPImageFetchResult> result, NSError *theError) {
        container = result.imageContainer;
        error = theError;
    }];
    [pipeline fetchImageWithOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    [provider removeDownloadStubForRequestURL:request.imageURL];
    XCTAssertNil(error);
    XCTAssertNotNil(container.image);
    metricInfo = [op.metrics metricInfoForSource:TIPImageLoadSourceNetwork];
    XCTAssertNotNil(metricInfo);
    XCTAssertNil(error, @"%@\n%@", metricInfo.networkRequest, metricInfo.networkRequest.allHTTPHeaderFields);

    [pipeline clearDiskCache];
    [pipeline clearMemoryCaches];
}

- (void)testCompletedDownloadWithError
{
    /**
     If the server yields an error despite all the data loading, we want TIP to be robust at
     catching these problems, reporting them, and continuing without a failure.
     */

    NSBundle *thisBundle = TIPTestsResourceBundle();
    NSString *imagePath = [thisBundle pathForResource:@"twitterfied" ofType:@"jpg"];
    NSData *imageData = [NSData dataWithContentsOfFile:imagePath];

    TIPImagePipelineTestSuccessWithErrorDownloadProvider *provider = [[TIPImagePipelineTestSuccessWithErrorDownloadProvider alloc] init];
    provider.downloadData = imageData;
    provider.downloadError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];

    TIPImagePipelineTestProblemHandler *problemObserver = [[TIPImagePipelineTestProblemHandler alloc] init];
    problemObserver.problemToExpect = TIPProblemImageDownloadedWithUnnecessaryError;

    id<TIPImageFetchDownloadProvider> originalProvider = [TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider;
    [TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider = provider;
    id<TIPProblemObserver> originalProblemObserver = [TIPGlobalConfiguration sharedInstance].problemObserver;
    [TIPGlobalConfiguration sharedInstance].problemObserver = problemObserver;
    tip_defer(^{
        [TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider = originalProvider;
        [TIPGlobalConfiguration sharedInstance].problemObserver = originalProblemObserver;
    });

    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:imagePath]);
    TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
    request.imageURL = [NSURL URLWithString:@"https://dummy.twitter.com/some_path/image.jpg"];
    request.cannedImageFilePath = imagePath;

    __block NSError *error;
    __block id<TIPImageFetchResult> result;
    TIPImagePipeline *pipeline = [[TIPImagePipeline alloc] initWithIdentifier:@"error.image.complete"];
    TIPImageFetchOperation *op = nil;
    [pipeline clearDiskCache];
    [pipeline clearMemoryCaches];

    problemObserver.expectation = [self expectationWithDescription:@"Problem.Expectation"];
    op = [pipeline operationWithRequest:request context:nil completion:^(id<TIPImageFetchResult> theResult, NSError *theError) {
        result = theResult;
        error = theError;
    }];
    [pipeline fetchImageWithOperation:op];
    [self waitForExpectations:@[problemObserver.expectation] timeout:10.0];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertNil(error);
    XCTAssertNotNil(result.imageContainer.image);
    XCTAssertEqual(result.imageSource, TIPImageLoadSourceNetwork);
    [pipeline clearMemoryCaches];

    op = [pipeline operationWithRequest:request context:nil completion:^(id<TIPImageFetchResult> theResult, NSError *theError) {
        result = theResult;
        error = theError;
    }];
    [pipeline fetchImageWithOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertNil(error);
    XCTAssertNotNil(result.imageContainer.image);
    XCTAssertEqual(result.imageSource, TIPImageLoadSourceDiskCache);
    [pipeline clearDiskCache];
    [pipeline clearMemoryCaches];
}

@end

@interface TIPImagePipelineTestSuccessWithErrorDownload : NSObject <TIPImageFetchDownload>

@property (nonatomic, readonly) NSData *downloadData;
@property (nonatomic, readonly) NSError *downloadError;

- (instancetype)initWithContext:(id<TIPImageFetchDownloadContext>)context downloadData:(NSData *)data downloadError:(NSError *)error;

@end

@implementation TIPImagePipelineTestSuccessWithErrorDownload

@synthesize context = _context;
@synthesize finalURLRequest = _finalURLRequest;

- (instancetype)initWithContext:(id<TIPImageFetchDownloadContext>)context downloadData:(NSData *)data downloadError:(NSError *)error
{
    if (self = [super init]) {
        _context = context;
        _downloadData = data;
        _downloadError = error;
    }
    return self;
}

- (void)start
{
    dispatch_async(self.context.downloadQueue, ^{
        [self.context.client imageFetchDownloadDidStart:self];
        [self.context.client imageFetchDownload:self
                                 hydrateRequest:self.context.originalRequest
                                     completion:^(NSError * _Nullable hError) {
            if (hError) {
                [self.context.client imageFetchDownload:self didCompleteWithError:hError];
                return;
            }

            [self.context.client imageFetchDownload:self authorizeRequest:self.context.hydratedRequest completion:^(NSError * _Nullable aError) {
                if (aError) {
                    [self.context.client imageFetchDownload:self didCompleteWithError:aError];
                    return;
                }

                NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
                headers[@"Content-Length"] = [@(self.downloadData.length) stringValue];
                headers[@"Content-Type"] = @"image/jpeg";
                headers[@"Accept-Ranges"] = @"bytes";
                headers[@"Last-Modified"] = @"Wed, 15 Nov 1995 04:58:08 GMT";
                NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.context.hydratedRequest.URL
                                                                          statusCode:200
                                                                         HTTPVersion:@"http/1.1"
                                                                        headerFields:headers];
                [self.context.client imageFetchDownload:self didReceiveURLResponse:response];
                dispatch_async(self.context.downloadQueue, ^{
                    [self.context.client imageFetchDownload:self didReceiveData:self.downloadData];
                    dispatch_async(self.context.downloadQueue, ^{
                        [self.context.client imageFetchDownload:self didCompleteWithError:self.downloadError];
                    });
                });
            }];
        }];
    });
}

- (void)cancelWithDescription:(NSString *)cancelDescription
{
    // noop
}

- (void)discardContext
{
    _context = nil;
}

@end

@implementation TIPImagePipelineTestSuccessWithErrorDownloadProvider

- (id<TIPImageFetchDownload>)imageFetchDownloadWithContext:(id<TIPImageFetchDownloadContext>)context
{
    return [[TIPImagePipelineTestSuccessWithErrorDownload alloc] initWithContext:context downloadData:self.downloadData downloadError:self.downloadError];
}

@end

@implementation TIPImagePipelineTestProblemHandler

- (void)tip_problemWasEncountered:(NSString *)problemName
                         userInfo:(NSDictionary<NSString *, id> *)userInfo
{
    if ([self.problemToExpect isEqualToString:problemName]) {
        self.problemUserInfoSeen = userInfo;
        if (self.expectation) {
            [self.expectation fulfill];
        }
    }
}

@end
