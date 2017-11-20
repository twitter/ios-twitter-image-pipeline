//
//  TIPImageContainer.m
//  TwitterImagePipeline
//
//  Created on 10/8/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageCodecCatalogue.h"
#import "TIPImageContainer.h"
#import "TIPImageUtils.h"
#import "UIImage+TIPAdditions.h"

NS_ASSUME_NONNULL_BEGIN

@interface TIPImageContainer ()
@property (nonatomic, readonly) NSUInteger loopCount;
@end

@implementation TIPImageContainer
{
    NSArray *_frameDurations;
    UIImage *_image;
}

- (instancetype)initWithImage:(UIImage *)image animated:(BOOL)animated loopCount:(NSUInteger)loopCount frameDurations:(nullable NSArray *)durations
{
    if (!image) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"MUST provide non-nil image argument!" userInfo:nil];
    }

    if (durations != nil && durations.count != image.images.count) {
        TIPLogWarning(@"Provided animation frame durations count doesn't equal number of animation frames!  Reverting to UIImage.duration for calculating the animation frame durations");
        durations = nil;
    }

    if (self = [super init]) {
        _image = image;
        _animated = animated;
        _loopCount = loopCount;
        _frameDurations = [durations copy];
    }
    return self;
}

- (instancetype)initWithImage:(UIImage *)image
{
    return [self initWithImage:image animated:(image.images.count > 1) loopCount:0 frameDurations:nil];
}

- (instancetype)initWithAnimatedImage:(UIImage *)image loopCount:(NSUInteger)loopCount frameDurations:(nullable NSArray *)durations
{
    return [self initWithImage:image animated:(image.images.count > 1) loopCount:loopCount frameDurations:durations];
}

- (UIImage *)image
{
    if (!_image) {
        [[TIPGlobalConfiguration sharedInstance] postProblem:TIPProblemImageContainerHasNilImage userInfo:@{}];
    }
    return (UIImage * __nonnull)_image;
}

- (NSUInteger)frameCount
{
    return (_animated) ? _image.images.count : 1;
}

- (nullable NSArray *)frames
{
    return _image.images;
}

- (nullable NSArray *)frameDurations
{
    if (!_frameDurations && _animated) {
        const NSUInteger count = _image.images.count;
        NSNumber *duration = @(_image.duration / count);
        NSMutableArray *durations = [[NSMutableArray alloc] initWithCapacity:count];
        for (NSUInteger i = 0; i < count; i++) {
            [durations addObject:duration];
        }
        _frameDurations = [durations copy];
    }
    return _frameDurations;
}

- (nullable UIImage *)frameAtIndex:(NSUInteger)index
{
    if (_animated) {
        if (index < _image.images.count) {
            return _image.images[index];
        }
    } else {
        if (index == 0) {
            return _image;
        }
    }
    return nil;
}

- (NSTimeInterval)frameDurationAtIndex:(NSUInteger)index
{
    if (!_animated) {
        return 0.0;
    }

    NSArray *durations = self.frameDurations;
    return durations.count > index ? [durations[index] doubleValue] : 0.0;
}

- (NSString *)description
{
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@ : %p", NSStringFromClass([self class]), self];

    [description appendFormat:@", size=%@, scale=%f", NSStringFromCGSize(_image.size), _image.scale];

    if (self.isAnimated) {
        [description appendFormat:@", frames=%tu, loopCount=%tu, durations=[%@]", self.frameCount, self.loopCount, [self.frameDurations componentsJoinedByString:@" "]];
    }

    [description appendFormat:@">"];

    return description;
}

@end

@implementation TIPImageContainer (Convenience)

+ (nullable instancetype)imageContainerWithImageSource:(CGImageSourceRef)imageSource
{
    if (!imageSource) {
        return nil;
    }

    const size_t count = CGImageSourceGetCount(imageSource);
    if (!count) {
        return nil;
    } else if (count == 1) {
        CGImageRef cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
        TIPDeferRelease(cgImage);
        UIImage *image = (cgImage) ? [UIImage imageWithCGImage:cgImage scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp] : nil;
        return (image) ? [(TIPImageContainer *)[[self class] alloc] initWithImage:image] : nil;
    }

    NSArray *durations;
    NSUInteger loopCount;
    UIImage *image = [UIImage tip_imageWithAnimatedImageSource:imageSource durations:&durations loopCount:&loopCount];
    return [(TIPImageContainer *)[[self class] alloc] initWithAnimatedImage:image loopCount:loopCount frameDurations:durations];
}

+ (nullable instancetype)imageContainerWithData:(NSData *)data decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
{
    if (!catalogue) {
        catalogue = [TIPImageCodecCatalogue sharedInstance];
    }

    return [catalogue decodeImageWithData:data decoderConfigMap:decoderConfigMap imageType:NULL];
}

+ (nullable instancetype)imageContainerWithFilePath:(NSString *)filePath decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue memoryMap:(BOOL)map
{
    return [self imageContainerWithFileURL:[NSURL fileURLWithPath:filePath isDirectory:NO] decoderConfigMap:decoderConfigMap codecCatalogue:catalogue memoryMap:map];
}

+ (nullable instancetype)imageContainerWithFileURL:(NSURL *)fileURL decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue memoryMap:(BOOL)map
{
    if (!fileURL.isFileURL) {
        return nil;
    }

    NSData *data = nil;
    if (map) {
        data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:NULL];
    } else {
        data = [NSData dataWithContentsOfURL:fileURL];
    }

    return (data) ? [self imageContainerWithData:data decoderConfigMap:decoderConfigMap codecCatalogue:catalogue] : nil;
}

- (NSUInteger)sizeInMemory
{
    return [self.image tip_estimatedSizeInBytes];
}

- (CGSize)dimensions
{
    return [self.image tip_dimensions];
}

- (BOOL)saveToFilePath:(NSString *)path type:(nullable NSString *)type codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue options:(TIPImageEncodingOptions)options quality:(float)quality atomic:(BOOL)atomic error:(out NSError * __autoreleasing __nullable * __nullable)error
{
    if (!catalogue) {
        catalogue = [TIPImageCodecCatalogue sharedInstance];
    }
    if (!type) {
        const TIPRecommendedImageTypeOptions recoOptions = TIPRecommendedImageTypeOptionsFromEncodingOptions(options, quality);
        type = [self.image tip_recommendedImageType:recoOptions];
    }

    return [catalogue encodeImage:self toFilePath:path withImageType:type quality:quality options:options atomic:atomic error:error];
}

- (nullable TIPImageContainer *)scaleToTargetDimensions:(CGSize)dimensions contentMode:(UIViewContentMode)contentMode
{
    TIPAssert(self.image != nil);
    UIImage *image = [self.image tip_scaledImageWithTargetDimensions:dimensions contentMode:contentMode];
    if (!image) {
        return nil;
    }

    return [[TIPImageContainer alloc] initWithImage:image animated:self.isAnimated loopCount:self.loopCount frameDurations:self.frameDurations];
}

- (void)decode
{
    [self.image tip_decode];
}

@end

NS_ASSUME_NONNULL_END
