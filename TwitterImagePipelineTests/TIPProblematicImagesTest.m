//
//  TIPProblematicImagesTest.m
//  TwitterImagePipeline
//
//  Created on 6/1/16.
//  Copyright © 2016 Twitter. All rights reserved.
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

#define IS_IOS_10_OR_GREATER ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 10)

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
                CGSizeMake(135, 153), // 2.0
                CGSizeMake(134.66666f, 153), // 3.0
            },
            .expectedScaledFillSizes = {
                CGSizeMake(136, 154), // 0.5
                CGSizeMake(135, 153), // 1.0
                CGSizeMake(135, 153.5f), // 2.0
                CGSizeMake(135, 153.33333f), // 3.0
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
                CGSizeMake(481, 546), // 1.0
                CGSizeMake(481.5f, 546), // 2.0
                CGSizeMake(481.66666f, 546), // 3.0
            },
        },
        {
            .originalSize = CGSizeMake(135, 154),
            .targetSize = CGSizeMake(480, 546),
            .expectedScaledFitSizes = {
                CGSizeMake(480, 544), // 0.5
                CGSizeMake(479, 546), // 1.0
                CGSizeMake(479, 546), // 2.0
                CGSizeMake(478.66666f, 546), // 3.0
            },
            .expectedScaledFillSizes = {
                CGSizeMake(482, 546), // 0.5
                CGSizeMake(480, 547), // 1.0
                CGSizeMake(480, 547.5f), // 2.0
                CGSizeMake(480, 547.33333f), // 3.0
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
    if (IS_IOS_10_OR_GREATER) {
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSourceRef, 0, NULL);
        XCTAssertTrue(properties != NULL);
        if (properties) {
            XCTAssertGreaterThan(CFDictionaryGetCount(properties), (CFIndex)0);
            CFRelease(properties);
        }
    } else {
        XCTAssertThrows(CGImageSourceCopyPropertiesAtIndex(imageSourceRef, 0, NULL));
    }
    CFRelease(imageSourceRef);
}

- (void)testProblematicAvatarHandledByTIP
{
    if (sizeof(NSInteger) == sizeof(int32_t)) {
        // 32-bit devices yield an abort instead of an exception :(
        return;
    }

    UIImage *image2 = nil;
    UIImage *image1 = [UIImage imageWithData:sProblematicAvatarData];

    TIPPartialImage *partialImage = [[TIPPartialImage alloc] initWithExpectedContentLength:sProblematicAvatarData.length];
    [partialImage appendData:sProblematicAvatarData final:NO];
    if (IS_IOS_10_OR_GREATER) {
        // no exception will have triggered
    } else {
        // exception will have triggered
    }
    image2 = [[partialImage renderImageWithMode:TIPImageDecoderRenderModeFullFrameProgress decoded:YES] image];
    if (IS_IOS_10_OR_GREATER) {
        XCTAssertNotNil(image2); // image can render
    } else {
        XCTAssertNil(image2); // image cannot render
    }

    [partialImage appendData:nil final:YES];
    image2 = [[partialImage renderImageWithMode:TIPImageDecoderRenderModeFullFrameProgress decoded:YES] image];
    XCTAssertNotNil(image2);

    XCTAssertTrue(CGSizeEqualToSize([image1 tip_dimensions], [image2 tip_dimensions]));

    NSData *pngData1 = UIImagePNGRepresentation(image1);
    NSData *pngData2 = UIImagePNGRepresentation(image2);

    // (╯°□°)╯︵ ┻━┻
    // On iOS 10, these images will serialize to different bytes...
    // ...specifically an image with scale will have DPI info and PixelsPerMeter info.
    // Recreating an imageWithData: image with a scale will get them to be consistent.
    if (IS_IOS_10_OR_GREATER) {
        if (image1.scale != image2.scale) {
            UIImage *roundTrip1 = [UIImage imageWithData:pngData1];
            UIImage *roundTrip2 = [UIImage imageWithData:pngData2];
            XCTAssertEqual(roundTrip1.scale, roundTrip2.scale);
            XCTAssertTrue(CGSizeEqualToSize(roundTrip1.size, roundTrip2.size));

            image1 = [UIImage imageWithData:sProblematicAvatarData scale:image2.scale];
            pngData1 = UIImagePNGRepresentation(image1);

            UIImage *imageTest = [UIImage imageWithData:pngData1 scale:image2.scale];
            XCTAssertTrue(CGSizeEqualToSize(imageTest.size, image2.size));
        }
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
    // TIP adds a protection around ImageIO code (in the codecs) to
    // avoid crashing and salvage the decoding.
    //

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

@end
