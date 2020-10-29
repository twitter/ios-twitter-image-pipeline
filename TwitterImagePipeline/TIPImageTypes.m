//
//  TIPImageTypes.m
//  TwitterImagePipeline
//
//  Created on 8/1/16.
//  Copyright © 2020 Twitter. All rights reserved.
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
static const UInt8 kPNGMagicNumbers[]       = { 0x89, 0x50, 0x4E, 0x47,
                                                0x0D, 0x0A, 0x1A, 0x0A };
static const UInt8 kWEBPMagicNumbers[]      = { 'R', 'I', 'F', 'F',
                                                '\0', '\0', '\0', '\0',
                                                'W', 'E', 'B', 'P' };

#define BIGGER(x, y) ((x) > (y) ? (x) : (y))

// statically assign the largest magic number at compile time
const NSUInteger TIPMagicNumbersForImageTypeMaximumLength =
(NSUInteger)BIGGER(sizeof(kPNGMagicNumbers),
                   BIGGER(sizeof(kGIFMagicNumbers),
                          BIGGER(sizeof(kJPEGMagicNumbers),
                                 BIGGER(sizeof(kBMP1MagicNumbers),
                                        sizeof(kWEBPMagicNumbers)))));

#define MAGIC_NUMBERS_ARE_EQUAL(bytes, len, magicNumber) \
( (len >= sizeof( magicNumber )) && (memcmp(bytes, magicNumber, sizeof( magicNumber )) == 0) )

#define TIPWorkAroundCoreGraphicsUTTypeLoadBug() \
do { \
    /**                                                                                            \
        Annoying bug in Apple's CoreGraphics will FAIL to load certain image formats (like RAW)    \
        until the identifiers list has been hydrated.                                              \
        Call `TIPReadableImageTypes` to force that hydration.                                      \
        Doesn't seem to affect iOS 8, but definitely affects iOS 9+.                               \
        NOTE: This will trigger XPC on first access via `CGImageSourceCopyTypeIdentifiers(...)`    \
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
NSString * const TIPImageTypeHEIC       = @"public.heic";
NSString * const TIPImageTypeAVCI       = @"public.avci";
NSString * const TIPImageTypeWEBP       = @"org.webmproject.webp";

#pragma mark - Static Functions

static NSSet<NSString *> *TIPReadableImageTypes()
{
    static NSSet<NSString *> *sReadableImageTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFArrayRef typeIds = CGImageSourceCopyTypeIdentifiers();
        TIPDeferRelease(typeIds);
        sReadableImageTypes = [NSSet setWithArray:(__bridge NSArray *)typeIds];
    });
    return sReadableImageTypes;
}

static NSSet<NSString *> *TIPWriteableImageTypes()
{
    static NSSet<NSString *> *sWriteableImageTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFArrayRef typeIds = CGImageDestinationCopyTypeIdentifiers();
        TIPDeferRelease(typeIds);
        NSMutableSet<NSString *> *set = [NSMutableSet setWithArray:(__bridge NSArray *)typeIds];

        // forcibly remove formats that are too restrictive for write support
        [set removeObject:TIPImageTypeICO];
        [set removeObject:TIPImageTypeICNS];

        sWriteableImageTypes = [set copy];
    });
    return sWriteableImageTypes;
}

#pragma mark - Functions

NSSet<NSString *> * TIPDetectableImageTypesViaMagicNumbers(void)
{
    static NSSet<NSString *> *sTypes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sTypes = [NSSet setWithObjects: TIPImageTypeBMP,
                                        TIPImageTypeJPEG,
                                        TIPImageTypeGIF,
                                        TIPImageTypePNG,
                                        TIPImageTypeWEBP,
                                        nil];
    });
    return sTypes;
}

NSString * __nullable TIPDetectImageTypeViaMagicNumbers(NSData *dataObj)
{
    CFDataRef data = (__bridge CFDataRef)dataObj;
    const size_t length = (data) ? (size_t)CFDataGetLength(data) : 0;
    const UInt8 *bytes = (data) ? CFDataGetBytePtr(data) : NULL;

    if (MAGIC_NUMBERS_ARE_EQUAL(bytes, length, kJPEGMagicNumbers)) {
        // kUTTypeJPEG;
        return TIPImageTypeJPEG;
    }

    if (MAGIC_NUMBERS_ARE_EQUAL(bytes, length, kPNGMagicNumbers)) {
        // kUTTypePNG;
        return TIPImageTypePNG;
    }

    if (MAGIC_NUMBERS_ARE_EQUAL(bytes, length, kBMP1MagicNumbers)) {
        // kUTTypeBMP;
        return TIPImageTypeBMP;
    }

    if (MAGIC_NUMBERS_ARE_EQUAL(bytes, length, kGIFMagicNumbers)) {
        // kUTTypeGIF;
        return TIPImageTypeGIF;
    }

    if (length >= 12) {
        // WebP has 2 magic numbers flanking real data,
        // so we need to split the check.
        if (0 == memcmp(bytes, kWEBPMagicNumbers, 4)) {
            if (0 == memcmp(bytes + 8, kWEBPMagicNumbers + 8, 4)) {
                // kUTTypeWEBP
                return TIPImageTypeWEBP;
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
                        || [type isEqualToString:TIPImageTypeJPEG2000]
                        || [type isEqualToString:TIPImageTypeHEIC]
                        || [type isEqualToString:TIPImageTypeAVCI];

    // though GIF can be munged many ways to change the quality,
    // we'll keep it simple and not treat GIF as supporting lossy quality

    return hasLossy;
}

BOOL TIPImageTypeSupportsIndexedPalette(NSString * __nullable type)
{
    const BOOL supportsPalette = [type isEqualToString:TIPImageTypePNG]
                              || [type isEqualToString:TIPImageTypeGIF];

    // GIF actually _only_ supports indexed palette encoding.

    return supportsPalette;
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

    const BOOL isTypeRawImage = (BOOL)UTTypeConformsTo(imageType, kUTTypeRawImage) || [utType isEqualToString:TIPImageTypeRAW];

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
    } else if (UTTypeConformsTo(imageType, CFSTR("public.heic"))) {
        return TIPImageTypeHEIC;
    } else if (UTTypeConformsTo(imageType, CFSTR("public.avci"))) {
        return TIPImageTypeAVCI;
    } else if (UTTypeConformsTo(imageType, CFSTR("org.webmproject.webp"))) {
        return TIPImageTypeWEBP;
    }

    return nil;
}

NSString * __nullable TIPFileExtensionFromUTType(NSString * __nullable utType)
{
    if (!utType) {
        return nil;
    }

    return (NSString *)CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)utType,
                                                                         kUTTagClassFilenameExtension));
}

NSString * __nullable TIPFileExtensionToUTType(NSString * __nullable fileExtension, BOOL mustBeImageUTType)
{
    if (!fileExtension) {
        return nil;
    }

    return (NSString *)CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                                               (__bridge CFStringRef)fileExtension,
                                                                               (mustBeImageUTType) ? kUTTypeImage : NULL));
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

#pragma mark Inspection stuff

static NSString * __nullable _DetectImageTypeFromImageSource(CGImageSourceRef imageSourceRef,
                                                             TIPImageEncodingOptions * __nullable optionsOut,
                                                             NSUInteger * __nullable animationFrameCountOut)
{
    NSString *type = nil;
    TIPImageEncodingOptions optionsRead = TIPImageEncodingNoOptions;
    NSUInteger animationFrameCount = 1;

    TIPWorkAroundCoreGraphicsUTTypeLoadBug();

    if (imageSourceRef != NULL) {

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

                    if ([(NSNumber *)CFDictionaryGetValue(imageProperties, kCGImagePropertyIsIndexed) boolValue]) {
                        optionsRead |= TIPImageEncodingIndexedColorPalette;
                    }

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
                    } else if (TIP_BITMASK_EXCLUDES_FLAGS(optionsRead, TIPImageEncodingIndexedColorPalette) && [type isEqualToString:TIPImageTypeGIF]) {
                        optionsRead |= TIPImageEncodingIndexedColorPalette;
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

    if (optionsOut) {
        *optionsOut = optionsRead;
    }
    if (animationFrameCountOut) {
        *animationFrameCountOut = animationFrameCount;
    }

    return type;
}

NSString * __nullable TIPDetectImageTypeFromFile(NSURL *filePath,
                                                 TIPImageEncodingOptions * __nullable optionsOut,
                                                 NSUInteger * __nullable animationFrameCountOut)
{
    if (filePath.isFileURL) {
        NSDictionary *options = @{ (NSString *)kCGImageSourceShouldCache : @NO };
        CGImageSourceRef imageSourceRef = CGImageSourceCreateWithURL((CFURLRef)filePath, (CFDictionaryRef)options);
        TIPDeferRelease(imageSourceRef);
        if (imageSourceRef != NULL) {
            return _DetectImageTypeFromImageSource(imageSourceRef, optionsOut, animationFrameCountOut);
        }
    }

    if (optionsOut) {
        *optionsOut = TIPImageEncodingNoOptions;
    }
    if (animationFrameCountOut) {
        *animationFrameCountOut = 1;
    }

    // Couldn't detect, try magic numbers
    if (filePath.isFileURL) {
        FILE *file = fopen(filePath.path.UTF8String, "r");
        if (file) {
            tip_defer(^{ fclose(file); });
            char buffer[TIPMagicNumbersForImageTypeMaximumLength] = { 0 };
            fread(buffer, 1, TIPMagicNumbersForImageTypeMaximumLength, file);
            NSData *data = [NSData dataWithBytesNoCopy:buffer length:TIPMagicNumbersForImageTypeMaximumLength freeWhenDone:NO];
            return TIPDetectImageTypeViaMagicNumbers(data);
        }
    }

    return nil;
}

NSString * __nullable TIPDetectImageType(NSData *data,
                                         TIPImageEncodingOptions * __nullable optionsOut,
                                         NSUInteger * __nullable animationFrameCountOut,
                                         BOOL hasCompleteImageData)
{
    NSDictionary *options = @{ (NSString *)kCGImageSourceShouldCache : @NO };
    CGImageSourceRef imageSourceRef = CGImageSourceCreateIncremental((__bridge CFDictionaryRef)options);
    TIPDeferRelease(imageSourceRef);
    if (imageSourceRef != NULL && data != nil) {
        CGImageSourceUpdateData(imageSourceRef, (__bridge CFDataRef)data, hasCompleteImageData);
        return _DetectImageTypeFromImageSource(imageSourceRef, optionsOut, animationFrameCountOut);
    }

    if (optionsOut) {
        *optionsOut = TIPImageEncodingNoOptions;
    }
    if (animationFrameCountOut) {
        *animationFrameCountOut = 1;
    }

    // Couldn't detect, try magic numbers
    return TIPDetectImageTypeViaMagicNumbers(data);
}

NSUInteger TIPImageDetectProgressiveScanCount(NSData *data)
{
    size_t byteIndex = 0;
    size_t length = (size_t)data.length;
    const UInt8 *bytes = (const UInt8 *)data.bytes;

    if (length <= 10) {
        return 0;
    }

    if (!MAGIC_NUMBERS_ARE_EQUAL(bytes, length, kJPEGMagicNumbers)) {
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
