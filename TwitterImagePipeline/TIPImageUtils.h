//
//  TIPImageUtils.h
//  TwitterImagePipeline
//
//  Created on 2/18/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import <ImageIO/CGImageProperties.h>
#import <ImageIO/CGImageSource.h>
#import <TwitterImagePipeline/TIPImageTypes.h>
#import <UIKit/UIImage.h>
#import <UIKit/UIScreen.h>
#import <UIKit/UIView.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark Render Support

//! protocol for the format of how to render.  Provided to the _renderFormat_ block of `TIPRenderImage` and supports read and write.
@protocol TIPRenderImageFormat <NSObject>
@property (nonatomic) BOOL opaque;
@property (nonatomic) BOOL prefersExtendedRange;
@property (nonatomic) CGFloat scale;
@property (nonatomic) CGSize renderSize;
@end

//! Block to configure a render format
typedef void(^TIPImageRenderFormattingBlock)(id<TIPRenderImageFormat> format);
//! Block to perform rendering.  _sourceImage_ if there was an image sourcing the render.
typedef void(^TIPImageRenderBlock)(UIImage * __nullable sourceImage, CGContextRef ctx);

#pragma mark Constants

/**
 When lossily encoding an image with Apple's ImageIO framework (which includes
 `UIImageJPEGRepresentation`), Apple uses a different metric for quality than the values commonly
 associated with JPEG images (the JFIF quality property).
 Since these differ and are complicated to dynamically compute, TIP provides some common static
 quality values for encoding an image with ImageIO that will align with JFIF qualities.
 */

//! JFIF 100% quality (with 4:2:0 chroma subsampling, 1.0f would yield an unsampled image)
static const float kTIPAppleQualityValueRepresentingJFIFQuality100  = 0.999f;
//! JFIF 95% quality
static const float kTIPAppleQualityValueRepresentingJFIFQuality95   = 0.830f;
//! JFIF 85% quality -- recommended
static const float kTIPAppleQualityValueRepresentingJFIFQuality85   = 0.575f;
//! JFIF 75% quality
static const float kTIPAppleQualityValueRepresentingJFIFQuality75   = 0.465f;
//! JFIF 65% quality
static const float kTIPAppleQualityValueRepresentingJFIFQuality65   = 0.400f;

#pragma mark Functions

//! Convert size (in points) to dimensions (in pixels)
NS_INLINE CGSize TIPDimensionsFromSizeScaled(CGSize size, CGFloat scale)
{
    if (scale <= 0.0) {
        scale = [UIScreen mainScreen].scale;
    }

    size.width *= scale;
    size.height *= scale;
    return size;
}

//! Convert dimensions (in pixels) to size (in points)
NS_INLINE CGSize TIPDimensionsToSizeScaled(CGSize dimensions, CGFloat scale)
{
    if (scale <= 0.0) {
        scale = [UIScreen mainScreen].scale;
    }

    dimensions.width /= scale;
    dimensions.height /= scale;
    return dimensions;
}

//! Get dimensions (in pixels) from `UIView`
NS_INLINE CGSize TIPDimensionsFromView(UIView * __nullable view)
{
    if (!view) {
        return CGSizeZero;
    }

    return TIPDimensionsFromSizeScaled(view.bounds.size, [UIScreen mainScreen].scale);
}

//! Get dimensions (in pixels) from `UIImage`
NS_INLINE CGSize TIPDimensionsFromImage(UIImage * __nullable image)
{
    if (!image) {
        return CGSizeZero;
    }

    return TIPDimensionsFromSizeScaled(image.size, image.scale);
}

//! Get size (in points based on screen scale) from dimensions (in pixels)
NS_INLINE CGSize TIPDimensionsToPointSize(CGSize dimensions)
{
    return TIPDimensionsToSizeScaled(dimensions, 0);
}

//! Get dimensions (in pixels) from size (in points based on screen scale)
NS_INLINE CGSize TIPDimensionsFromPointSize(CGSize size)
{
    return TIPDimensionsFromSizeScaled(size, 0);
}

//! Get a new size from an existing one by adjusting the scale
NS_INLINE CGSize TIPSizeByAdjustingScale(CGSize size, CGFloat oldScale, CGFloat newScale)
{
    if (oldScale == 0.0f) {
        oldScale = [UIScreen mainScreen].scale;
    }
    if (newScale == 0.0f) {
        newScale = [UIScreen mainScreen].scale;
    }

    if (oldScale == newScale) {
        return size;
    }

    size.width *= oldScale;
    size.height *= oldScale;
    size.width /= newScale;
    size.height /= newScale;

    return size;
}

//! Get a new size from an existing one by adjusting the scale
NS_INLINE CGPoint TIPPointByAdjustingScale(CGPoint point, CGFloat oldScale, CGFloat newScale)
{
    if (oldScale == 0.0f) {
        oldScale = [UIScreen mainScreen].scale;
    }
    if (newScale == 0.0f) {
        newScale = [UIScreen mainScreen].scale;
    }

    if (oldScale == newScale) {
        return point;
    }

    point.x *= oldScale;
    point.y *= oldScale;
    point.x /= newScale;
    point.y /= newScale;

    return point;
}

//! Get a new rect from an existing one by adjusting the scale
NS_INLINE CGRect TIPRectByAdjustingScale(CGRect rect, CGFloat oldScale, CGFloat newScale)
{
    rect.size = TIPSizeByAdjustingScale(rect.size, oldScale, newScale);
    rect.origin = TIPPointByAdjustingScale(rect.origin, oldScale, newScale);
    return rect;
}

//! Does the `UIViewContentMode` scale?
NS_INLINE BOOL TIPContentModeDoesScale(UIViewContentMode contentMode)
{
    switch (contentMode)
    {
        case UIViewContentModeScaleToFill:
        case UIViewContentModeScaleAspectFit:
        case UIViewContentModeScaleAspectFill:
            return YES;
        default:
            return NO;
    }
}

//! Estimate byte size of a decoded `UIImage` with the given settings
FOUNDATION_EXTERN NSUInteger TIPEstimateMemorySizeOfImageWithSettings(CGSize size,
                                                                      CGFloat scale,
                                                                      NSUInteger componentsPerPixel,
                                                                      NSUInteger frameCount);

/**
 Compare size with target sizing info
 Computed target dimensions will be pixel aligned
 (i.e. any fractional pixels will be rounded up, e.g. { 625.75, 724.001 } ==> { 626, 725 })
 @note only _targetContentMode_ values that have `UIViewContentModeScale*` will be scaled (others are just positional and do not scale)
 */
FOUNDATION_EXTERN BOOL TIPSizeMatchesTargetSizing(CGSize size,
                                                  CGSize targetSize,
                                                  UIViewContentMode targetContentMode,
                                                  CGFloat scale);

//! Best effort alpha check on a `CGImageRef`
FOUNDATION_EXTERN BOOL TIPCGImageHasAlpha(CGImageRef imageRef, BOOL inspectPixels);
//! Best effort alpha check on a `CIImage`
FOUNDATION_EXTERN BOOL TIPCIImageHasAlpha(CIImage *image, BOOL inspectPixels);

//! Does the given screen support wide gamut color (aka P3)?
FOUNDATION_EXTERN BOOL TIPScreenSupportsWideColorGamut(UIScreen *screen);
//! Does the main screen support wide gamut color (aka P3)?
FOUNDATION_EXTERN BOOL TIPMainScreenSupportsWideColorGamut(void) __attribute__((const));

/**
 Scale a size to target sizing info
 @note only _targetContentMode_ values that have `UIViewContentModeScale*` will be scaled (others are just positional and do not scale)
 */
FOUNDATION_EXTERN CGSize TIPSizeScaledToTargetSizing(CGSize sizeToScale,
                                                     CGSize targetSizeOrZero,
                                                     UIViewContentMode targetContentMode,
                                                     CGFloat scale);
/**
 Scale dimensions to target sizing info
 @note only _targetContentMode_ values that have `UIViewContentModeScale*` will be scaled (others are just positional and do not scale)
 */
FOUNDATION_EXTERN CGSize TIPDimensionsScaledToTargetSizing(CGSize dimensionsToScale,
                                                           CGSize targetDimensionsOrZero,
                                                           UIViewContentMode targetContentMode);
//! Convert from `UIImageOrientation` to CGImage orientation
FOUNDATION_EXTERN CGImagePropertyOrientation TIPCGImageOrientationFromUIImageOrientation(UIImageOrientation orientation) __attribute__((const));
//! Convert from CGImage orientation to `UIImageOrientation`
FOUNDATION_EXTERN UIImageOrientation TIPUIImageOrientationFromCGImageOrientation(CGImagePropertyOrientation cgOrientation) __attribute__((const));

/**
 Execute CGContext (or heavy memory cost) code.
 When `[TIPGlobalConfiguration serializeCGContextAccess]` is `YES`, this function will serialize
 execution across threads.
 */
FOUNDATION_EXTERN void TIPExecuteCGContextBlock(dispatch_block_t __attribute__((noescape)) block);

/**
 Render to a `UIImage` (using the `TIPExecuteCGContextBlock` call under the hood)
 @param sourceImage the image to source the render off of, can provide `nil` to source off device defaults
 @param formatBlock the block to configure the formatting of the render
 @param renderBlock the block to perform the rendering
 @return the rendered `UIImage` or `nil`
 @note a _sourceImage_ that is an animation will yield `nil`
 */
FOUNDATION_EXTERN UIImage * __nullable TIPRenderImage(UIImage * __nullable sourceImage,
                                                      TIPImageRenderFormattingBlock __nullable __attribute__((noescape)) formatBlock,
                                                      TIPImageRenderBlock __attribute__((noescape)) renderBlock);

NS_ASSUME_NONNULL_END
