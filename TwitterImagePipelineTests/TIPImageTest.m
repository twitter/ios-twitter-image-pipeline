//
//  TIPImageTest.m
//  TFNUtilities
//
//  Created on 2/19/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import <objc/runtime.h>
#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPImageCodecCatalogue.h"
#import "TIPImageContainer.h"
#import "TIPImageUtils.h"
#import "TIPTests.h"
#import "TIPXMP4Codec.h"
#import "TIPXWebPCodec.h"
#import "UIImage+TIPAdditions.h"

@import Foundation;
@import MobileCoreServices;
@import UIKit;
@import XCTest;

@interface TestParamSet : NSObject
@property (nonatomic) BOOL useFloat;
@property (nonatomic) size_t bytesPerComponent;
@property (nonatomic) CGImageAlphaInfo alphaInfo;
@property (nonatomic) uint32_t byteOrder;
+ (instancetype)floatParamSetWithAlphaInfo:(CGImageAlphaInfo)alphaInfo byteOrder:(uint32_t)byteOrder;
+ (instancetype)integerParamSetWithAlphaInfo:(CGImageAlphaInfo)alphaInfo byteOrder:(uint32_t)byteOrder bytesPerComponent:(size_t)bytesPerComponent;
@end

#define PARAM_SET_FLOAT(ai, bo) [TestParamSet floatParamSetWithAlphaInfo:(ai) byteOrder:(bo)]
#define PARAM_SET_INT(ai, bo)   [TestParamSet integerParamSetWithAlphaInfo:(ai) byteOrder:(bo) bytesPerComponent:1]

#define PLUG_IN_WEBP() \
TIPXWebPCodec *webpCodec = [[TIPXWebPCodec alloc] init]; \
[[TIPImageCodecCatalogue sharedInstance] setCodec:webpCodec forImageType:TIPXImageTypeWebP]; \
tip_defer(^{ \
    [[TIPImageCodecCatalogue sharedInstance] removeCodecForImageType:TIPXImageTypeWebP]; \
});

#define PLUG_IN_MP4() \
TIPXMP4Codec *mp4Codec = [[TIPXMP4Codec alloc] init]; \
[[TIPImageCodecCatalogue sharedInstance] setCodec:mp4Codec forImageType:TIPXImageTypeMP4]; \
tip_defer(^{ \
    [[TIPImageCodecCatalogue sharedInstance] removeCodecForImageType:TIPXImageTypeMP4]; \
});


static const NSOperatingSystemVersion kIOS11 = { 11, 0, 0 };

@implementation TestParamSet

+ (instancetype)floatParamSetWithAlphaInfo:(CGImageAlphaInfo)alphaInfo byteOrder:(uint32_t)byteOrder
{
    TestParamSet *set = [[self alloc] init];
    set.alphaInfo = alphaInfo;
    set.byteOrder = byteOrder;
    set.useFloat = YES;
    set.bytesPerComponent = sizeof(float);
    return set;
}

+ (instancetype)integerParamSetWithAlphaInfo:(CGImageAlphaInfo)alphaInfo byteOrder:(uint32_t)byteOrder bytesPerComponent:(size_t)bytesPerComponent
{
    TestParamSet *set = [[self alloc] init];
    set.alphaInfo = alphaInfo;
    set.byteOrder = byteOrder;
    set.useFloat = NO;
    set.bytesPerComponent = bytesPerComponent;
    return set;
}

@end

@interface TestColorSpace : NSObject
@property (nonatomic, readonly) CGColorSpaceRef colorSpace;
@property (nonatomic, readonly) NSArray *validParamSets;
+ (instancetype)colorSpaceWithOwnedRef:(CGColorSpaceRef)colorSpace validParamSets:(NSArray *)validParamSets;
@end

@implementation TestColorSpace

+ (instancetype)colorSpaceWithOwnedRef:(CGColorSpaceRef)colorSpace validParamSets:(NSArray *)validParamSets
{
    TestColorSpace *tcs = [[self alloc] init];
    tcs->_colorSpace = colorSpace;
    tcs->_validParamSets = [validParamSets copy];
    return tcs;
}

- (void)dealloc
{
    if (_colorSpace) {
        CFRelease(_colorSpace);
    }
}

@end

@interface NSData (Description)
- (NSString *)tst_shortDescription;
@end

@implementation NSData (Description)

- (NSString*)tst_shortDescription
{
    return [NSString stringWithFormat:@"<%@:%p length=%tu>", NSStringFromClass([self class]), self, self.length];
}

@end

@interface TIPImageTest : XCTestCase
@end

#define JPEG_QUALITY_PERFECT (1.0f)
#define JPEG_QUALITY_GOOD (kTIPAppleQualityValueRepresentingJFIFQuality85)
#define JPEG_QUALITY_OK (0.15f)

#define JPEG2000_QUALITY_PERFECT (1.0f)
#define JPEG2000_QUALITY_GOOD (kTIPAppleQualityValueRepresentingJFIFQuality85)
#define JPEG2000_QUALITY_OK (0.15f)

#define WEBP_QUALITY_PERFECT (.99f) /* use .99 because 1. is lossless and slower than molasses in Edmonton in January */
#define WEBP_QUALITY_GOOD (0.6f)
#define WEBP_QUALITY_OK (0.3f)

#define TEST_IMAGE_WIDTH ((CGFloat)1880.0)
#define TEST_IMAGE_HEIGHT ((CGFloat)1253.0)

#define TEST_ANIMATION_WIDTH ((CGFloat)480.0)
#define TEST_ANIMATION_HEIGHT ((CGFloat)320.0)

static TIPImageContainer *sImageContainer;
static TIPImageContainer *sAnimatedImageContainer;
static NSMutableArray<NSString *> *sSavedImages;
static NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *sPerformanceInfo;

@implementation TIPImageTest

+ (NSArray <NSInvocation *> *)testInvocations
{
    NSArray<NSInvocation *> *invocations = [super testInvocations];
    invocations = [invocations sortedArrayUsingComparator:^NSComparisonResult(NSInvocation *inv1, NSInvocation *inv2) {
        return [NSStringFromSelector(inv1.selector) compare:NSStringFromSelector(inv2.selector)];
    }];
    return invocations;
}

+ (void)setUp
{
    NSBundle *thisBundle = TIPTestsResourceBundle();

    NSString *imagePath = [thisBundle pathForResource:@"carnival" ofType:@"png"];
    UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
    [image tip_decode];
    sImageContainer = [[TIPImageContainer alloc] initWithImage:image];
    imagePath = [thisBundle pathForResource:@"fireworks" ofType:@"gif"];
    NSUInteger loopCount;
    NSArray<NSNumber *> *durations;
    image = [UIImage tip_imageWithAnimatedImageFile:imagePath durations:&durations loopCount:&loopCount];
    [image tip_decode]; // yes, this is a no-op, but we'll leave this here in case we can optimize the decode for animated images later
    sAnimatedImageContainer = [[TIPImageContainer alloc] initWithAnimatedImage:image loopCount:loopCount frameDurations:durations];

    sSavedImages = [NSMutableArray array];
    sPerformanceInfo = [NSMutableDictionary dictionary];

    // make the NSData description less verbose
    Method originalMethod = class_getInstanceMethod([NSData class], @selector(description));
    Method swizzledMethod = class_getInstanceMethod([NSData class], @selector(tst_shortDescription));
    method_exchangeImplementations(originalMethod, swizzledMethod);
}

+ (void)tearDown
{
    // return NSData description
    Method originalMethod = class_getInstanceMethod([NSData class], @selector(description));
    Method swizzledMethod = class_getInstanceMethod([NSData class], @selector(tst_shortDescription));
    method_exchangeImplementations(originalMethod, swizzledMethod);

    sImageContainer = nil;
    sAnimatedImageContainer = nil;
    for (NSString *file in sSavedImages) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:file error:NULL];
        NSLog(@"%@ size: %@", file.lastPathComponent, [NSByteCountFormatter stringFromByteCount:(long long)attributes.fileSize countStyle:NSByteCountFormatterCountStyleBinary]);
        [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
    }

    [self logPerf];
    sPerformanceInfo = nil;
}

+ (void)logPerf
{
    NSMutableString *perfString = [NSMutableString stringWithFormat:@"%8s | %8s | %8s | %8s", "format", "save", "load", "speed"];
    [perfString appendString:@"\n----------------------------------------"];
    NSMutableArray<NSString *> *keys = [sPerformanceInfo.allKeys mutableCopy];
    [keys sortUsingComparator:^NSComparisonResult(NSString *key1, NSString *key2) {
        float val1 = sPerformanceInfo[key1][@"speed"].floatValue;
        float val2 = sPerformanceInfo[key2][@"speed"].floatValue;

        if (val1 < val2) {
            return NSOrderedAscending;
        } else if (val1 > val2) {
            return NSOrderedDescending;
        }

        return NSOrderedSame;
    }];
    for (NSString *imageType in keys) {
        NSDictionary<NSString *, NSNumber *> *metrics = sPerformanceInfo[imageType];
        [perfString appendFormat:@"\n%8s | %7.3fs | %7.3fs | %7.3fs", [imageType UTF8String], metrics[@"save"].floatValue, metrics[@"load"].floatValue, metrics[@"speed"].floatValue];
    }
    NSLog(@"\n%@", perfString);
}

- (void)tearDown
{
    (void)[TIPImageCodecCatalogue sharedInstance].allCodecs; // flush
    [super tearDown];
}

#pragma mark Test SetUp

- (void)testLoadedImage
{
    XCTAssert(sImageContainer.dimensions.width == TEST_IMAGE_WIDTH);
    XCTAssert(sImageContainer.dimensions.height == TEST_IMAGE_HEIGHT);
    XCTAssert(sAnimatedImageContainer.dimensions.width == TEST_ANIMATION_WIDTH);
    XCTAssert(sAnimatedImageContainer.dimensions.height == TEST_ANIMATION_HEIGHT);
    XCTAssert(sAnimatedImageContainer.image.images.count > 2);
}

#pragma mark Test Read/Write of different formats

- (void)runSaveTest:(NSString *)type options:(TIPImageEncodingOptions)options extension:(NSString *)extension quality:(float)quality useAnimatedImage:(BOOL)useAnimated
{
    NSString *file = [[[NSTemporaryDirectory() stringByAppendingPathComponent:@"test"] stringByAppendingPathExtension:[@((NSUInteger)(quality * 100.0f)) stringValue]] stringByAppendingPathExtension:extension];
    NSError *error = nil;
    TIPImageContainer * imageContainer = (useAnimated) ? sAnimatedImageContainer : sImageContainer;
    const BOOL writeToFileSuccess = [imageContainer saveToFilePath:file type:type codecCatalogue:nil options:options quality:quality atomic:YES error:&error];
    XCTAssertTrue(writeToFileSuccess, @"file=`%@`, error=%@", file, error);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:file isDirectory:NULL], @"%@", file);
    [sSavedImages addObject:file];
}

- (void)runLoadTest:(NSString *)expectedType options:(TIPImageEncodingOptions)options extension:(NSString *)extension quality:(float)quality isAnimated:(BOOL)animated
{
    NSString *file = [[[NSTemporaryDirectory() stringByAppendingPathComponent:@"test"] stringByAppendingPathExtension:[@((NSUInteger)(quality * 100.0f)) stringValue]] stringByAppendingPathExtension:extension];
    NSData *data = [NSData dataWithContentsOfFile:file];
    XCTAssertGreaterThan(data.length, (NSUInteger)0, @"%@", file);
    NSUInteger detectedAnimatedFrameCount = 0;
    TIPImageEncodingOptions detectedOptions = 0;
    NSString *detectedType = TIPDetectImageType(data, &detectedOptions, &detectedAnimatedFrameCount, NO);
    BOOL couldBeCustomType = detectedType == nil;
    if (!couldBeCustomType) {
        XCTAssertEqualObjects(detectedType, expectedType, @"%@", file);
        XCTAssertEqual(options, detectedOptions);
        XCTAssertEqual(!!animated, (detectedAnimatedFrameCount > 1));
    }

    TIPImageContainer *container = [TIPImageContainer imageContainerWithData:data decoderConfigMap:nil codecCatalogue:nil];
    UIImage *image = container.image;
    XCTAssertNotNil(image, @"extension = '%@'", extension);
    NSTimeInterval decompressTime = [self decompressImage:image];
    NSLog(@"%@ decompress time: %fs", file.lastPathComponent, decompressTime);
    if (animated) {
        XCTAssertGreaterThan(image.images.count, (NSUInteger)1);
        XCTAssertEqual(image.images.count, container.frameCount);
        XCTAssertEqual(image.images.count, container.frameDurations.count);
        if (!couldBeCustomType) {
            XCTAssertEqual(container.frameDurations.count, detectedAnimatedFrameCount);
        }
        XCTAssertEqual(sAnimatedImageContainer.frameCount, container.frameDurations.count);
        if (sAnimatedImageContainer.frameCount == container.frameDurations.count) {
            for (NSUInteger i = 0; i < container.frameDurations.count; i++) {
                XCTAssertEqualWithAccuracy([sAnimatedImageContainer.frameDurations[i] floatValue], [container.frameDurations[i] floatValue], 0.005f);
            }
        }
    } else {
        XCTAssertLessThanOrEqual(image.images.count, (NSUInteger)1);
    }
}

- (NSTimeInterval)decompressImage:(UIImage *)image
{
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    [image tip_decode];
    return CFAbsoluteTimeGetCurrent() - startTime;
}

- (void)runSpeedTest:(NSString *)type options:(TIPImageEncodingOptions)options
{
    TIPImageCodecCatalogue *catalogue = [TIPImageCodecCatalogue sharedInstance];
    // const BOOL animated = [catalogue codecWithImageTypeSupportsAnimation:type];
    TIPImageContainer *imageContainer = (NO) ? sAnimatedImageContainer : sImageContainer;
    for (NSUInteger i = 0; i < 5; i++) {
        @autoreleasepool {
            float quality = 1.0f - ((i % 10) / 10.0f);
            if (type == TIPXImageTypeWebP && quality > .99f) {
                // Lossless WebP is super slow,
                // drop down to 99% in order to give WebP a fighting chance
                quality = .99f;
            }
            NSError *error = nil;
            NSData *data = [catalogue encodeImage:imageContainer withImageType:type quality:quality options:options error:&error];
            XCTAssertGreaterThan(data.length, (NSUInteger)0, @"Write image (q=%f) to data failed: %@", quality, error);
        }
    }
}

- (void)runMeasurement:(NSString *)measurement format:(NSString *)format block:(dispatch_block_t)block
{
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    block();
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();

    NSMutableDictionary<NSString *, NSNumber *> *measurements = sPerformanceInfo[format];
    if (!measurements) {
        measurements = [NSMutableDictionary dictionary];
        sPerformanceInfo[format] = measurements;
    }

    measurements[measurement] = @(end - start);
}

#pragma mark Image Formats R+W tests

- (void)testSaveJPEG
{
    [self runSaveTest:TIPImageTypeJPEG options:0 extension:@"jpg" quality:JPEG_QUALITY_PERFECT useAnimatedImage:NO];
    [self runSaveTest:TIPImageTypeJPEG options:0 extension:@"jpg" quality:JPEG_QUALITY_GOOD useAnimatedImage:NO];

    [self runMeasurement:@"save" format:@"jpg" block:^{
        [self runSaveTest:TIPImageTypeJPEG options:0 extension:@"jpg" quality:JPEG_QUALITY_OK useAnimatedImage:NO];
    }];
}

- (void)testXLoadJPEG
{
    [self runLoadTest:TIPImageTypeJPEG options:0 extension:@"jpg" quality:JPEG_QUALITY_PERFECT isAnimated:NO];
    [self runLoadTest:TIPImageTypeJPEG options:0 extension:@"jpg" quality:JPEG_QUALITY_GOOD isAnimated:NO];

    [self runMeasurement:@"load" format:@"jpg" block:^{
        [self runLoadTest:TIPImageTypeJPEG options:0 extension:@"jpg" quality:JPEG_QUALITY_OK isAnimated:NO];
    }];
}

- (void)testSpeedJPEG
{
    [self runMeasurement:@"speed" format:@"jpg" block:^{
        [self runSpeedTest:TIPImageTypeJPEG options:0];
    }];
}

- (void)testSavePJPEG
{
    [self runSaveTest:TIPImageTypeJPEG options:TIPImageEncodingProgressive extension:@"pjpg" quality:JPEG_QUALITY_PERFECT useAnimatedImage:NO];
    [self runSaveTest:TIPImageTypeJPEG options:TIPImageEncodingProgressive extension:@"pjpg" quality:JPEG_QUALITY_GOOD useAnimatedImage:NO];

    [self runMeasurement:@"save" format:@"pjpg" block:^{
        [self runSaveTest:TIPImageTypeJPEG options:TIPImageEncodingProgressive extension:@"pjpg" quality:JPEG_QUALITY_OK useAnimatedImage:NO];
    }];
}

- (void)testXLoadPJPEG
{
    [self runLoadTest:TIPImageTypeJPEG options:TIPImageEncodingProgressive extension:@"pjpg" quality:JPEG_QUALITY_PERFECT isAnimated:NO];
    [self runLoadTest:TIPImageTypeJPEG options:TIPImageEncodingProgressive extension:@"pjpg" quality:JPEG_QUALITY_GOOD isAnimated:NO];

    [self runMeasurement:@"load" format:@"pjpg" block:^{
        [self runLoadTest:TIPImageTypeJPEG options:TIPImageEncodingProgressive extension:@"pjpg" quality:JPEG_QUALITY_OK isAnimated:NO];
    }];
}

- (void)testSpeedPJPEG
{
    [self runMeasurement:@"speed" format:@"pjpg" block:^{
        [self runSpeedTest:TIPImageTypeJPEG options:TIPImageEncodingProgressive];
    }];
}

- (void)testSaveJPEG2000
{
    [self runSaveTest:TIPImageTypeJPEG2000 options:0 extension:@"j2k" quality:JPEG2000_QUALITY_PERFECT useAnimatedImage:NO];
    [self runSaveTest:TIPImageTypeJPEG2000 options:0 extension:@"j2k" quality:JPEG2000_QUALITY_GOOD useAnimatedImage:NO];

    [self runMeasurement:@"save" format:@"j2k" block:^{
        [self runSaveTest:TIPImageTypeJPEG2000 options:0 extension:@"j2k" quality:JPEG2000_QUALITY_OK useAnimatedImage:NO];
    }];
}

- (void)testXLoadJPEG2000
{
    [self runLoadTest:TIPImageTypeJPEG2000 options:0 extension:@"j2k" quality:JPEG2000_QUALITY_PERFECT isAnimated:NO];
    [self runLoadTest:TIPImageTypeJPEG2000 options:0 extension:@"j2k" quality:JPEG2000_QUALITY_GOOD isAnimated:NO];

    [self runMeasurement:@"load" format:@"j2k" block:^{
        [self runLoadTest:TIPImageTypeJPEG2000 options:0 extension:@"j2k" quality:JPEG2000_QUALITY_OK isAnimated:NO];
    }];
}

- (void)testSpeedJPEG2000
{
    [self runMeasurement:@"speed" format:@"j2k" block:^{
        [self runSpeedTest:TIPImageTypeJPEG2000 options:0];
    }];
}

- (void)testSavePNG
{
    [self runMeasurement:@"save" format:@"png" block:^{
        [self runSaveTest:TIPImageTypePNG options:0 extension:@"png" quality:1.0f useAnimatedImage:NO];
    }];
}

- (void)testXLoadPNG
{
    [self runMeasurement:@"load" format:@"png" block:^{
        [self runLoadTest:TIPImageTypePNG options:0 extension:@"png" quality:1.0f isAnimated:NO];
    }];
}

- (void)testSpeedPNG
{
    [self runMeasurement:@"speed" format:@"png" block:^{
        [self runSpeedTest:TIPImageTypePNG options:0];
    }];
}

- (void)testSaveIPNG
{
    [self runMeasurement:@"save" format:@"ipng" block:^{
        [self runSaveTest:TIPImageTypePNG options:TIPImageEncodingProgressive extension:@"i.png" quality:1.0f useAnimatedImage:NO];
    }];
}

- (void)testXLoadIPNG
{
    [self runMeasurement:@"load" format:@"ipng" block:^{
        [self runLoadTest:TIPImageTypePNG options:TIPImageEncodingProgressive extension:@"i.png" quality:1.0f isAnimated:NO];
    }];
}

- (void)testSpeedIPNG
{
    [self runMeasurement:@"speed" format:@"ipng" block:^{
        [self runSpeedTest:TIPImageTypePNG options:TIPImageEncodingProgressive];
    }];
}

- (void)testSaveTIFF
{
    [self runMeasurement:@"save" format:@"tiff" block:^{
        [self runSaveTest:TIPImageTypeTIFF options:0 extension:@"tiff" quality:1.0f useAnimatedImage:NO];
    }];
}

- (void)testXLoadTIFF
{
    [self runMeasurement:@"load" format:@"tiff" block:^{
        [self runLoadTest:TIPImageTypeTIFF options:0 extension:@"tiff" quality:1.0f isAnimated:NO];
    }];
}

- (void)testSpeedTIFF
{
    [self runMeasurement:@"speed" format:@"tiff" block:^{
        [self runSpeedTest:TIPImageTypeTIFF options:0];
    }];
}

- (void)testSaveBMP
{
    [self runMeasurement:@"save" format:@"bmp" block:^{
        [self runSaveTest:TIPImageTypeBMP options:0 extension:@"bmp" quality:1.0f useAnimatedImage:NO];
    }];
}

- (void)testXLoadBMP
{
    [self runMeasurement:@"load" format:@"bmp" block:^{
        [self runLoadTest:TIPImageTypeBMP options:0 extension:@"bmp" quality:1.0f isAnimated:NO];
    }];
}

- (void)testSpeedBMP
{
    [self runMeasurement:@"speed" format:@"bmp" block:^{
        [self runSpeedTest:TIPImageTypeBMP options:0];
    }];
}

- (void)testSaveTGA
{
    [self runMeasurement:@"save" format:@"tga" block:^{
        [self runSaveTest:TIPImageTypeTARGA options:0 extension:@"tga" quality:1.0f useAnimatedImage:NO];
    }];
}

- (void)testXLoadTGA
{
    [self runMeasurement:@"load" format:@"tga" block:^{
        [self runLoadTest:TIPImageTypeTARGA options:0 extension:@"tga" quality:1.0f isAnimated:NO];
    }];
}

- (void)testSpeedTGA
{
    [self runMeasurement:@"speed" format:@"tga" block:^{
        [self runSpeedTest:TIPImageTypeTARGA options:0];
    }];
}

#pragma mark Less Supported Image Formats tests

- (void)runLoadTestForReadOnlyFormat:(NSString *)format imageType:(NSString *)imageType
{
    NSBundle *thisBundle = TIPTestsResourceBundle();
    NSString *imagePath = [thisBundle pathForResource:@"sample" ofType:format];
    NSData *data = [NSData dataWithContentsOfFile:imagePath];
    XCTAssertGreaterThan(data.length, (NSUInteger)0, @"%@", imagePath);
    NSUInteger detectedAnimatedFrameCount = 0;
    TIPImageEncodingOptions detectedOptions = 0;
    NSString *detectedType = TIPDetectImageType(data, &detectedOptions, &detectedAnimatedFrameCount, YES);
    XCTAssertEqualObjects(detectedType, imageType, @"%@", imagePath);
    XCTAssertEqual(0, detectedOptions);
    XCTAssertEqual(NO, (detectedAnimatedFrameCount > 1), @"%@", imagePath);
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    TIPDeferRelease(imageSource);
    UIImage *image = [UIImage imageWithData:data];
    NSTimeInterval decompressTime = [self decompressImage:image];
    XCTAssertNotNil(image, @"%@", imagePath);
    NSLog(@"%@ decompress time: %fs", imagePath.lastPathComponent, decompressTime);
}

- (void)runLoadTestForUnreadableFormat:(NSString *)format
{
    NSBundle *thisBundle = TIPTestsResourceBundle();
    NSString *imagePath = [thisBundle pathForResource:@"sample" ofType:format];
    NSData *data = [NSData dataWithContentsOfFile:imagePath];
    XCTAssertGreaterThan(data.length, (NSUInteger)0, @"format='%@', file='%@'", format, imagePath);
    NSUInteger detectedAnimatedFrameCount = 0;
    TIPImageEncodingOptions detectedOptions = 0;
    NSString *detectedType = TIPDetectImageType(data, &detectedOptions, &detectedAnimatedFrameCount, YES);
    XCTAssertNil(detectedType, @"%@", imagePath);
    UIImage *image = [UIImage imageWithData:data];
    XCTAssertNil(image, @"%@", imagePath);
}

- (void)runAttemptToSaveImageAsReadOnlyImageType:(NSString *)imageType
{
    NSError *error = nil;
    NSData *imageData = nil;
    imageData = [sImageContainer.image tip_writeToDataWithType:imageType
                                               encodingOptions:0
                                                       quality:1.f
                                            animationLoopCount:0
                                       animationFrameDurations:nil
                                                         error:&error];
    XCTAssertNil(imageData);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, TIPErrorDomain);
    XCTAssertEqual(error.code, TIPErrorCodeEncodingUnsupported);
    XCTAssertEqualObjects(error.userInfo[@"imageType"], imageType);

    error = nil;
    imageData = [[TIPImageCodecCatalogue sharedInstance] encodeImage:sImageContainer withImageType:imageType quality:1.f options:0 error:&error];
    XCTAssertNil(imageData);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, TIPErrorDomain);
    XCTAssertEqual(error.code, TIPErrorCodeEncodingUnsupported);
    XCTAssertEqualObjects(error.userInfo[@"imageType"], imageType);
}

- (void)testSavePICT
{
    [self runAttemptToSaveImageAsReadOnlyImageType:TIPImageTypePICT];
}

- (void)testXLoadPICT
{
    [self runLoadTestForUnreadableFormat:@"pict"];
}

- (void)testSpeedPICT
{
    // unsupported with read only format
}

- (void)testSaveQTIF
{
    [self runAttemptToSaveImageAsReadOnlyImageType:TIPImageTypeQTIF];
}

- (void)testXLoadQTIF
{
    // Cannot even figure out how to create a qif file to test this :P
    // [self runLoadTestForUnreadableFormat:@"qif"];
}

- (void)testSpeedQTIF
{
    // unsupported with read only format
}

- (void)testSaveICO
{
    [self runAttemptToSaveImageAsReadOnlyImageType:TIPImageTypeICO];
}

- (void)testXLoadICO
{
    [self runMeasurement:@"load" format:@"*ico" block:^{
        [self runLoadTestForReadOnlyFormat:@"ico" imageType:TIPImageTypeICO];
    }];
}

- (void)testSpeedICO
{
    // unsupported with read only format
}

- (void)testSaveICNS
{
    [self runAttemptToSaveImageAsReadOnlyImageType:TIPImageTypeICNS];
}

- (void)testXLoadICNS
{
    if ([[NSProcessInfo processInfo] respondsToSelector:@selector(isOperatingSystemAtLeastVersion:)] && [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:kIOS11]) {
        [self runMeasurement:@"load" format:@"*icns" block:^{
            [self runLoadTestForReadOnlyFormat:@"icns" imageType:TIPImageTypeICNS];
        }];
    } else {
        [self runLoadTestForUnreadableFormat:@"icns"];
    }
}

- (void)testSpeedICNS
{
    // unsupported with read only format
}

- (void)testSaveRAW
{
    [self runAttemptToSaveImageAsReadOnlyImageType:TIPImageTypeRAW];
}

- (void)testXLoadRAW
{
    [self runMeasurement:@"load" format:@"*cr2" block:^{
        [self runLoadTestForReadOnlyFormat:@"cr2" imageType:TIPImageTypeRAW];
    }];
}

- (void)testSpeedRAW
{
    // unsupported with read only format
}

- (void)testSaveWebP
{
    XCTAssertNil([[TIPImageCodecCatalogue sharedInstance] codecForImageType:TIPXImageTypeWebP]);

    PLUG_IN_WEBP();

    [self runSaveTest:TIPXImageTypeWebP options:0 extension:@"webp" quality:WEBP_QUALITY_PERFECT useAnimatedImage:NO];
    [self runSaveTest:TIPXImageTypeWebP options:0 extension:@"webp" quality:WEBP_QUALITY_GOOD useAnimatedImage:NO];

    [self runMeasurement:@"save" format:@"webp" block:^{
        [self runSaveTest:TIPXImageTypeWebP options:0 extension:@"webp" quality:WEBP_QUALITY_OK useAnimatedImage:NO];
    }];
}

- (void)testXLoadWebP
{
    [self runLoadTestForUnreadableFormat:@"webp"];

    PLUG_IN_WEBP();

    [self runLoadTest:TIPXImageTypeWebP options:0 extension:@"webp" quality:WEBP_QUALITY_PERFECT isAnimated:NO];
    [self runLoadTest:TIPXImageTypeWebP options:0 extension:@"webp" quality:WEBP_QUALITY_GOOD isAnimated:NO];

    [self runMeasurement:@"load" format:@"webp" block:^{
        [self runLoadTest:TIPXImageTypeWebP options:0 extension:@"webp" quality:WEBP_QUALITY_OK isAnimated:NO];
    }];
}

- (void)testSpeedWebP
{
    XCTAssertNil([[TIPImageCodecCatalogue sharedInstance] codecForImageType:@"webp"]);

    PLUG_IN_WEBP();

    [self runMeasurement:@"speed" format:@"webp" block:^{
        [self runSpeedTest:TIPXImageTypeWebP options:0];
    }];
}

#pragma mark Animated Formats R+W tests

- (void)testSaveAnimatedGIF
{
    [self runMeasurement:@"save" format:@"gif" block:^{
        [self runSaveTest:TIPImageTypeGIF options:0 extension:@"gif" quality:1.0f useAnimatedImage:YES];
    }];
}

- (void)testXLoadAnimatedGIF
{
    [self runMeasurement:@"load" format:@"gif" block:^{
        [self runLoadTest:TIPImageTypeGIF options:0 extension:@"gif" quality:1.0f isAnimated:YES];
    }];
}

- (void)testSpeedAnimatedGIF
{
    [self runMeasurement:@"speed" format:@"gif" block:^{
        [self runSpeedTest:TIPImageTypeGIF options:0];
    }];
}

- (void)testSaveAnimatedPNG
{
    [self runMeasurement:@"save" format:@"apng" block:^{
        [self runSaveTest:TIPImageTypePNG options:0 extension:@"apng" quality:1.0f useAnimatedImage:YES];
    }];
}

- (void)testXLoadAnimatedPNG
{
    [self runMeasurement:@"load" format:@"apng" block:^{
        [self runLoadTest:TIPImageTypePNG options:0 extension:@"apng" quality:1.0f isAnimated:YES];
    }];
}

- (void)testSpeedAnimatedPNG
{
    [self runMeasurement:@"speed" format:@"apng" block:^{
        [self runSpeedTest:TIPImageTypePNG options:0];
    }];
}


- (void)testSaveAnimatedMP4
{
    // noop
}

- (void)testXLoadAnimatedMP4
{
    PLUG_IN_MP4();

    // need to "seed" the test file since we don't have the encoder

    NSString *srcFile = [TIPTestsResourceBundle() pathForResource:@"200w" ofType:@"mp4"];
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *tmpFile = [tmpDir stringByAppendingPathComponent:@"test.100.mp4"];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm copyItemAtPath:srcFile toPath:tmpFile error:NULL];
    tip_defer(^{
        [fm removeItemAtPath:tmpFile error:NULL];
    });

    // run the actual test

    TIPImageContainer *container = [TIPImageContainer imageContainerWithFilePath:tmpFile decoderConfigMap:nil codecCatalogue:nil memoryMap:YES];
    XCTAssertNotNil(container.image);
    XCTAssertEqual((NSUInteger)35, container.frameCount);
}

- (void)testSpeedAnimatedMP4
{
    // noop
}

#pragma mark Robustness Tests

- (void)testDataDribbleJPEG
{
    // test an image by appending 1 byte at a time

    TIPImageContainer *scaledImage = [sImageContainer scaleToTargetDimensions:CGSizeMake(48, 48) contentMode:UIViewContentModeScaleAspectFit];
    id<TIPImageCodec> jpegCodec = [[TIPImageCodecCatalogue sharedInstance] codecForImageType:TIPImageTypeJPEG];
    id<TIPImageDecoder> jpegDecoder = jpegCodec.tip_decoder;
    NSData *data = [[TIPImageCodecCatalogue sharedInstance] encodeImage:scaledImage withImageType:TIPImageTypeJPEG quality:kTIPAppleQualityValueRepresentingJFIFQuality85 options:0 error:NULL];

    XCTAssertGreaterThan(data.length, (NSUInteger)0);

    id<TIPImageDecoderContext> decoderContext = [jpegDecoder tip_initiateDecoding:nil expectedDataLength:data.length buffer:nil];
    TIPImageDecoderAppendResult result = TIPImageDecoderAppendResultDidProgress;
    NSUInteger counts[4] = { 0 };
    const Byte * dataBytePtr = data.bytes;
    const Byte * dataBytePtrEnd = dataBytePtr + data.length;
    for (; dataBytePtr < dataBytePtrEnd; dataBytePtr++) {
        result = [jpegDecoder tip_append:decoderContext data:[NSData dataWithBytesNoCopy:(void *)dataBytePtr length:1 freeWhenDone:NO]];
        counts[result]++;
    }
    result = [jpegDecoder tip_finalizeDecoding:decoderContext];
    counts[result]++;

    TIPImageContainer *decodedImage = [jpegDecoder tip_renderImage:decoderContext mode:TIPImageDecoderRenderModeCompleteImage];

    XCTAssertNotNil(decodedImage);
    XCTAssertTrue(CGSizeEqualToSize(decodedImage.dimensions, scaledImage.dimensions));
}

#pragma mark Test Functions

- (void)testImageWriteToFile
{
    TIPSetDebugSTOPOnAssertEnabled(NO);
    NSString *tmpPath = [[[NSTemporaryDirectory() stringByAppendingPathComponent:@"test"] stringByAppendingPathExtension:[NSUUID UUID].UUIDString] stringByAppendingPathExtension:@"jpg"];

    UIImage *image = nil;
    NSString *path = nil;
    BOOL success = NO;

#define TEST_WRITE(shouldSucceed) \
    @try { \
        success = [image tip_writeToFile:path type:TIPImageTypeJPEG encodingOptions:0 quality:1.f animationLoopCount:0 animationFrameDurations:nil atomically:YES error:NULL]; \
    } \
    @catch (NSException *exception) { \
        success = NO; \
    } \
    if (shouldSucceed) { \
        XCTAssertTrue(success); \
    } else { \
        XCTAssertFalse(success); \
    }

    path = tmpPath;
    TEST_WRITE(NO);

    image = sImageContainer.image;
    path = nil;
    TEST_WRITE(NO);

    path = tmpPath;
    TEST_WRITE(YES);

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:NULL];
}

- (void)testTypeSupportsProgressiveLoading
{
    NSOperatingSystemVersion osVersion = { 7, 0, 0 };
    if ([[NSProcessInfo processInfo] respondsToSelector:@selector(operatingSystemVersion)]) {
        osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    }

    XCTAssertEqual([[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsProgressiveLoading:TIPImageTypeJPEG2000], NO); // for now
    XCTAssertEqual([[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsProgressiveLoading:TIPImageTypeJPEG], osVersion.majorVersion >= 8);
    XCTAssertEqual([[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsProgressiveLoading:TIPImageTypePNG], NO); // for now
    XCTAssertEqual([[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsProgressiveLoading:nil], NO);
}

- (BOOL)_typeHasProgressiveVariant:(NSString *)type
{
    return [[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsProgressiveLoading:type];
}

- (void)testTypeHasProgressiveVariant
{
    NSOperatingSystemVersion version = { 7, 0, 0 };
    if ([[NSProcessInfo processInfo] respondsToSelector:@selector(operatingSystemVersion)]) {
        version = [NSProcessInfo processInfo].operatingSystemVersion;
    }

    XCTAssertEqual([self _typeHasProgressiveVariant:TIPImageTypeJPEG], version.majorVersion >= 8);
    XCTAssertEqual([self _typeHasProgressiveVariant:TIPImageTypeJPEG2000], NO);
    XCTAssertEqual([self _typeHasProgressiveVariant:TIPImageTypePNG], NO);
    XCTAssertEqual([self _typeHasProgressiveVariant:nil], NO);
}

- (void)testGetMemorySize
{
    XCTAssertEqual((CGFloat)1.0, sImageContainer.image.scale);

    NSUInteger pixelSize = (NSUInteger)TEST_IMAGE_WIDTH * (NSUInteger)TEST_IMAGE_HEIGHT;
    XCTAssertEqual([sImageContainer.image tip_estimatedSizeInBytes], pixelSize * 4);

    CGSize size = sImageContainer.image.size;
    XCTAssertEqual(TIPEstimateMemorySizeOfImageWithSettings(size, 1.0, 3, 1), pixelSize * 3);
    XCTAssertEqual(TIPEstimateMemorySizeOfImageWithSettings(size, 2.0, 3, 1), pixelSize * 3 * 4);
    XCTAssertEqual(TIPEstimateMemorySizeOfImageWithSettings(size, 1.0, 4, 1), pixelSize * 4);
    XCTAssertEqual(TIPEstimateMemorySizeOfImageWithSettings(size, 2.0, 4, 1), pixelSize * 4 * 4);
    XCTAssertEqual(TIPEstimateMemorySizeOfImageWithSettings(CGSizeZero, 1.0, 4, 1), (NSUInteger)0);
}

- (void)testImageType
{
    XCTAssertNil(TIPImageTypeFromUTType((__bridge NSString *)kUTTypeImage));
    XCTAssertEqualObjects(TIPImageTypeJPEG, TIPImageTypeFromUTType((__bridge NSString *)kUTTypeJPEG));
    XCTAssertEqualObjects(TIPImageTypeJPEG2000, TIPImageTypeFromUTType((__bridge NSString *)kUTTypeJPEG2000));
    XCTAssertEqualObjects(TIPImageTypeTIFF, TIPImageTypeFromUTType((__bridge NSString *)kUTTypeTIFF));
    XCTAssertEqualObjects(TIPImageTypeGIF, TIPImageTypeFromUTType((__bridge NSString *)kUTTypeGIF));
    XCTAssertEqualObjects(TIPImageTypePNG, TIPImageTypeFromUTType((__bridge NSString *)kUTTypePNG));
    XCTAssertEqualObjects(TIPImageTypeBMP, TIPImageTypeFromUTType((__bridge NSString *)kUTTypeBMP));
    XCTAssertEqualObjects(TIPImageTypeTARGA, TIPImageTypeFromUTType(@"com.truevision.tga-image"));
    XCTAssertTrue(UTTypeConformsTo(CFSTR("com.truevision.tga-image"), kUTTypeImage));
    XCTAssertEqualObjects(TIPImageTypePICT, TIPImageTypeFromUTType((__bridge NSString *)kUTTypePICT));
    XCTAssertEqualObjects(TIPImageTypeQTIF, TIPImageTypeFromUTType((__bridge NSString *)kUTTypeQuickTimeImage));
    XCTAssertEqualObjects(TIPImageTypeICNS, TIPImageTypeFromUTType((__bridge NSString *)kUTTypeAppleICNS));
    XCTAssertEqualObjects(TIPImageTypeICO, TIPImageTypeFromUTType((__bridge NSString *)kUTTypeICO));
    XCTAssertEqualObjects(TIPImageTypeRAW, TIPImageTypeFromUTType((__bridge NSString *)kUTTypeRawImage));
    XCTAssertEqualObjects(TIPImageTypeRAW, TIPImageTypeFromUTType(@"com.canon.cr2-raw-image"));

    // read

    XCTAssertFalse(TIPImageTypeCanReadWithImageIO((__bridge NSString *)kUTTypeImage));
    XCTAssertFalse(TIPImageTypeCanReadWithImageIO((__bridge NSString *)kUTTypeMPEG2Video));

    XCTAssertTrue(TIPImageTypeCanReadWithImageIO(TIPImageTypeJPEG));
    XCTAssertTrue(TIPImageTypeCanReadWithImageIO(TIPImageTypeJPEG2000));
    XCTAssertTrue(TIPImageTypeCanReadWithImageIO(TIPImageTypeTIFF));
    XCTAssertTrue(TIPImageTypeCanReadWithImageIO(TIPImageTypeGIF));
    XCTAssertTrue(TIPImageTypeCanReadWithImageIO(TIPImageTypePNG));
    XCTAssertTrue(TIPImageTypeCanReadWithImageIO(TIPImageTypeBMP));
    XCTAssertTrue(TIPImageTypeCanReadWithImageIO(TIPImageTypeTARGA));
    XCTAssertTrue(TIPImageTypeCanReadWithImageIO(@"com.canon.cr2-raw-image"));
    XCTAssertTrue(TIPImageTypeCanReadWithImageIO(TIPImageTypeICO));

    XCTAssertFalse(TIPImageTypeCanReadWithImageIO(TIPImageTypePICT));
    XCTAssertFalse(TIPImageTypeCanReadWithImageIO(TIPImageTypeQTIF));
    XCTAssertFalse(TIPImageTypeCanReadWithImageIO(TIPImageTypeRAW));

    if ([[NSProcessInfo processInfo] respondsToSelector:@selector(isOperatingSystemAtLeastVersion:)] && [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:kIOS11]) {
        XCTAssertTrue(TIPImageTypeCanReadWithImageIO(TIPImageTypeICNS));
    } else {
        XCTAssertFalse(TIPImageTypeCanReadWithImageIO(TIPImageTypeICNS));
    }


    // write

    XCTAssertFalse(TIPImageTypeCanWriteWithImageIO((__bridge NSString *)kUTTypeImage));
    XCTAssertFalse(TIPImageTypeCanWriteWithImageIO((__bridge NSString *)kUTTypeMPEG2Video));

    XCTAssertTrue(TIPImageTypeCanWriteWithImageIO(TIPImageTypeJPEG));
    XCTAssertTrue(TIPImageTypeCanWriteWithImageIO(TIPImageTypeJPEG2000));
    XCTAssertTrue(TIPImageTypeCanWriteWithImageIO(TIPImageTypeTIFF));
    XCTAssertTrue(TIPImageTypeCanWriteWithImageIO(TIPImageTypeGIF));
    XCTAssertTrue(TIPImageTypeCanWriteWithImageIO(TIPImageTypePNG));
    XCTAssertTrue(TIPImageTypeCanWriteWithImageIO(TIPImageTypeBMP));
    XCTAssertTrue(TIPImageTypeCanWriteWithImageIO(TIPImageTypeTARGA));

    XCTAssertFalse(TIPImageTypeCanWriteWithImageIO(@"com.canon.cr2-raw-image"));
    XCTAssertFalse(TIPImageTypeCanWriteWithImageIO(TIPImageTypeICO));
    XCTAssertFalse(TIPImageTypeCanWriteWithImageIO(TIPImageTypePICT));
    XCTAssertFalse(TIPImageTypeCanWriteWithImageIO(TIPImageTypeQTIF));
    XCTAssertFalse(TIPImageTypeCanWriteWithImageIO(TIPImageTypeRAW));
    XCTAssertFalse(TIPImageTypeCanWriteWithImageIO(TIPImageTypeICNS));

    // matching with catalogue

#define ASSERT_CATALOGUE_MATCHES_IO(type) \
    do { \
        XCTAssertEqual(TIPImageTypeCanReadWithImageIO((type)), [[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsDecoding:(type)]); \
        XCTAssertEqual(TIPImageTypeCanWriteWithImageIO((type)), [[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsEncoding:(type)]); \
    } while (0)

    ASSERT_CATALOGUE_MATCHES_IO((__bridge NSString *)kUTTypeImage);
    ASSERT_CATALOGUE_MATCHES_IO((__bridge NSString *)kUTTypeMPEG2Video);
    ASSERT_CATALOGUE_MATCHES_IO(TIPImageTypeJPEG);
    ASSERT_CATALOGUE_MATCHES_IO(TIPImageTypeJPEG2000);
    ASSERT_CATALOGUE_MATCHES_IO(TIPImageTypeTIFF);
    ASSERT_CATALOGUE_MATCHES_IO(TIPImageTypeGIF);
    ASSERT_CATALOGUE_MATCHES_IO(TIPImageTypePNG);
    ASSERT_CATALOGUE_MATCHES_IO(TIPImageTypeBMP);
    ASSERT_CATALOGUE_MATCHES_IO(TIPImageTypeTARGA);
    ASSERT_CATALOGUE_MATCHES_IO(TIPImageTypeICO);

    XCTAssertNotEqual(TIPImageTypeCanReadWithImageIO(@"com.canon.cr2-raw-image"), [[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsDecoding:@"com.canon.cr2-raw-image"]);
    XCTAssertEqual(TIPImageTypeCanWriteWithImageIO(@"com.canon.cr2-raw-image"), [[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsEncoding:@"com.canon.cr2-raw-image"]);
}

- (void)testMatchesTargetDimensionsAndContentMode
{
    CGSize targetDimensions;

    // Equal target and source
    targetDimensions = sImageContainer.dimensions;
    XCTAssertTrue([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter]);
    XCTAssertTrue([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeTopLeft]);
    XCTAssertTrue([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeRedraw]);
    XCTAssertTrue([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill]);
    XCTAssertTrue([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit]);
    XCTAssertTrue([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill]);

    // Smaller target
    targetDimensions = sImageContainer.dimensions;
    targetDimensions.width /= 2.0;
    targetDimensions.height /= 2.0;
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeTopLeft]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeRedraw]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill]);

    // Larger target
    targetDimensions = sImageContainer.dimensions;
    targetDimensions.width *= 2.0;
    targetDimensions.height *= 2.0;
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeTopLeft]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeRedraw]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill]);

    // Larger height
    targetDimensions = sImageContainer.dimensions;
    targetDimensions.height *= 2.0;
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeTopLeft]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeRedraw]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill]);
    XCTAssertTrue([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill]);

    // Smaller height
    targetDimensions = sImageContainer.dimensions;
    targetDimensions.height /= 2.0;
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeTopLeft]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeRedraw]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit]);
    XCTAssertTrue([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill]);

    // Larger width
    targetDimensions = sImageContainer.dimensions;
    targetDimensions.width *= 2.0;
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeTopLeft]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeRedraw]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill]);
    XCTAssertTrue([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill]);

    // Smaller width
    targetDimensions = sImageContainer.dimensions;
    targetDimensions.width /= 2.0;
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeTopLeft]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeRedraw]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill]);
    XCTAssertFalse([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit]);
    XCTAssertTrue([sImageContainer.image tip_matchesTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill]);
}

- (void)testScaled
{
    UIImage *scaledImage;
    CGSize targetDimensions, scaledDimensions, imageDimensions;
    imageDimensions = sImageContainer.dimensions;

    @autoreleasepool {
        // Zero size
        targetDimensions = CGSizeZero;
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
    }

    @autoreleasepool {
        // Matching size
        targetDimensions = imageDimensions;
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
    }

    @autoreleasepool {
        // Smaller size
        targetDimensions = imageDimensions;
        targetDimensions.width = (CGFloat)ceil(targetDimensions.width / 2.0);
        targetDimensions.height = (CGFloat)ceil(targetDimensions.height / 2.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)1.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)1.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
    }

    @autoreleasepool {
        // Larger size
        targetDimensions = imageDimensions;
        targetDimensions.width *= 2.0;
        targetDimensions.height *= 2.0;
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)2.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)2.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
    }

    @autoreleasepool {
        // Smaller width
        targetDimensions = imageDimensions;
        targetDimensions.width = (CGFloat)ceil(targetDimensions.width / 2.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(imageDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(imageDimensions.height / 2.0, scaledDimensions.height, (CGFloat)1.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
    }

    @autoreleasepool {
        // Larger width
        targetDimensions = imageDimensions;
        targetDimensions.width *= 2.0;
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(imageDimensions.height * 2.0, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(imageDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
    }

    @autoreleasepool {
        // Smaller height
        targetDimensions = imageDimensions;
        targetDimensions.height = (CGFloat)ceil(targetDimensions.height / 2.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(imageDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(imageDimensions.width / 2.0, scaledDimensions.width, (CGFloat)1.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
    }

    @autoreleasepool {
        // Larger height
        targetDimensions = imageDimensions;
        targetDimensions.height *= 2.0;
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleToFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFill];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(targetDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(imageDimensions.width * 2.0, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeScaleAspectFit];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualWithAccuracy(imageDimensions.height, scaledDimensions.height, (CGFloat)0.0);
        XCTAssertEqualWithAccuracy(targetDimensions.width, scaledDimensions.width, (CGFloat)0.0);
        scaledImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:UIViewContentModeCenter];
        scaledDimensions = [scaledImage tip_dimensions];
        XCTAssertEqualObjects(sImageContainer.image, scaledImage);
    }

}

- (void)testFixOrientation
{
#define SLOW_IMAGE_CHECK 0

    UIImage *sourceImage = [sImageContainer.image tip_scaledImageWithTargetDimensions:CGSizeMake(1024, 768) contentMode:UIViewContentModeScaleToFill];
#if SLOW_IMAGE_CHECK
    NSData *originalImagePNGData = UIImagePNGRepresentation(sourceImage);
#endif
    UIImage *modifiedImage = nil;
    UIImage *fixedImage = nil;
    XCTAssertEqual(UIImageOrientationUp, sourceImage.imageOrientation);

    // Up
    @autoreleasepool {
        modifiedImage = [self imageByRotatingImage:sourceImage andSettingOrientation:UIImageOrientationUp];
        fixedImage = [modifiedImage tip_orientationAdjustedImage];
        XCTAssertEqualObjects(modifiedImage, fixedImage);
        XCTAssertEqual(fixedImage.imageOrientation, sourceImage.imageOrientation);
#if SLOW_IMAGE_CHECK
        XCTAssertEqualObjects(originalImagePNGData, UIImagePNGRepresentation(modifiedImage));
        XCTAssertEqualObjects(originalImagePNGData, UIImagePNGRepresentation(fixedImage));
#endif
        modifiedImage = nil;
        fixedImage = nil;
    }

    // Down
    @autoreleasepool {
        modifiedImage = [self imageByRotatingImage:sourceImage andSettingOrientation:UIImageOrientationDown];
        fixedImage = [modifiedImage tip_orientationAdjustedImage];
        XCTAssertNotEqual(modifiedImage.imageOrientation, sourceImage.imageOrientation);
        XCTAssertEqual(fixedImage.imageOrientation, sourceImage.imageOrientation);
#if SLOW_IMAGE_CHECK
        XCTAssertNotEqualObjects(originalImagePNGData, UIImagePNGRepresentation(modifiedImage));
        XCTAssertEqualObjects(originalImagePNGData, UIImagePNGRepresentation(fixedImage));
#endif
        modifiedImage = nil;
        fixedImage = nil;
    }

    // Left
    @autoreleasepool {
        modifiedImage = [self imageByRotatingImage:sourceImage andSettingOrientation:UIImageOrientationLeft];
        fixedImage = [modifiedImage tip_orientationAdjustedImage];
        XCTAssertNotEqual(modifiedImage.imageOrientation, sourceImage.imageOrientation);
        XCTAssertEqual(fixedImage.imageOrientation, sourceImage.imageOrientation);
#if SLOW_IMAGE_CHECK
        XCTAssertNotEqualObjects(originalImagePNGData, UIImagePNGRepresentation(modifiedImage));
        XCTAssertEqualObjects(originalImagePNGData, UIImagePNGRepresentation(fixedImage));
#endif
        modifiedImage = nil;
        fixedImage = nil;
    }

    // Right
    @autoreleasepool {
        modifiedImage = [self imageByRotatingImage:sourceImage andSettingOrientation:UIImageOrientationRight];
        fixedImage = [modifiedImage tip_orientationAdjustedImage];
        XCTAssertNotEqual(modifiedImage.imageOrientation, sourceImage.imageOrientation);
        XCTAssertEqual(fixedImage.imageOrientation, sourceImage.imageOrientation);
#if SLOW_IMAGE_CHECK
        XCTAssertNotEqualObjects(originalImagePNGData, UIImagePNGRepresentation(modifiedImage));
        XCTAssertEqualObjects(originalImagePNGData, UIImagePNGRepresentation(fixedImage));
#endif
        modifiedImage = nil;
        fixedImage = nil;
    }

    // UpMirrored
    @autoreleasepool {
        modifiedImage = [self imageByRotatingImage:sourceImage andSettingOrientation:UIImageOrientationUpMirrored];
        fixedImage = [modifiedImage tip_orientationAdjustedImage];
        XCTAssertNotEqual(modifiedImage.imageOrientation, sourceImage.imageOrientation);
        XCTAssertEqual(fixedImage.imageOrientation, sourceImage.imageOrientation);
#if SLOW_IMAGE_CHECK
        XCTAssertNotEqualObjects(originalImagePNGData, UIImagePNGRepresentation(modifiedImage));
        XCTAssertEqualObjects(originalImagePNGData, UIImagePNGRepresentation(fixedImage));
#endif
        modifiedImage = nil;
        fixedImage = nil;
    }

    // DownMirrored
    @autoreleasepool {
        modifiedImage = [self imageByRotatingImage:sourceImage andSettingOrientation:UIImageOrientationDownMirrored];
        fixedImage = [modifiedImage tip_orientationAdjustedImage];
        XCTAssertNotEqual(modifiedImage.imageOrientation, sourceImage.imageOrientation);
        XCTAssertEqual(fixedImage.imageOrientation, sourceImage.imageOrientation);
#if SLOW_IMAGE_CHECK
        XCTAssertNotEqualObjects(originalImagePNGData, UIImagePNGRepresentation(modifiedImage));
        XCTAssertEqualObjects(originalImagePNGData, UIImagePNGRepresentation(fixedImage));
#endif
        modifiedImage = nil;
        fixedImage = nil;
    }

    // LeftMirrored
    @autoreleasepool {
        modifiedImage = [self imageByRotatingImage:sourceImage andSettingOrientation:UIImageOrientationLeftMirrored];
        fixedImage = [modifiedImage tip_orientationAdjustedImage];
        XCTAssertNotEqual(modifiedImage.imageOrientation, sourceImage.imageOrientation);
        XCTAssertEqual(fixedImage.imageOrientation, sourceImage.imageOrientation);
#if SLOW_IMAGE_CHECK
        XCTAssertNotEqualObjects(originalImagePNGData, UIImagePNGRepresentation(modifiedImage));
        XCTAssertEqualObjects(originalImagePNGData, UIImagePNGRepresentation(fixedImage));
#endif
        modifiedImage = nil;
        fixedImage = nil;
    }

    // RightMirrored
    @autoreleasepool {
        modifiedImage = [self imageByRotatingImage:sourceImage andSettingOrientation:UIImageOrientationRightMirrored];
        fixedImage = [modifiedImage tip_orientationAdjustedImage];
        XCTAssertNotEqual(modifiedImage.imageOrientation, sourceImage.imageOrientation);
        XCTAssertEqual(fixedImage.imageOrientation, sourceImage.imageOrientation);
#if SLOW_IMAGE_CHECK
        XCTAssertNotEqualObjects(originalImagePNGData, UIImagePNGRepresentation(modifiedImage));
        XCTAssertEqualObjects(originalImagePNGData, UIImagePNGRepresentation(fixedImage));
#endif
        modifiedImage = nil;
        fixedImage = nil;
    }

#undef SLOW_IMAGE_CHECK
}

- (UIImage *)imageByRotatingImage:(UIImage *)image andSettingOrientation:(UIImageOrientation)orientation
{
    UIImageOrientation antiOrientation = orientation;
    switch (orientation) {
        case UIImageOrientationDown:
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            antiOrientation = orientation;
            break;
        case UIImageOrientationLeft:
            antiOrientation = UIImageOrientationRight;
            break;
        case UIImageOrientationRight:
            antiOrientation = UIImageOrientationLeft;
            break;
        case UIImageOrientationUp:
        default:
            return image;
    }

    UIImage *anti = [UIImage imageWithCGImage:image.CGImage scale:image.scale orientation:antiOrientation];
    anti = [anti tip_orientationAdjustedImage];
    anti = [UIImage imageWithCGImage:anti.CGImage scale:anti.scale orientation:orientation];
    return anti;
}

#pragma mark Image Alpha

- (void)_runTestImageHasAlpha:(UIImage *)image hasAlphaPixel:(BOOL)hasAlphaPixel
{
    NSArray * const colorSpaces =
        @[
             [TestColorSpace colorSpaceWithOwnedRef:CGColorSpaceCreateDeviceGray()
                                     validParamSets:@[
                  PARAM_SET_INT(kCGImageAlphaNone, kCGBitmapByteOrderDefault),
                  PARAM_SET_INT(kCGImageAlphaOnly, kCGBitmapByteOrderDefault),
#if !TARGET_OS_IPHONE
                  [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaNone byteOrder:kCGBitmapByteOrderDefault bytesPerComponent:2],
                  PARAM_SET_FLOAT(kCGImageAlphaNone, kCGBitmapByteOrderDefault),
                  PARAM_SET_FLOAT(kCGImageAlphaNone, kCGBitmapByteOrder32Little),
                  PARAM_SET_FLOAT(kCGImageAlphaNone, kCGBitmapByteOrder32Big),
#endif // !TARGET_OS_IPHONE
                                                      ]],

             [TestColorSpace colorSpaceWithOwnedRef:CGColorSpaceCreateDeviceRGB()
                                     validParamSets:@[
                PARAM_SET_INT(kCGImageAlphaNoneSkipFirst, kCGBitmapByteOrderDefault),
                PARAM_SET_INT(kCGImageAlphaNoneSkipFirst, kCGBitmapByteOrder32Little),
                PARAM_SET_INT(kCGImageAlphaNoneSkipFirst, kCGBitmapByteOrder32Big),
                PARAM_SET_INT(kCGImageAlphaNoneSkipLast, kCGBitmapByteOrderDefault),
                PARAM_SET_INT(kCGImageAlphaNoneSkipLast, kCGBitmapByteOrder32Little),
                PARAM_SET_INT(kCGImageAlphaNoneSkipLast, kCGBitmapByteOrder32Big),
                PARAM_SET_INT(kCGImageAlphaPremultipliedFirst, kCGBitmapByteOrderDefault),
                PARAM_SET_INT(kCGImageAlphaPremultipliedFirst, kCGBitmapByteOrder32Little),
                PARAM_SET_INT(kCGImageAlphaPremultipliedFirst, kCGBitmapByteOrder32Big),
                PARAM_SET_INT(kCGImageAlphaPremultipliedLast, kCGBitmapByteOrderDefault),
                PARAM_SET_INT(kCGImageAlphaPremultipliedLast, kCGBitmapByteOrder32Little),
                PARAM_SET_INT(kCGImageAlphaPremultipliedLast, kCGBitmapByteOrder32Big),
#if !TARGET_OS_IPHONE
                /* Skipping: 16 bits per pixel, 5 bits per component, kCGImageAlphaNoneSkipFirst */
                [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaPremultipliedLast byteOrder:kCGBitmapByteOrderDefault bytesPerComponent:2],
                [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaPremultipliedLast byteOrder:kCGBitmapByteOrder32Little bytesPerComponent:2],
                [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaPremultipliedLast byteOrder:kCGBitmapByteOrder32Big bytesPerComponent:2],
                [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaPremultipliedLast byteOrder:kCGBitmapByteOrder16Little bytesPerComponent:2],
                [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaPremultipliedLast byteOrder:kCGBitmapByteOrder16Big bytesPerComponent:2],
                [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaNoneSkipLast byteOrder:kCGBitmapByteOrderDefault bytesPerComponent:2],
                [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaNoneSkipLast byteOrder:kCGBitmapByteOrder32Little bytesPerComponent:2],
                [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaNoneSkipLast byteOrder:kCGBitmapByteOrder32Big bytesPerComponent:2],
                [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaNoneSkipLast byteOrder:kCGBitmapByteOrder16Little bytesPerComponent:2],
                [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaNoneSkipLast byteOrder:kCGBitmapByteOrder16Big bytesPerComponent:2],
                PARAM_SET_FLOAT(kCGImageAlphaNoneSkipLast, kCGBitmapByteOrderDefault),
                PARAM_SET_FLOAT(kCGImageAlphaPremultipliedLast, kCGBitmapByteOrderDefault),
#endif // !iOS
                                                      ]],

             [TestColorSpace colorSpaceWithOwnedRef:CGColorSpaceCreateDeviceCMYK()
                                     validParamSets:@[
#if !TARGET_OS_IPHONE
                  PARAM_SET_INT(kCGImageAlphaNone, kCGBitmapByteOrderDefault),
                  [TestParamSet integerParamSetWithAlphaInfo:kCGImageAlphaNone byteOrder:kCGBitmapByteOrderDefault bytesPerComponent:2],
                  PARAM_SET_FLOAT(kCGImageAlphaNone, kCGBitmapByteOrderDefault),
#endif // !iOS
                                                      ]],
         ];

    for (TestColorSpace *colorSpace in colorSpaces) {
        for (TestParamSet *paramSet in colorSpace.validParamSets) {
            for (uint32_t useExactBufferSize = 0; useExactBufferSize <= 1; useExactBufferSize++) {
                UIImage *testImage = [self _testImageHasAlpha:image
                                                hasAlphaPixel:hasAlphaPixel
                                                   colorSpace:colorSpace.colorSpace
                                                     paramSet:paramSet
                                           useExactBufferSize:(BOOL)useExactBufferSize];

                if (!testImage) {
                    continue;
                }

                BOOL hasAlphaComponent = NO;
                BOOL alphaOnly = NO;
                switch (paramSet.alphaInfo) {
                    case kCGImageAlphaOnly:
                        alphaOnly = YES;
                    case kCGImageAlphaPremultipliedLast:
                    case kCGImageAlphaPremultipliedFirst:
                    case kCGImageAlphaLast:
                    case kCGImageAlphaFirst:
                        hasAlphaComponent = YES;
                        break;
                    case kCGImageAlphaNoneSkipFirst:
                    case kCGImageAlphaNoneSkipLast:
                    case kCGImageAlphaNone:
                    default:
                        break;
                }

                if (!hasAlphaComponent) {
                    XCTAssertFalse([testImage tip_hasAlpha:NO]);
                    XCTAssertFalse([testImage tip_hasAlpha:YES]);
                } else {
                    XCTAssertTrue([testImage tip_hasAlpha:NO]);
                    if (hasAlphaPixel) {
                        XCTAssertTrue([testImage tip_hasAlpha:YES]);
                    } else {
                        XCTAssertFalse([testImage tip_hasAlpha:YES]);
                    }
                }
            }
        }
    }
}

- (UIImage *)_testImageHasAlpha:(UIImage *)image
                  hasAlphaPixel:(BOOL)hasAlphaPixel
                     colorSpace:(CGColorSpaceRef)colorSpace
                       paramSet:(TestParamSet *)paramSet
             useExactBufferSize:(BOOL)useExactBufferSize
{
    CGBitmapInfo bitmapInfo = 0;
    if (paramSet.useFloat) {
        bitmapInfo |= kCGBitmapFloatComponents;
    }
    bitmapInfo |= paramSet.byteOrder & kCGBitmapByteOrderMask;
    bitmapInfo |= paramSet.alphaInfo;

    BOOL hasAlphaComponent = NO;
    BOOL alphaOnly = NO;
    switch (paramSet.alphaInfo) {
        case kCGImageAlphaOnly:
            alphaOnly = YES;
        case kCGImageAlphaPremultipliedLast:
        case kCGImageAlphaPremultipliedFirst:
        case kCGImageAlphaLast:
        case kCGImageAlphaFirst:
            hasAlphaComponent = YES;
            break;
        case kCGImageAlphaNoneSkipFirst:
        case kCGImageAlphaNoneSkipLast:
            hasAlphaComponent = YES; // component, but empty
            break;
        case kCGImageAlphaNone:
        default:
            break;
    }

    CGSize size = [image tip_dimensions];

    size_t bytesPerRow = 0;
    if (useExactBufferSize) {
        bytesPerRow = paramSet.bytesPerComponent;
        if (!alphaOnly) {
            bytesPerRow *= (hasAlphaComponent ? 1 : 0) + CGColorSpaceGetNumberOfComponents(colorSpace);
        }
        bytesPerRow *= (size_t)size.width;
    }

    CGContextRef cgContext = CGBitmapContextCreate(NULL, // auto buffer
                                                   (size_t)size.width,
                                                   (size_t)size.height,
                                                   paramSet.bytesPerComponent * 8,
                                                   bytesPerRow,
                                                   colorSpace,
                                                   bitmapInfo);
    TIPDeferRelease(cgContext);
    if (!cgContext) {
        return nil;
    }

    CGContextDrawImage(cgContext, CGRectMake(0, 0, size.width, size.height), image.CGImage);
    CGImageRef cgImage = CGBitmapContextCreateImage(cgContext);
    TIPDeferRelease(cgImage);
    UIImage *testImage = [UIImage imageWithCGImage:cgImage];
    return testImage;
}

- (void)testImageHasAlpha
{
    setenv("CGBITMAP_CONTEXT_LOG_ERRORS", "1", 0);

    NSBundle *bundle = TIPTestsResourceBundle();

    NSData *dataNoAlpha = [NSData dataWithContentsOfFile:[bundle pathForResource:@"noAlpha" ofType:@"png"]];
    NSData *dataSomeAlpha = [NSData dataWithContentsOfFile:[bundle pathForResource:@"someAlpha" ofType:@"png"]];
    NSData *dataAllAlpha = [NSData dataWithContentsOfFile:[bundle pathForResource:@"allAlpha" ofType:@"png"]];

    UIImage *imageNoAlpha = [UIImage imageWithData:dataNoAlpha];
    UIImage *imageSomeAlpha = [UIImage imageWithData:dataSomeAlpha];
    UIImage *imageAllAlpha = [UIImage imageWithData:dataAllAlpha];

    [self _runTestImageHasAlpha:imageNoAlpha hasAlphaPixel:NO];
    [self _runTestImageHasAlpha:imageSomeAlpha hasAlphaPixel:YES];
    [self _runTestImageHasAlpha:imageAllAlpha hasAlphaPixel:YES];
}

- (void)testTIPImageTypeMatchesUTType
{
    XCTAssertEqualObjects((NSString *)kUTTypeJPEG, TIPImageTypeJPEG);
    XCTAssertEqualObjects((NSString *)kUTTypeJPEG2000, TIPImageTypeJPEG2000);
    XCTAssertEqualObjects((NSString *)kUTTypeTIFF, TIPImageTypeTIFF);
    XCTAssertEqualObjects((NSString *)kUTTypePICT, TIPImageTypePICT);
    XCTAssertEqualObjects((NSString *)kUTTypeGIF, TIPImageTypeGIF);
    XCTAssertEqualObjects((NSString *)kUTTypePNG, TIPImageTypePNG);
    XCTAssertEqualObjects((NSString *)kUTTypeQuickTimeImage, TIPImageTypeQTIF);
    XCTAssertEqualObjects((NSString *)kUTTypeAppleICNS, TIPImageTypeICNS);
    XCTAssertEqualObjects((NSString *)kUTTypeBMP, TIPImageTypeBMP);
    XCTAssertEqualObjects(@"com.truevision.tga-image", TIPImageTypeTARGA);
    XCTAssertEqualObjects((NSString *)kUTTypeICO, TIPImageTypeICO);
    XCTAssertEqualObjects((NSString *)kUTTypeRawImage, TIPImageTypeRAW);
}

@end
