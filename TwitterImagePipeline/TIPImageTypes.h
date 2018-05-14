//
//  TIPImageTypes.h
//  TwitterImagePipeline
//
//  Created on 8/1/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Image Types

#pragma mark Read & Write image types

/**
 JPEG (Joint Photographic Experts Group)
 JPEG has a way of being encoded progressively.
 Progressive encoding/decoding _is_ supported by _TIP_ by default.
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeJPEG;
/**
 JPEG-2000 (Joint Photographic Experts Group circa 2000)
 JPEG-2000 has a way of being encoded progressively (numerous ways actually).
 Progressive encoding/decoding _is not_ supported by __TIP__ by default,
 a custom `TIPImageCodec` would be required to add progressive support.
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeJPEG2000;
/**
 PNG (Portable Network Graphic)
 Animation encoding/decoding _is_ supported by _TIP_ by default (on iOS 8+).
 PNG has a way of being encoded progressively (interlaced/Adam7).
 Progressive decoding _is not_ supported by __TIP__ by default,
 a custom `TIPImageCodec` would be required to add progressive decoding support.
 Progressive encoding _is_ supported by __TIP__ by default.
 @note FWIW: progressively encoded PNG images are significantly larger than normal PNGs
 and using progressive encoding of PNG is not recommended.
 */
FOUNDATION_EXTERN NSString * const TIPImageTypePNG;
/**
 GIF (Graphics Interchange Format)
 GIF supports encoding as an animation.
 Animation encoding/decoding _is_ supported by _TIP_ by default.
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeGIF;
/**
 TIFF (Tagged Image File Format)
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeTIFF;
/**
 BMP (Windows Bitmap)
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeBMP;
/**
 TARGA or TGA (Truevision Advanced Raster Graphics Adapter)
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeTARGA;

#pragma mark Read-only image types

/**
 ICO (Windows icon data)
 Only decoding is supported by __TIP__ by default.
 @warning must be 16x16, 32x32, 48x48, 128x128, and/or 256x256
 @note image format can contain multiple resolutions
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeICO;
/**
 RAW (Raw image data)
 Only decoding is supported by __TIP__ by default.
 @note requires iOS 8+
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeRAW;
/**
 ICNS (Apple icon image)
 Only decoding is supported by __TIP__ by default.
 @note image format can contain multiple resolutions
 @note requires iOS 11+
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeICNS;

#pragma mark Unsupported image types (cannot read nor write)

/**
 PICT (QuickDraw image)
 Not supported by __TIP__ by default,
 a custom `TIPImageCodec` would be required to add support.
 */
FOUNDATION_EXTERN NSString * const TIPImageTypePICT;
/**
 QTIF (QuickTime Image Format)
 Not supported by __TIP__ by default,
 a custom `TIPImageCodec` would be required to add support.
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeQTIF;

#pragma mark - TIPImageEncodingOptions

/**
 Options for encoding an image
 */
typedef NS_OPTIONS(NSInteger, TIPImageEncodingOptions)
{
    /** no options */
    TIPImageEncodingNoOptions = 0,
    /** Encoded as progressive (if supported) */
    TIPImageEncodingProgressive = 1 << 0,
    /** Force no-alpha, even if the image has alpha */
    TIPImageEncodingNoAlpha = 1 << 1,
    /** Encode as grayscale (does not work with animated images) */
    TIPImageEncodingGrayscale = 1 << 2,
};

#pragma mark - TIPRecommendedImageTypeOptions

/**
 Options for selecting a recommended image type from a given `UIImage`.
 See `[UIImage tip_recommendedImageType:]`
 */
typedef NS_OPTIONS(NSInteger, TIPRecommendedImageTypeOptions) {
    /** no options */
    TIPRecommendedImageTypeNoOptions = 0,
    /** assume alpha (takes precedence over `AssumeNoAlpha`) */
    TIPRecommendedImageTypeAssumeAlpha = 1 << 0,
    /** assume no alpha (`AssumeAlpha` has precedence) */
    TIPRecommendedImageTypeAssumeNoAlpha = 1 << 1,
    /** permit lossy */
    TIPRecommendedImageTypePermitLossy = 1 << 2,
    /** prefer progressive */
    TIPRecommendedImageTypePreferProgressive = 1 << 3
};

#pragma mark - Functions

#pragma mark Type Checking

/** Determine if the provided image type can be read/decoded into a `UIImage` by _TIP_ */
FOUNDATION_EXPORT BOOL TIPImageTypeCanReadWithImageIO(NSString * __nullable type);
/** Determine if the provided image type can be writtend/encoded from a `UIImage` by _TIP_ */
FOUNDATION_EXPORT BOOL TIPImageTypeCanWriteWithImageIO(NSString * __nullable type);

#pragma mark TIP type vs Uniform Type Identifier (UTI) conversion

/**
 Convert a UTI to a TIP image type.
 See `MobileCoreServices/UTCoreTypes.h`
 */
FOUNDATION_EXTERN NSString * __nullable TIPImageTypeFromUTType(NSString * __nullable utType);
/**
 Convert a TIP image type to a UTI.
 See `MobileCoreServices/UTCoreTypes.h`
 */
FOUNDATION_EXTERN NSString * __nullable TIPImageTypeToUTType(NSString * __nullable type);

#pragma mark Debug/Inspection Utilities

/**
 Detect the image type from raw encoded data.
 @param data The `NSData`
 @param optionsOut The `TIPImageEncodingOptions` to detect (`NULL` if detection isn't desired)
 @param animationFrameCountOut The number of animations frames (`NULL` if detection isn't desired)
 @param hasCompleteImageData provide `YES` if _data_ is the entire encoded image,
 `NO` if the data is partial progress
 @return The image type detected or `nil` if no type could be detected
 */
FOUNDATION_EXTERN NSString * __nullable TIPDetectImageType(NSData *data,
                                                           TIPImageEncodingOptions * __nullable optionsOut,
                                                           NSUInteger * __nullable animationFrameCountOut,
                                                           BOOL hasCompleteImageData);
/**
 Detect the image type from raw encoded data via magic numbers.
 @param data The `NSData`
 @return the detected image type or `nil` if no type could be detected
 */
FOUNDATION_EXTERN NSString * __nullable TIPDetectImageTypeViaMagicNumbers(NSData *data);
/**
 Detect the number of progressive scans in the provided `NSData`.
 Currently only supports progressive JPEG.
 */
FOUNDATION_EXTERN NSUInteger TIPImageDetectProgressiveScanCount(NSData *data);
/**
 Hydrate some recommended image type options
 */
FOUNDATION_EXTERN TIPRecommendedImageTypeOptions TIPRecommendedImageTypeOptionsFromEncodingOptions(TIPImageEncodingOptions encodingOptions, float quality) __attribute__((const));

NS_ASSUME_NONNULL_END
