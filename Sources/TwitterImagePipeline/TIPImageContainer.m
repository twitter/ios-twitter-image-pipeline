//
//  TIPImageContainer.m
//  TwitterImagePipeline
//
//  Created on 10/8/15.
//  Copyright © 2020 Twitter. All rights reserved.
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
    NSArray<NSNumber *> *_frameDurations;
    UIImage *_image;
}

- (instancetype)initWithImage:(UIImage *)image
                     animated:(BOOL)animated
                    loopCount:(NSUInteger)loopCount
               frameDurations:(nullable NSArray<NSNumber *> *)durations
{
    if (!image) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"MUST provide non-nil image argument!"
                                     userInfo:nil];
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
    return [self initWithImage:image
                      animated:(image.images.count > 1)
                     loopCount:0
                frameDurations:nil];
}

- (instancetype)initWithAnimatedImage:(UIImage *)image
                            loopCount:(NSUInteger)loopCount
                       frameDurations:(nullable NSArray<NSNumber *> *)durations
{
    return [self initWithImage:image
                      animated:(image.images.count > 1)
                     loopCount:loopCount
                frameDurations:durations];
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

- (nullable NSArray<UIImage *> *)frames
{
    return _image.images;
}

- (nullable NSArray<NSNumber *> *)frameDurations
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

- (id)descriptor
{
    NSValue *dimensions = [NSValue valueWithCGSize:[self dimensions]];
    if (self.isAnimated) {
        return @{
            @"dimensions" : dimensions,
            @"frameDurations" : self.frameDurations ?: @[],
            @"loopCount" : @(self.loopCount)
        };
    }

    return @{ @"dimensions" : dimensions };
}

@end

@implementation TIPImageContainer (Convenience)

+ (nullable instancetype)imageContainerWithImage:(UIImage *)image descriptor:(id)descriptor
{
    TIPAssert(image != nil);
    TIPAssert(descriptor != nil);
    if (!image || !descriptor) {
        return nil;
    }

    NSDictionary *d = descriptor;
    if (![d isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    CGSize dims = [(NSValue*)d[@"dimensions"] CGSizeValue];
    if (!CGSizeEqualToSize(image.tip_dimensions, dims)) {
        return nil;
    }

    NSArray<NSNumber *> *frameDurations = d[@"frameDurations"];
    if (frameDurations && ![frameDurations isKindOfClass:[NSArray class]]) {
        return nil;
    }

    if (frameDurations && image.images.count <= 1) {
        return nil;
    }

    if (frameDurations && frameDurations.count != image.images.count) {
        return nil;
    }

    const NSUInteger loopCount = (frameDurations != nil) ? [d[@"loopCount"] unsignedIntegerValue] : 0;

    return [[self alloc] initWithImage:image
                              animated:frameDurations != nil
                             loopCount:loopCount
                        frameDurations:frameDurations];
}

//! returns negative value if all the images are the same size (aka is an animation)
static CFIndex _DetectLargestNonAnimatedImageIndex(CGImageSourceRef imageSource)
{
    const size_t count = CGImageSourceGetCount(imageSource);
    TIPAssert(count > 0);

    if (count == 1) {
        // definitely not animated
        return 0;
    }

    /**
     We have multiple frames...
     If all the frames are the same size, we have an animation.
     If any of the frames differ in size, we have a set of images in a single container, use the largest one.

        Look at the first 5 frames (or count of frames, whichever is less).
        If first frames are all the same size, treat image as an animation (return -1)
        Else if the size in first frames differs, continue through all frames to find largest (return that index)
     */

    BOOL allEqual = YES;
    CFIndex largestIndex = -1;
    CGSize largestSize = CGSizeZero;
    static const size_t kMaxFramesAllEqualCountLimit = 5;
    const size_t maxFramesAllEqualCount = MIN(count, kMaxFramesAllEqualCountLimit);

    for (size_t i = 0; (allEqual ? (i < maxFramesAllEqualCount) : (i < count)); i++) {
        const CGSize size = TIPDetectImageSourceDimensionsAtIndex(imageSource, i);
        if (CGSizeEqualToSize(size, CGSizeZero)) {
            // no dimensions, skip
            continue;
        }

        if (size.width > largestSize.width && size.height > largestSize.height) {
            largestSize = size;
            if (largestIndex < 0) {
                // never had a largest size yet
                largestIndex = (CFIndex)i;
            } else {
                // already had a largest size
                allEqual = NO;
                largestIndex = (CFIndex)i;
            }
        } else if (size.width < largestSize.width && size.height < largestSize.height) {
            TIPAssert(largestIndex >= 0);
            allEqual = NO;
        }
    }

    return (allEqual) ? -1 : largestIndex;
}

+ (nullable instancetype)imageContainerWithImageSource:(CGImageSourceRef)imageSource
{
    return [self imageContainerWithImageSource:imageSource
                              targetDimensions:CGSizeZero
                             targetContentMode:UIViewContentModeCenter];
}

+ (nullable instancetype)imageContainerWithImageSource:(CGImageSourceRef)imageSource
                                      targetDimensions:(CGSize)targetDimensions
                                     targetContentMode:(UIViewContentMode)targetContentMode
{
    if (!imageSource) {
        return nil;
    }

    const size_t count = CGImageSourceGetCount(imageSource);
    if (!count) {
        return nil;
    }

    const CFIndex index = _DetectLargestNonAnimatedImageIndex(imageSource);
    if (index >= 0) {
        // not animated
        UIImage *image = [UIImage tip_imageWithImageSource:imageSource
                                                   atIndex:(NSUInteger)index
                                          targetDimensions:targetDimensions
                                         targetContentMode:targetContentMode];
        return (image) ? [(TIPImageContainer *)[[self class] alloc] initWithImage:image] : nil;
    }

    // made it here, means we are animated

    NSArray *durations;
    NSUInteger loopCount;
    UIImage *image = [UIImage tip_imageWithAnimatedImageSource:imageSource
                                              targetDimensions:targetDimensions
                                             targetContentMode:targetContentMode
                                                     durations:&durations
                                                     loopCount:&loopCount];
    return [(TIPImageContainer *)[[self class] alloc] initWithAnimatedImage:image
                                                                  loopCount:loopCount
                                                             frameDurations:durations];
}

+ (nullable instancetype)imageContainerWithData:(NSData *)data
                               decoderConfigMap:(nullable NSDictionary<NSString *,id> *)decoderConfigMap
                                 codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
{
    return [self imageContainerWithData:data
                       targetDimensions:CGSizeZero
                      targetContentMode:UIViewContentModeCenter
                       decoderConfigMap:decoderConfigMap
                         codecCatalogue:catalogue];
}

+ (nullable instancetype)imageContainerWithData:(NSData *)data
                               targetDimensions:(CGSize)targetDimensions
                              targetContentMode:(UIViewContentMode)targetContentMode
                               decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
                                 codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
{
    if (!catalogue) {
        catalogue = [TIPImageCodecCatalogue sharedInstance];
    }

    return [catalogue decodeImageWithData:data
                         targetDimensions:targetDimensions
                        targetContentMode:targetContentMode
                         decoderConfigMap:decoderConfigMap
                                imageType:NULL];
}

+ (nullable instancetype)imageContainerWithFilePath:(NSString *)filePath
                                   decoderConfigMap:(nullable NSDictionary<NSString *,id> *)decoderConfigMap
                                     codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
                                          memoryMap:(BOOL)map
{
    return [self imageContainerWithFilePath:filePath
                           targetDimensions:CGSizeZero
                          targetContentMode:UIViewContentModeCenter
                           decoderConfigMap:decoderConfigMap
                             codecCatalogue:catalogue
                                  memoryMap:map];
}

+ (nullable instancetype)imageContainerWithFilePath:(NSString *)filePath
                                   targetDimensions:(CGSize)targetDimensions
                                  targetContentMode:(UIViewContentMode)targetContentMode
                                   decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
                                     codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
                                          memoryMap:(BOOL)map
{
    return [self imageContainerWithFileURL:[NSURL fileURLWithPath:filePath isDirectory:NO]
                          targetDimensions:targetDimensions
                         targetContentMode:targetContentMode
                          decoderConfigMap:decoderConfigMap
                            codecCatalogue:catalogue
                                 memoryMap:map];
}

+ (nullable instancetype)imageContainerWithFileURL:(NSURL *)fileURL
                                  decoderConfigMap:(nullable NSDictionary<NSString *,id> *)decoderConfigMap
                                    codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
                                         memoryMap:(BOOL)map
{
    return [self imageContainerWithFileURL:fileURL
                          targetDimensions:CGSizeZero
                         targetContentMode:UIViewContentModeCenter
                          decoderConfigMap:decoderConfigMap
                            codecCatalogue:catalogue
                                 memoryMap:map];
}

+ (nullable instancetype)imageContainerWithFileURL:(NSURL *)fileURL
                                  targetDimensions:(CGSize)targetDimensions
                                 targetContentMode:(UIViewContentMode)targetContentMode
                                  decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
                                    codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
                                         memoryMap:(BOOL)map
{
    if (!fileURL.isFileURL) {
        return nil;
    }

    NSData *data = nil;
    if (map) {
        data = [NSData dataWithContentsOfURL:fileURL
                                     options:NSDataReadingMappedIfSafe
                                       error:NULL];
    } else {
        data = [NSData dataWithContentsOfURL:fileURL];
    }

    if (!data) {
        return nil;
    }

    return [self imageContainerWithData:data
                       targetDimensions:targetDimensions
                      targetContentMode:targetContentMode
                       decoderConfigMap:decoderConfigMap
                         codecCatalogue:catalogue];
}

- (NSUInteger)sizeInMemory
{
    return [self.image tip_estimatedSizeInBytes];
}

- (CGSize)dimensions
{
    return [self.image tip_dimensions];
}

- (CGSize)pointSize
{
    return [self.image tip_pointSize];
}

- (BOOL)saveToFilePath:(NSString *)path
                  type:(nullable NSString *)type
        codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
               options:(TIPImageEncodingOptions)options
               quality:(float)quality
                atomic:(BOOL)atomic
                 error:(out NSError * __autoreleasing __nullable * __nullable)error
{
    if (!catalogue) {
        catalogue = [TIPImageCodecCatalogue sharedInstance];
    }
    if (!type) {
        const TIPRecommendedImageTypeOptions recoOptions = TIPRecommendedImageTypeOptionsFromEncodingOptions(options, quality);
        type = [self.image tip_recommendedImageType:recoOptions];
    }

    return [catalogue encodeImage:self
                       toFilePath:path
                    withImageType:type
                          quality:quality
                          options:options
                           atomic:atomic
                            error:error];
}

- (nullable TIPImageContainer *)scaleToTargetDimensions:(CGSize)dimensions
                                            contentMode:(UIViewContentMode)contentMode
{
    TIPAssert(self.image != nil);
    UIImage *image = [self.image tip_scaledImageWithTargetDimensions:dimensions
                                                         contentMode:contentMode];
    if (!image) {
        return nil;
    }

    return [[TIPImageContainer alloc] initWithImage:image
                                           animated:self.isAnimated
                                          loopCount:self.loopCount
                                     frameDurations:self.frameDurations];
}

- (void)decode
{
    [self.image tip_decode];
}

@end

NS_ASSUME_NONNULL_END
