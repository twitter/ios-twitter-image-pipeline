//
//  TIPImageTypes.m
//  TwitterImagePipeline
//
//  Created on 8/1/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import "TIP_Project.h"
#import "TIPImageCodecCatalogue.h"
#import "TIPImageTypes.h"

NS_ASSUME_NONNULL_BEGIN

static const UInt8 kBMP1MagicNumbers[]      = { 0x42, 0x4D };
static const UInt8 kJPEGMagicNumbers[]      = { 0xFF, 0xD8, 0xFF };
static const UInt8 kGIFMagicNumbers[]       = { 0x47, 0x49, 0x46 };
static const UInt8 kPNGMagicNumbers[]       = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };

#define MAGIC_NUMBERS_ARE_EQUAL(bytes, magicNumber) \
(memcmp(bytes, magicNumber, sizeof( magicNumber )) == 0)

#define TIPWorkAroundCoreGraphicsUTTypeLoadBug() \
do { \
    /**                                                                                            \
        Annoying bug in Apple's CoreGraphics will FAIL to load certain image formats (like RAW)    \
        until the identifiers list has been hydrated.                                              \
        Call `TIPReadableImageTypes` to force that hydration.                                      \
        Doesn't seem to affect iOS 8, but definitely affects iOS 9.                                \
    */ \
    (void)TIPReadableImageTypes(); \
} while (0)

#pragma mark - Image Types

NSString * const TIPImageTypeJPEG       = @"public.jpeg";
NSString * const TIPImageTypeJPEG2000   = @"public.jpeg-2000";
NSString * const TIPImageTypePNG        = @"public.png";
NSString * const TIPImageTypeGIF        = @"com.compuserve.gif";
NSString * const TIPImageTypeTIFF       = @"public.tiff";
NSString * const TIPImageTypeBMP        = @"com.microsoft.bmp";
NSString * const TIPImageTypeTARGA      = @"com.truevision.tga-image";
NSString * const TIPImageTypePICT       = @"com.apple.pict";
NSString * const TIPImageTypeQTIF       = @"com.apple.quicktime-image";
NSString * const TIPImageTypeICNS       = @"com.apple.icns";
NSString * const TIPImageTypeICO        = @"com.microsoft.ico";
NSString * const TIPImageTypeRAW        = @"public.camera-raw-image";

#pragma mark - Static Functions

static NSSet<NSString *> *TIPReadableImageTypes()
{
    static NSSet<NSString *> *sReadableImageTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFArrayRef typeIds = CGImageSourceCopyTypeIdentifiers();
        sReadableImageTypes = [NSSet setWithArray:(__bridge NSArray *)typeIds];
        CFRelease(typeIds);
    });
    return sReadableImageTypes;
}

static NSSet<NSString *> *TIPWriteableImageTypes()
{
    static NSSet<NSString *> *sWriteableImageTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFArrayRef typeIds = CGImageDestinationCopyTypeIdentifiers();
        NSMutableSet<NSString *> *set = [NSMutableSet setWithArray:(__bridge NSArray *)typeIds];

        // forcibly remove formats that are too restrictive for write support
        [set removeObject:TIPImageTypeICO];
        [set removeObject:TIPImageTypeICNS];

        sWriteableImageTypes = [set copy];
        CFRelease(typeIds);
    });
    return sWriteableImageTypes;
}

#pragma mark - Functions

NSString * __nullable TIPDetectImageTypeViaMagicNumbers(NSData *dataObj)
{
    CFDataRef data = (__bridge CFDataRef)dataObj;
    const CFIndex length = (data) ? CFDataGetLength(data) : 0;
    const UInt8 *bytes = (data) ? CFDataGetBytePtr(data) : NULL;

    if (length >= 2) {
        if (MAGIC_NUMBERS_ARE_EQUAL(bytes, kBMP1MagicNumbers)) {
            // kUTTypeBMP;
            return TIPImageTypeBMP;
        } else if (length >= 3) {
            if (MAGIC_NUMBERS_ARE_EQUAL(bytes, kJPEGMagicNumbers)) {
                // kUTTypeJPEG;
                return TIPImageTypeJPEG;
            } else if (MAGIC_NUMBERS_ARE_EQUAL(bytes, kGIFMagicNumbers)) {
                // kUTTypeGIF;
                return TIPImageTypeGIF;
            } else if (length >= 8) {
                if (MAGIC_NUMBERS_ARE_EQUAL(bytes, kPNGMagicNumbers)) {
                    // kUTTypePNG;
                    return TIPImageTypePNG;
                }
            }
        }
    }

    return nil;
}

static BOOL TIPImageTypeHasProgressiveVariant(NSString * __nullable type)
{
    const BOOL hasProgressiveVariant = [type isEqualToString:TIPImageTypeJPEG]
                                    || [type isEqualToString:TIPImageTypeJPEG2000]
                                    || [type isEqualToString:TIPImageTypePNG];
    return hasProgressiveVariant;
}

BOOL TIPImageTypeSupportsLossyQuality(NSString * __nullable type)
{
    const BOOL hasLossy =  [type isEqualToString:TIPImageTypeJPEG]
                        || [type isEqualToString:TIPImageTypeJPEG2000];

    // though GIF can be munged many ways to change the quality,
    // we'll keep it simple and not treat GIF as supporting lossy quality

    return hasLossy;
}

NSString * __nullable TIPImageTypeToUTType(NSString * __nullable type)
{
    TIPWorkAroundCoreGraphicsUTTypeLoadBug();

    if (UTTypeConformsTo((__bridge CFStringRef)type, kUTTypeImage)) {
        return type;
    }
    return nil;
}

NSString * __nullable TIPImageTypeFromUTType(NSString * __nullable utType)
{
    CFStringRef imageType = (__bridge CFStringRef)utType;

    // We check RAW first since RAW camera images can be detected as both RAW and TIFF and we'll bias to RAW

    BOOL isTypeRawImage;
#if __IPHONE_8_0 <= __IPHONE_OS_VERSION_MIN_REQUIRED
    isTypeRawImage = (BOOL)UTTypeConformsTo(imageType, kUTTypeRawImage);
#else
    isTypeRawImage = &kUTTypeRawImage && UTTypeConformsTo(imageType, kUTTypeRawImage);
#endif
    isTypeRawImage = isTypeRawImage || [utType isEqualToString:TIPImageTypeRAW];

    if (isTypeRawImage) {
        return TIPImageTypeRAW;
    } else if (UTTypeConformsTo(imageType, kUTTypeJPEG)) {
        return TIPImageTypeJPEG;
    } else if (UTTypeConformsTo(imageType, kUTTypePNG)) {
        return TIPImageTypePNG;
    } else if (UTTypeConformsTo(imageType, kUTTypeJPEG2000)) {
        return TIPImageTypeJPEG2000;
    } else if (UTTypeConformsTo(imageType, kUTTypeGIF)) {
        return TIPImageTypeGIF;
    } else if (UTTypeConformsTo(imageType, kUTTypeTIFF)) {
        return TIPImageTypeTIFF;
    } else if (UTTypeConformsTo(imageType, kUTTypeBMP)) {
        return TIPImageTypeBMP;
    } else if (UTTypeConformsTo(imageType, CFSTR("com.truevision.tga-image"))) {
        return TIPImageTypeTARGA;
    } else if (UTTypeConformsTo(imageType, kUTTypePICT)) {
        return TIPImageTypePICT;
    } else if (UTTypeConformsTo(imageType, kUTTypeICO)) {
        return TIPImageTypeICO;
    } else if (UTTypeConformsTo(imageType, kUTTypeAppleICNS)) {
        return TIPImageTypeICNS;
    } else if (UTTypeConformsTo(imageType, kUTTypeQuickTimeImage)) {
        return TIPImageTypeQTIF;
    }

    return nil;
}

BOOL TIPImageTypeCanReadWithImageIO(NSString * __nullable imageType)
{
    return (imageType) ? [TIPReadableImageTypes() containsObject:imageType] : NO;
}

BOOL TIPImageTypeCanWriteWithImageIO(NSString * __nullable imageType)
{
    return (imageType) ? [TIPWriteableImageTypes() containsObject:imageType] : NO;
}

TIPRecommendedImageTypeOptions TIPRecommendedImageTypeOptionsFromEncodingOptions(TIPImageEncodingOptions encodingOptions, float quality)
{
    TIPRecommendedImageTypeOptions options = 0;
    if (quality < 1.f) {
        options |= TIPRecommendedImageTypePermitLossy;
    }
    if (TIP_BITMASK_HAS_SUBSET_FLAGS(encodingOptions, TIPImageEncodingProgressive)) {
        options |= TIPRecommendedImageTypePreferProgressive;
    }
    if (TIP_BITMASK_HAS_SUBSET_FLAGS(encodingOptions, TIPImageEncodingNoAlpha)) {
        options |= TIPRecommendedImageTypeAssumeNoAlpha;
    }
    return options;
}


#pragma mark Debug Stuff

NSString * __nullable TIPDetectImageType(NSData *data,
                                         TIPImageEncodingOptions * __nullable optionsOut,
                                         NSUInteger * __nullable animationFrameCountOut,
                                         BOOL hasCompleteImageData)
{
    NSString *type = nil;

    TIPWorkAroundCoreGraphicsUTTypeLoadBug();

    TIPImageEncodingOptions optionsRead = TIPImageEncodingNoOptions;
    NSUInteger animationFrameCount = 1;
    NSDictionary *options = @{ (NSString *)kCGImageSourceShouldCache : @NO };
    CGImageSourceRef imageSourceRef = CGImageSourceCreateIncremental((__bridge CFDictionaryRef)options);
    TIPDeferRelease(imageSourceRef);
    if (imageSourceRef != NULL && data != nil) {
        CGImageSourceUpdateData(imageSourceRef, (__bridge CFDataRef)data, hasCompleteImageData);

        // Read type
        CFStringRef imageTypeStringRef = CGImageSourceGetType(imageSourceRef);
        if (imageTypeStringRef != NULL) {
            type = TIPImageTypeFromUTType((__bridge NSString *)imageTypeStringRef);
        }

#if DEBUG && TEST_CODE
        // Test image construction
        for (NSUInteger i = 0; i < CGImageSourceGetCount(imageSourceRef); i++) {
            CGImageRef dbgImageRef = CGImageSourceCreateImageAtIndex(imageSourceRef, i, NULL);
            TIPDeferRelease(dbgImageRef);
            UIImage *dbgImage = [UIImage imageWithCGImage:dbgImageRef];
            if (!CGSizeEqualToSize(CGSizeZero, dbgImage.size)) {
                dbgImage = nil;
            }
        }
#endif

        if (optionsOut) {
            // Options are desired, check for progressive

            if (TIPImageTypeHasProgressiveVariant(type)) {
                CFDictionaryRef imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSourceRef, 0, NULL);
                TIPDeferRelease(imageProperties);
                if (imageProperties != NULL) {

                    BOOL progressive = NO;
                    if ([type isEqualToString:TIPImageTypeJPEG]) {
                        CFDictionaryRef jfifProperties = CFDictionaryGetValue(imageProperties, kCGImagePropertyJFIFDictionary);
                        if (jfifProperties) {
                            CFBooleanRef isProgressiveBool = CFDictionaryGetValue(jfifProperties, kCGImagePropertyJFIFIsProgressive) ?: kCFBooleanFalse;
                            progressive = !!CFBooleanGetValue(isProgressiveBool);
                        }
                    } else if ([type isEqualToString:TIPImageTypePNG]) {
                        CFDictionaryRef pngProperties = CFDictionaryGetValue(imageProperties, kCGImagePropertyPNGDictionary);
                        if (pngProperties) {
                            CFTypeRef interlaceType = CFDictionaryGetValue(pngProperties, kCGImagePropertyPNGInterlaceType) ?: NULL;
                            NSNumber *interlaceTypeNumber = (__bridge NSNumber *)interlaceType;
                            if ([interlaceTypeNumber unsignedIntegerValue] == 1 /* Adam7 Interlaced Encoding */) {
                                progressive = YES;
                            }
                        }
                    }

                    if (progressive) {
                        optionsRead |= TIPImageEncodingProgressive;
                    }
                }
            }
        }

        if (animationFrameCountOut) {
            // Read image count (if potentially animated)
            if ([[TIPImageCodecCatalogue sharedInstance] codecWithImageTypeSupportsAnimation:type]) {
                animationFrameCount = (NSUInteger)MAX((size_t)1, CGImageSourceGetCount(imageSourceRef));
            }
        }

    }

    if (!type) {
        // Couldn't detect, try magic numbers
        type = TIPDetectImageTypeViaMagicNumbers(data);
    }

    if (optionsOut) {
        *optionsOut = optionsRead;
    }
    if (animationFrameCountOut) {
        *animationFrameCountOut = animationFrameCount;
    }

    return type;
}

NSUInteger TIPImageDetectProgressiveScanCount(NSData *data)
{
    NSUInteger byteIndex = 0;
    NSUInteger length = data.length;
    const UInt8 *bytes = (const UInt8 *)data.bytes;

    if (length <= 10) {
        return 0;
    }

    if (!MAGIC_NUMBERS_ARE_EQUAL(bytes, kJPEGMagicNumbers)) {
        return 0;
    }

    byteIndex += sizeof(kJPEGMagicNumbers);

    for (; byteIndex < length; byteIndex++) {
        if (bytes[byteIndex] == 0xFF) {
            byteIndex++;
            if (bytes[byteIndex] == 0xC0) {
                return 0; // not progressive
            } else if (bytes[byteIndex] == 0xC2) {
                byteIndex++;
                break;
            }
        }
    }

    NSUInteger count = 0;
    for (; byteIndex < length; byteIndex++) {
        if (bytes[byteIndex] == 0xFF) {
            byteIndex++;
            if (bytes[byteIndex] == 0xDA) {
                // start of new scan
                count++;
            }
        }
    }
    return count;
}

NS_ASSUME_NONNULL_END
