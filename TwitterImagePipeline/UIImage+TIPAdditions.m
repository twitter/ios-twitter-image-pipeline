//
//  UIImage+TIPAdditions.m
//  TwitterImagePipeline
//
//  Created on 9/6/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageUtils.h"
#import "UIImage+TIPAdditions.h"

NS_ASSUME_NONNULL_BEGIN
static NSDictionary *TIPImageWritingProperties(UIImage *image,
                                               NSString *type,
                                               TIPImageEncodingOptions options,
                                               float quality,
                                               NSNumber * __nullable animationLoopCount,
                                               NSNumber * __nullable animationDuration,
                                               BOOL isGlobalProperties);
static CGImageRef __nullable TIPCGImageCreateGrayscale(CGImageRef __nullable imageRef);
NS_ASSUME_NONNULL_END

@implementation UIImage (TIPAdditions)

#pragma mark Inferred Properties

- (CGSize)tip_dimensions
{
    return TIPDimensionsFromSizeScaled(self.size, self.scale);
}

- (NSUInteger)tip_estimatedSizeInBytes
{
    // Often an image can have additional bytes as a buffer per row of pixels.
    // Getting the true byte size will be most accurate.

    const NSUInteger bytesPerRow = self.CGImage ? CGImageGetBytesPerRow(self.CGImage) : 0;
    if (!bytesPerRow) {
        // unknown bytes per row, guesstimate
        return TIPEstimateMemorySizeOfImageWithSettings(self.size, self.scale, 4 /* Guess RGB+A == 4 bytes */, self.images.count);
    }

    const NSUInteger rowCount = (NSUInteger)(self.size.height * self.scale);
    return bytesPerRow * rowCount;
}

- (NSUInteger)tip_imageCountBasedOnImageType:(NSString *)type
{
    if (!type || [type isEqualToString:TIPImageTypeGIF] /* only GIF for now */) {
        return MAX((NSUInteger)1, self.images.count);
    }

    return 1;
}

- (BOOL)tip_hasAlpha:(BOOL)inspectPixels
{
    if (self.images.count > 0) {
        UIImage *image = self.images.firstObject;
        return image ? [image tip_hasAlpha:inspectPixels] : YES /* assume alpha */;
    }

    if (self.CGImage) {
        return TIPCGImageHasAlpha(self.CGImage, inspectPixels);
    } else if (self.CIImage) {
        return TIPCIImageHasAlpha(self.CIImage, inspectPixels);
    }

    return YES; // just assume alpha
}

#pragma mark Inspection Methods

- (NSString *)tip_recommendedImageType:(TIPRecommendedImageTypeOptions)options
{
    if (self.images.count > 1) {
        return TIPImageTypeGIF;
    }

    BOOL alpha = NO;
    if (TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPRecommendedImageTypeAssumeAlpha)) {
        alpha = YES;
    } else if (TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPRecommendedImageTypeAssumeNoAlpha)) {
        alpha = NO;
    } else {
        alpha = [self tip_hasAlpha:YES];
    }
    const BOOL progressive = TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPRecommendedImageTypePreferProgressive);
    const BOOL lossy = TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPRecommendedImageTypePermitLossy);

    if (alpha) {
        if (lossy) {
            return TIPImageTypePNG; /* PNG for now, might want JPEG2000 */
        }
        if (progressive) {
            return TIPImageTypePNG; /* PNG for now */
        }

        return TIPImageTypePNG;
    }

    if (progressive) {
        return TIPImageTypeJPEG;
    }

    return TIPImageTypeJPEG;
}

- (BOOL)tip_matchesTargetDimensions:(CGSize)targetDimensions contentMode:(UIViewContentMode)targetContentMode
{
    return TIPSizeMatchesTargetSizing([self tip_dimensions], targetDimensions, targetContentMode, 1);
}

#pragma mark Transform Methods

- (UIImage *)tip_scaledImageWithTargetDimensions:(CGSize)targetDimensions contentMode:(UIViewContentMode)targetContentMode;
{
    __block UIImage *image = self;

    const CGSize dimensions = [image tip_dimensions];
    const CGSize scaledTargetDimensions = TIPSizeGreaterThanZero(targetDimensions) ? TIPDimensionsScaledToTargetSizing(dimensions, targetDimensions, targetContentMode) : CGSizeZero;

    // If we have a target size and the target size is not the same as our source image's size, draw the resized image
    if (TIPSizeGreaterThanZero(scaledTargetDimensions) && !CGSizeEqualToSize(dimensions, scaledTargetDimensions)) {
        const CGFloat scale = [UIScreen mainScreen].scale;
        const CGRect drawRect = CGRectMake(0, 0, scaledTargetDimensions.width / scale, scaledTargetDimensions.height / scale);
        const BOOL hasAlpha = [image tip_hasAlpha:NO];

        TIPExecuteCGContextBlock(^{
            UIGraphicsBeginImageContextWithOptions(drawRect.size, !hasAlpha, scale);
            if (!image.images.count) {
                [image drawInRect:drawRect];
                image = UIGraphicsGetImageFromCurrentImageContext();
            } else {
                NSMutableArray *newFrames = [[NSMutableArray alloc] initWithCapacity:image.images.count];
                for (UIImage *frame in image.images) {
                    @autoreleasepool {
                        [frame drawInRect:drawRect];
                        UIImage *newFrame = UIGraphicsGetImageFromCurrentImageContext();
                        [newFrames addObject:newFrame];
                    }
                }
                image = [UIImage animatedImageWithImages:newFrames duration:image.duration];
            }
            UIGraphicsEndImageContext();
        });
    }

    if (image == self) {
        [image tip_decode];
    }

    if (!image) {
        NSDictionary *userInfo = @{
                                   TIPProblemInfoKeyImageDimensions : [NSValue valueWithCGSize:dimensions],
                                   TIPProblemInfoKeyTargetDimensions : [NSValue valueWithCGSize:targetDimensions],
                                   TIPProblemInfoKeyTargetContentMode : @(targetContentMode),
                                   TIPProblemInfoKeyScaledDimensions : [NSValue valueWithCGSize:scaledTargetDimensions],
                                   TIPProblemInfoKeyImageIsAnimated : @(self.images.count > 1),
                                   };
        [[TIPGlobalConfiguration sharedInstance] postProblem:TIPProblemImageFailedToScale userInfo:userInfo];
    }
    TIPAssert(image != nil);

    return image;
}

- (UIImage *)tip_orientationAdjustedImage
{
    UIImage *sourceImage = self;

    if (UIImageOrientationUp == sourceImage.imageOrientation) {
        return sourceImage;
    }

    if (sourceImage.CIImage) {
        sourceImage = [sourceImage tip_CGImageBackedImageAndReturnError:NULL] ?: sourceImage;
    }

    if (!sourceImage.CGImage) {
        return sourceImage; // TODO: support rotating animated images
    }

    CGSize dimensions = [sourceImage tip_dimensions];
    CGAffineTransform transform = CGAffineTransformIdentity;

    // 1) rotate
    switch (sourceImage.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, dimensions.width, dimensions.height);
            transform = CGAffineTransformRotate(transform, (CGFloat)M_PI);
            break;

        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, dimensions.width, 0);
            transform = CGAffineTransformRotate(transform, (CGFloat)M_PI_2);
            break;

        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, dimensions.height);
            transform = CGAffineTransformRotate(transform, (CGFloat)-M_PI_2);
            break;
        case UIImageOrientationUp:
            TIPAssertNever();
        case UIImageOrientationUpMirrored:
            break;
    }

    // Flip
    switch (sourceImage.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, dimensions.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;

        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, dimensions.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationUp:
            TIPAssertNever();
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }

    // Draw
    __block UIImage *image = nil;
    TIPExecuteCGContextBlock(^{
        CGContextRef ctx = CGBitmapContextCreate(NULL,
                                                 (size_t)dimensions.width,
                                                 (size_t)dimensions.height,
                                                 CGImageGetBitsPerComponent(sourceImage.CGImage),
                                                 0,
                                                 CGImageGetColorSpace(sourceImage.CGImage),
                                                 CGImageGetBitmapInfo(sourceImage.CGImage));
        TIPDeferRelease(ctx);
        CGContextConcatCTM(ctx, transform);
        switch (sourceImage.imageOrientation) {
            case UIImageOrientationLeft:
            case UIImageOrientationLeftMirrored:
            case UIImageOrientationRight:
            case UIImageOrientationRightMirrored:
                CGContextDrawImage(ctx, CGRectMake(0, 0, dimensions.height, dimensions.width), sourceImage.CGImage);
                break;
            default:
                CGContextDrawImage(ctx, CGRectMake(0, 0, dimensions.width, dimensions.height), sourceImage.CGImage);
                break;
        }

        // Get the image
        CGImageRef cgImage = CGBitmapContextCreateImage(ctx);
        TIPDeferRelease(cgImage);
        image = [UIImage imageWithCGImage:cgImage scale:sourceImage.scale orientation:UIImageOrientationUp];
    });
    return image;
}

- (UIImage *)tip_CGImageBackedImageAndReturnError:(out NSError **)error;
{
    __block NSError *outError = nil;
    tip_defer(^{
        if (error) {
            *error = outError;
        }
    });

    if (self.CGImage) {
        return self;
    }

    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 9 && !TIPIsExtension()) {
        // Cannot do GPU work in the background before iOS 9
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        if ([[UIApplicationClass sharedApplication] applicationState] == UIApplicationStateBackground) {
            // In background, abort
            outError = [NSError errorWithDomain:TIPErrorDomain code:TIPErrorCodeCannotUseGPUInBackground userInfo:nil];
            return nil;
        }
    }

    CIImage *CIImage = self.CIImage;
    if (!CIImage) {
        outError = [NSError errorWithDomain:TIPErrorDomain code:TIPErrorCodeMissingCIImage userInfo:nil];
        return nil;
    }

    __block UIImage *image = nil;
    TIPExecuteCGContextBlock(^{
        CIContext *context = [CIContext contextWithOptions:nil];
        CGImageRef cgImage = [context createCGImage:CIImage fromRect:CIImage.extent];
        TIPDeferRelease(cgImage);
        if (cgImage) {
            image = [UIImage imageWithCGImage:cgImage scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
        }
    });

    if (!image) {
        outError = [NSError errorWithDomain:TIPErrorDomain code:TIPErrorCodeUnknown userInfo:nil];
        return nil;
    }

    return image;
}

- (UIImage *)tip_grayscaleImage
{
    CGImageRef originalImageRef = self.CGImage;
    CGImageRef grayscaleImageRef = TIPCGImageCreateGrayscale(originalImageRef);
    TIPDeferRelease(grayscaleImageRef);
    if (!grayscaleImageRef) {
        return nil;
    } else if (grayscaleImageRef == originalImageRef) {
        return self;
    }
    return [UIImage imageWithCGImage:grayscaleImageRef];
}

#pragma mark Decode Methods

+ (UIImage *)tip_imageWithAnimatedImageFile:(NSString *)filePath
                                  durations:(out NSArray<NSNumber *> **)durationsOut
                                  loopCount:(out NSUInteger *)loopCountOut
{
    NSURL *fileURL = [NSURL fileURLWithPath:filePath isDirectory:NO];
    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((CFURLRef)fileURL, NULL);
    TIPDeferRelease(imageSource);
    if (imageSource) {
        return [self tip_imageWithAnimatedImageSource:imageSource
                                            durations:durationsOut
                                            loopCount:loopCountOut];
    }
    return nil;
}

+ (UIImage *)tip_imageWithAnimatedImageData:(NSData *)data
                                  durations:(out NSArray<NSNumber *> **)durationsOut
                                  loopCount:(out NSUInteger *)loopCountOut
{
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    TIPDeferRelease(imageSource);
    if (imageSource) {
        return [self tip_imageWithAnimatedImageSource:imageSource
                                            durations:durationsOut
                                            loopCount:loopCountOut];
    }
    return nil;
}

#pragma mark Encode Methods

- (BOOL)tip_writeToCGImageDestinationWithBlock:(CGImageDestinationRef(^)(NSString *UTType, const NSUInteger imageCount))desinationCreationBlock
                                          type:(NSString *)type
                               encodingOptions:(TIPImageEncodingOptions)options
                                       quality:(float)quality
                            animationLoopCount:(NSUInteger)animationLoopCount
                       animationFrameDurations:(NSArray<NSNumber *> *)animationFrameDurations
                                         error:(out NSError **)error
{
    __block NSError *theError = nil;
    tip_defer(^{
        if (error) {
            *error = theError;
        }
    });

    UIImage *image = self;
    if (image.CIImage && !image.CGImage && image.images.count == 0) {
        image = [image tip_CGImageBackedImageAndReturnError:&theError];
        if (theError != nil) {
            return NO;
        }
        TIPAssert(image != nil);
    }

    if (!image.CGImage && image.images.count == 0) {
        theError = [NSError errorWithDomain:TIPErrorDomain code:TIPErrorCodeMissingCGImage userInfo:nil];
        return NO;
    }

    if (!type) {
        const TIPRecommendedImageTypeOptions recoOptions = TIPRecommendedImageTypeOptionsFromEncodingOptions(options, quality);
        type = [self tip_recommendedImageType:recoOptions];
    }

    TIPAssert(type != nil);
    NSString *typeString = TIPImageTypeToUTType(type);
    if (!typeString || !TIPImageTypeCanWriteWithImageIO(type)){
        theError = [NSError errorWithDomain:TIPErrorDomain code:TIPErrorCodeEncodingUnsupported userInfo:@{ @"imageType" : type }];
        return NO;
    }

    // Write
    const NSUInteger imageCount = [image tip_imageCountBasedOnImageType:type];
    CGImageDestinationRef destinationRef = desinationCreationBlock(typeString, imageCount);
    TIPDeferRelease(destinationRef);
    if (destinationRef) {
        const BOOL success = [image tip_writeToCGImageDestination:destinationRef
                                                             type:type
                                                  encodingOptions:options
                                                          quality:quality
                                               animationLoopCount:animationLoopCount
                                          animationFrameDurations:animationFrameDurations
                                                            error:&theError];

        if (!success) {
            TIPAssert(theError != nil);
            return NO;
        }
    } else {
        theError = [NSError errorWithDomain:TIPErrorDomain code:TIPErrorCodeFailedToInitializeImageDestination userInfo:nil];
        return NO;
    }

    return YES;
}

- (NSData *)tip_writeToDataWithType:(NSString *)type
                    encodingOptions:(TIPImageEncodingOptions)options
                            quality:(float)quality
                 animationLoopCount:(NSUInteger)animationLoopCount
            animationFrameDurations:(NSArray<NSNumber *> *)animationFrameDurations
                              error:(out NSError **)error
{
    __block NSError *theError = nil;
    tip_defer(^{
        if (error) {
            *error = theError;
        }
    });

    NSMutableData *mData = [[NSMutableData alloc] init];
    CGImageDestinationRef (^destinationBlock)(NSString *, const NSUInteger) = ^CGImageDestinationRef(NSString *UTType, const NSUInteger imageCount) {
        return CGImageDestinationCreateWithData((__bridge CFMutableDataRef)mData, (__bridge CFStringRef)UTType, imageCount, NULL);
    };
    const BOOL success = [self tip_writeToCGImageDestinationWithBlock:destinationBlock
                                                                 type:type
                                                      encodingOptions:options
                                                              quality:quality
                                                   animationLoopCount:animationLoopCount
                                              animationFrameDurations:animationFrameDurations
                                                                error:&theError];
    TIPAssert(!!success ^ !!theError);
    return success ? mData : nil;
}

- (BOOL)tip_writeToFile:(NSString *)filePath
                   type:(NSString *)type
        encodingOptions:(TIPImageEncodingOptions)options
                quality:(float)quality
     animationLoopCount:(NSUInteger)animationLoopCount
animationFrameDurations:(NSArray<NSNumber *> *)animationFrameDurations
             atomically:(BOOL)atomic
                  error:(out NSError **)error
{
    TIPAssert(filePath != nil);

    __block NSError *theError = nil;
    tip_defer(^{
        if (error) {
            *error = theError;
        }
    });

    if (!filePath) {
        theError = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:nil];
        return NO;
    }

    NSURL *finalFilePathURL = [NSURL fileURLWithPath:filePath isDirectory:NO];
    NSURL *writeFilePathURL = atomic ? [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString] isDirectory:NO] : finalFilePathURL;
    if (finalFilePathURL && writeFilePathURL) {
        // Ensure dirs
        [[NSFileManager defaultManager] createDirectoryAtURL:finalFilePathURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
        if (atomic) {
            [[NSFileManager defaultManager] createDirectoryAtURL:writeFilePathURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
        }
    }

    CGImageDestinationRef (^destinationBlock)(NSString *, const NSUInteger) = ^CGImageDestinationRef(NSString *UTType, const NSUInteger imageCount) {
        return CGImageDestinationCreateWithURL((__bridge CFURLRef)writeFilePathURL, (__bridge CFStringRef)UTType, imageCount, NULL);
    };
    const BOOL success = [self tip_writeToCGImageDestinationWithBlock:destinationBlock
                                                                 type:type
                                                      encodingOptions:options
                                                              quality:quality
                                                   animationLoopCount:animationLoopCount
                                              animationFrameDurations:animationFrameDurations
                                                                error:&theError];
    TIPAssert(!!success ^ !!theError);
    if (success) {
        if (atomic) {
            // Atomic move
            if (![[NSFileManager defaultManager] moveItemAtURL:writeFilePathURL toURL:finalFilePathURL error:&theError]) {
                TIPAssert(theError != nil);
                return NO;
            }
        }
    }

    return success;
}

#pragma mark Other Methods

- (void)tip_decode
{
    // Animated images cannot be "decoded".
    // Decoding an animated image (sourced from a GIF) appears to crash 100% on iOS 10.
    // Crashes on iOS 8 and 9 too, but very infrequently.
    // We'll avoid it altogether to be safe.
    if (self.images.count <= 0) {
        TIPExecuteCGContextBlock(^{
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0.0);
            [self drawAtPoint:CGPointZero];
            UIGraphicsEndImageContext();
        });
    }
}

@end

@implementation UIImage (TIPAdditions_CGImage)

- (BOOL)tip_writeToCGImageDestination:(CGImageDestinationRef)destinationRef
                                 type:(NSString *)type
                      encodingOptions:(TIPImageEncodingOptions)options
                              quality:(float)quality
                   animationLoopCount:(NSUInteger)animationLoopCount
              animationFrameDurations:(NSArray<NSNumber *> *)animationFrameDurations
                                error:(out NSError **)error
{
    __block NSError *theError = nil;
    tip_defer(^{
        if (error) {
            *error = theError;
        }
    });

    if (!type) {
        const TIPRecommendedImageTypeOptions recoOptions = TIPRecommendedImageTypeOptionsFromEncodingOptions(options, quality);
        type = [self tip_recommendedImageType:recoOptions];
    }

    const NSUInteger count = [self tip_imageCountBasedOnImageType:type];
    if (count > 1) {
        // Animated!

        // Prep to see if we have duration overrides in our meta data
        if (animationFrameDurations.count != count) {
            animationFrameDurations = nil;
        }

        NSDictionary *properties = TIPImageWritingProperties(self,
                                                             type,
                                                             options,
                                                             quality,
                                                             @(animationLoopCount),
                                                             nil,
                                                             YES);
        CGImageDestinationSetProperties(destinationRef, (__bridge CFDictionaryRef)properties);

        for (NSUInteger i = 0; i < count; i++) {
            UIImage *subimage = self.images[i];
            if (!subimage.CGImage) {
                theError = [NSError errorWithDomain:TIPErrorDomain code:TIPErrorCodeMissingCGImage userInfo:nil];
                break;
            }

            properties = TIPImageWritingProperties(self,
                                                   type,
                                                   options,
                                                   quality,
                                                   @(animationLoopCount),
                                                   animationFrameDurations ? animationFrameDurations[i] : nil,
                                                   NO);
            CGImageDestinationAddImage(destinationRef, subimage.CGImage, (__bridge CFDictionaryRef)properties);
        }
    } else {
        // Not animated

        const BOOL grayscale = TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageEncodingGrayscale);
        CGImageRef cgImage = self.CGImage ?: [self.images.firstObject CGImage];
        if (grayscale) {
            cgImage = TIPCGImageCreateGrayscale(cgImage);
        }

        if (cgImage) {
            NSDictionary *properties = TIPImageWritingProperties(self, type, options, quality, nil, nil, NO);
            CGImageDestinationAddImage(destinationRef, cgImage, (__bridge CFDictionaryRef)properties);
            if (grayscale) {
                CFRelease(cgImage);
            }
        } else {
            theError = [NSError errorWithDomain:TIPErrorDomain code:TIPErrorCodeMissingCGImage userInfo:nil];
        }
    }

    if (!theError && !CGImageDestinationFinalize(destinationRef)) {
        theError = [NSError errorWithDomain:TIPErrorDomain code:TIPErrorCodeFailedToFinalizeImageDestination userInfo:nil];
    }

    return !theError;
}

+ (UIImage *)tip_imageWithAnimatedImageSource:(CGImageSourceRef)source
                                    durations:(out NSArray<NSNumber *> **)durationsOut
                                    loopCount:(out NSUInteger *)loopCountOut
{
    UIImage *image = nil;
    NSTimeInterval duration = 0.0;
    size_t const count = CGImageSourceGetCount(source);
    if (count > 1 && loopCountOut) {
        CFDictionaryRef topLevelProperties = CGImageSourceCopyProperties(source, NULL);
        TIPDeferRelease(topLevelProperties);
        CFDictionaryRef topLevelGIFProperties = topLevelProperties ? CFDictionaryGetValue(topLevelProperties, kCGImagePropertyGIFDictionary) : NULL;
        NSNumber *loopCount = topLevelGIFProperties ? (NSNumber *)CFDictionaryGetValue(topLevelGIFProperties, kCGImagePropertyGIFLoopCount) : nil;
        *loopCountOut = (loopCount) ? loopCount.unsignedIntegerValue : 0;
    }

    const CGFloat scale = [UIScreen mainScreen].scale;
    NSMutableArray *durations = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray *images = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; i++) {
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
        TIPDeferRelease(properties);
        if (properties) {
            const CGImagePropertyOrientation cgOrientation = [[(__bridge NSDictionary *)properties objectForKey:(NSString *)kCGImagePropertyOrientation] unsignedIntValue];
            const UIImageOrientation orientation = TIPUIImageOrientationFromCGImageOrientation(cgOrientation);
            CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, i, NULL);
            TIPDeferRelease(imageRef);
            if (imageRef) {
                UIImage *frame = [UIImage imageWithCGImage:imageRef scale:scale orientation:orientation];
                if (frame) {
                    float additionalDuration = 0.0;

                    CFDictionaryRef gifProperties = CFDictionaryGetValue(properties, kCGImagePropertyGIFDictionary);
                    if (gifProperties) {
                        NSNumber *unclampedDelayTime = (NSNumber *)CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFUnclampedDelayTime);
                        if (unclampedDelayTime) {
                            additionalDuration = unclampedDelayTime.floatValue;
                        } else {
                            NSNumber *delayTime = (NSNumber *)CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFDelayTime);
                            if (delayTime) {
                                additionalDuration = delayTime.floatValue;
                            }
                        }
                    } else {
                        TIPLogWarning(@"No GIF dictionary in properties:%@", (__bridge NSDictionary *)properties);
                    }

                    if (additionalDuration < 0.01f + FLT_EPSILON) {
                        additionalDuration = 0.1f;
                    }
                    duration += additionalDuration;

                    [images addObject:frame];
                    [durations addObject:@(additionalDuration)];
                }
            }
        }
    }

    if (images.count > 0) {
        if (images.count == 1) {
            image = images.firstObject;
        } else {
            image = [UIImage animatedImageWithImages:images duration:duration];
        }
    }

    if (durationsOut) {
        *durationsOut = [durations copy];
    }

    return image;
}

@end

static NSDictionary *TIPImageWritingProperties(UIImage *image,
                                               NSString *type,
                                               TIPImageEncodingOptions options,
                                               float quality,
                                               NSNumber *animationLoopCount,
                                               NSNumber *animationDuration,
                                               BOOL isGlobalProperties)
{
    const BOOL preferProgressive = TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageEncodingProgressive);
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];

    // TODO: investigate if we should be using kCGImageDestinationOptimizeColorForSharing
    /*
     if (&kCGImageDestinationOptimizeColorForSharing != NULL) {
     properties[(NSString *)kCGImageDestinationOptimizeColorForSharing] = (__bridge id)kCFBooleanTrue;
     }
     */

    properties[(NSString *)kCGImagePropertyOrientation] = @(TIPCGImageOrientationFromUIImageOrientation(image.imageOrientation));

    if (TIPImageTypeSupportsLossyQuality(type)) {
        properties[(NSString *)kCGImageDestinationLossyCompressionQuality] = @(quality);
    }
    if (TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageEncodingNoAlpha)) {
        properties[(NSString *)kCGImagePropertyHasAlpha] = (__bridge id)kCFBooleanFalse;
    }
    if (TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageEncodingGrayscale)) {
        properties[(NSString *)kCGImagePropertyColorModel] = @"Gray";
    }

    if ([type isEqualToString:TIPImageTypeJPEG]) {
        NSDictionary *jfifInfo = @{
                                   (NSString *)kCGImagePropertyJFIFIsProgressive : (__bridge NSNumber *)((preferProgressive) ? kCFBooleanTrue : kCFBooleanFalse),
                                   (NSString *)kCGImagePropertyJFIFXDensity : @72,
                                   (NSString *)kCGImagePropertyJFIFYDensity : @72,
                                   (NSString *)kCGImagePropertyJFIFDensityUnit : @1,
                                   };
        properties[(NSString *)kCGImagePropertyJFIFDictionary] = jfifInfo;
    } else if ([type isEqualToString:TIPImageTypeJPEG2000]) {
        // TODO: add support for preferProgressive
    } else if ([type isEqualToString:TIPImageTypeTIFF]) {
        NSDictionary *tiffInfo = @{
                                   (NSString *)kCGImagePropertyTIFFCompression : @(/*NSTIFFCompressionLZW*/ 5)
                                   };
        properties[(NSString *)kCGImagePropertyTIFFDictionary] = tiffInfo;
    } else if ([type isEqualToString:TIPImageTypePNG]) {
        if (preferProgressive) {
            NSDictionary *pngInfo = @{
                                      (NSString *)kCGImagePropertyPNGInterlaceType : @1 // 1 == Adam7 interlaced encoding
                                      };
            properties[(NSString *)kCGImagePropertyPNGDictionary] = pngInfo;
        }
    } else if ([type isEqualToString:TIPImageTypeGIF]) {
        if (image.images.count > 1) {
            NSDictionary *gifInfo = nil;
            if (isGlobalProperties) {

                const NSUInteger loopCount = animationLoopCount.unsignedIntegerValue;

                // Exceedingly large values have been know to prevent looping from happening at all on browsers.
                // Restrict our loop count here to something that is more than long enough.
                const UInt16 loopCount16 = (UInt16)MIN(loopCount, (NSUInteger)INT16_MAX);

                gifInfo = @{ (NSString *)kCGImagePropertyGIFLoopCount : @(loopCount16) };

            } else {
                gifInfo = @{ (NSString *)kCGImagePropertyGIFDelayTime : animationDuration ?: @(image.duration / image.images.count) };
            }

            properties[(NSString *)kCGImagePropertyGIFDictionary] = gifInfo;
        }
    }

    return properties;
}

static CGImageRef TIPCGImageCreateGrayscale(CGImageRef imageRef)
{
    if (!imageRef) {
        return NULL;
    }

    CGColorSpaceRef originalColorSpace = CGImageGetColorSpace(imageRef);
    const CGColorSpaceModel model = CGColorSpaceGetModel(originalColorSpace);
    if (model == kCGColorSpaceModelMonochrome) {
        CFRetain(imageRef);
        return imageRef;
    } else if (model == kCGColorSpaceModelRGB || model == kCGColorSpaceModelCMYK) {
        if (1 == CGColorSpaceGetNumberOfComponents(originalColorSpace)) {
            // one component == grayscale
            CFRetain(imageRef);
            return imageRef;
        }
    }

    // Create image rectangle with current image width/height
    CGRect imageRect = CGRectMake(0, 0, CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));

    // Grayscale color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    TIPDeferRelease(colorSpace);

    // Create bitmap content with current image size and grayscale colorspace
    CGContextRef context = CGBitmapContextCreate(nil, (size_t)imageRect.size.width, (size_t)imageRect.size.height, 8, 0, colorSpace, kCGImageAlphaNone);
    TIPDeferRelease(context);

    // Draw image into current context, with specified rectangle
    // using previously defined context (with grayscale colorspace)
    CGContextDrawImage(context, imageRect, imageRef);

    // Create bitmap image info from pixel data in current context
    return CGBitmapContextCreateImage(context);
}
