//
//  TIPImageTypes.h
//  TwitterImagePipeline
//
//  Created on 8/1/16.
//  Copyright © 2020 Twitter. All rights reserved.
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
 @warning Apple has announced JPEG2000 support is deprecated as of iOS 13 & macOS 10.15... use at your own risk.
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeJPEG2000;
/**
 PNG (Portable Network Graphic)
 Animation encoding/decoding _is_ supported by _TIP_ by default.
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
/**
 HEIC (High Efficiency Image File w/ HEVC compressed image)
 HEIC is a specific variant of HEIF
 @note Supported on devices with iOS 11+ and Simulators with iOS 12+.
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeHEIC;

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
 @note tvOS support not enabled for now
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeRAW;
/**
 ICNS (Apple icon image)
 Only decoding is supported by __TIP__ by default.
 @note image format can contain multiple resolutions
 @note requires iOS 11+
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeICNS;
/**
 AVCI (High Efficiency Image File w/ H.264 compressed image)
 AVCI is a specific variant of HEIF
 @note Supported on devices with iOS 11+ and Simulator with iOS 12+.
 @warning this is untested currently due to difficulty in creating .avci files to test
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeAVCI;
/**
 WEBP (Google's WebM project image format, WebP)
 @note requires iOS 14+
 @note the `TIPXWebPCodec` encoder and decoder can be installed for backwards compatibility
 */
FOUNDATION_EXTERN NSString * const TIPImageTypeWEBP;

#pragma mark Unsupported image types (cannot read nor write)

/**
 PICT (QuickDraw image)
 Not supported by __TIP__ by default,
 a custom `TIPImageCodec` would be required to add support.
 @note PICT images _ARE_ supported on TARGET_OS_MACCATALYST
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
    /** Encoded as grayscale (does not work with animated images) */
    TIPImageEncodingGrayscale = 1 << 2,
    /** Encoded using indexed color palette (default encoders do not support writing indexed color palette images, must have a custome encoder that handles this option) */
    TIPImageEncodingIndexedColorPalette = 1 << 3,
};

/**
 Options for encoding an image with an indexed palette
 */
typedef NS_OPTIONS(NSInteger, TIPIndexedPaletteEncodingOptions)
{
    /** no options */
    TIPIndexedPaletteEncodingNoOptions = 0,

    /** 8-bit depth, 256 colors (default) */
    TIPIndexedPaletteEncodingBitDepth8 = (8-8) << 0,
    /** 7-bit depth, 128 colors */
    TIPIndexedPaletteEncodingBitDepth7 = (8-7) << 0,
    /** 6-bit depth, 64 colors */
    TIPIndexedPaletteEncodingBitDepth6 = (8-6) << 0,
    /** 5-bit depth, 32 colors */
    TIPIndexedPaletteEncodingBitDepth5 = (8-5) << 0,
    /** 4-bit depth, 16 colors */
    TIPIndexedPaletteEncodingBitDepth4 = (8-4) << 0,
    /** 3-bit depth, 8 colors */
    TIPIndexedPaletteEncodingBitDepth3 = (8-3) << 0,
    /** 2-bit depth, 4 colors */
    TIPIndexedPaletteEncodingBitDepth2 = (8-2) << 0,
    /** 1-bit depth, 2 colors */
    TIPIndexedPaletteEncodingBitDepth1 = (8-1) << 0,
    /** 0-bit depth, Invalid */
    TIPIndexedPaletteEncodingBitDepthInvalid = (8-0) << 0,

    /** Transparency can support any alpha, like PNG8 (default) */
    TIPIndexedPaletteEncodingTransparencyAnyAlpha = 0b00 << 8,
    /** Transparency is not supported */
    TIPIndexedPaletteEncodingTransparencyNoAlpha = 0b01 << 8,
    /** Transparency can support only full transparency, like GIF */
    TIPIndexedPaletteEncodingTransparencyFullAlphaOnly = 0b10 << 8,
    /** Invalid transparency option */
    TIPIndexedPaletteEncodingTransparencyInvalid = 0b11 << 8,
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

#pragma mark - Constants

//! Max length of a magic number for identifying an image type
FOUNDATION_EXTERN NSUInteger const TIPMagicNumbersForImageTypeMaximumLength;

#pragma mark - Functions

#pragma mark Type Checking

/** Determine if the provided image type can be read/decoded into a `UIImage` by _TIP_ */
FOUNDATION_EXTERN BOOL TIPImageTypeCanReadWithImageIO(NSString * __nullable type);
/** Determine if the provided image type can be writtend/encoded from a `UIImage` by _TIP_ */
FOUNDATION_EXTERN BOOL TIPImageTypeCanWriteWithImageIO(NSString * __nullable type);

#pragma mark TIP type vs Uniform Type Identifier (UTI) vs File Extension

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
/**
 Convert a UTI to a file extension.
 See `MobileCoreServices/UTCoreType.h`
 */
FOUNDATION_EXTERN NSString * __nullable TIPFileExtensionFromUTType(NSString * __nullable utType);
/**
 Convert a file extension to a UTI.
 See `MobileCoreServices/UTCoreType.h`
*/
FOUNDATION_EXTERN NSString * __nullable TIPFileExtensionToUTType(NSString * __nullable fileExtension, BOOL mustBeImageUTType);

#pragma mark Inspection Utilities

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
Detect the image type from raw encoded data.
@param filePath The file to detect
@param optionsOut The `TIPImageEncodingOptions` to detect (`NULL` if detection isn't desired)
@param animationFrameCountOut The number of animations frames (`NULL` if detection isn't desired)
@return The image type detected or `nil` if no type could be detected
*/
FOUNDATION_EXTERN NSString * __nullable TIPDetectImageTypeFromFile(NSURL *filePath,
                                                                   TIPImageEncodingOptions * __nullable optionsOut,
                                                                   NSUInteger * __nullable animationFrameCountOut);

/**
 Detect the image type from raw encoded data via magic numbers.
 @param data The `NSData`
 @return the detected image type or `nil` if no type could be detected
 */
FOUNDATION_EXTERN NSString * __nullable TIPDetectImageTypeViaMagicNumbers(NSData *data);

/**
 What types are detectable via magic numbers?
 @return the set of image types that can be detected via magic numbers.
 */
FOUNDATION_EXTERN NSSet<NSString *> * TIPDetectableImageTypesViaMagicNumbers(void);

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
