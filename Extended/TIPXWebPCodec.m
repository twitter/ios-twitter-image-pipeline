//
//  TIPXWebPCodec.m
//  TwitterImagePipeline
//
//  Created on 11/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Accelerate/Accelerate.h>
#import <TwitterImagePipeline/TwitterImagePipeline.h>
#import <WebP/decode.h>
#import <WebP/encode.h>
#import "TIPXWebPCodec.h"

#pragma mark - Constants

NSString * const TIPXImageTypeWebP = @"google.webp";

#pragma mark - Defer support

typedef void(^tipx_defer_block_t)(void);
NS_INLINE void tipx_deferFunc(__strong tipx_defer_block_t __nonnull * __nonnull blockRef)
{
    tipx_defer_block_t actualBlock = *blockRef;
    actualBlock();
}

#define _tipx_macro_concat(a, b) a##b
#define tipx_macro_concat(a, b) _tipx_macro_concat(a, b)

#pragma twitter startignorestylecheck

#define tipx_defer(deferBlock) \
__strong tipx_defer_block_t tipx_macro_concat(tipx_stack_defer_block_, __LINE__) __attribute__((cleanup(tipx_deferFunc), unused)) = deferBlock

#define TIPXDeferRelease(ref) tipx_defer(^{ if (ref) { CFRelease(ref); } })

#pragma twitter stopignorestylecheck

#pragma mark - Declarations

static TIPImageContainer * __nullable TIPXWebPConstructImageContainer(CGDataProviderRef dataProvider, const size_t width, const size_t height, const size_t bytesPerPixel, const size_t componentsPerPixel);
static BOOL TIPXWebPPictureImport(WebPPicture *picture, CGImageRef imageRef);
static BOOL TIPXWebPCreateRGBADataForImage(CGImageRef sourceImage, vImage_Buffer *convertedImageBuffer);

@interface TIPXWebPDecoderContext : NSObject <TIPImageDecoderContext>

@property (nonatomic, readonly) NSData *tip_data;
@property (nonatomic, readonly) CGSize tip_dimensions;
@property (nonatomic, readonly) BOOL tip_hasAlpha;
@property (nonatomic, readonly) NSUInteger tip_frameCount;

- (instancetype)initWithExpectedContentLength:(NSUInteger)length buffer:(NSMutableData *)buffer;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly) NSUInteger expectedContentLength;

- (TIPImageDecoderAppendResult)append:(NSData *)data;
- (TIPImageContainer *)renderImage:(TIPImageDecoderRenderMode)mode;
- (TIPImageDecoderAppendResult)finalizeDecoding;

@end

@interface TIPXWebPDecoder : NSObject <TIPImageDecoder>
@end

@interface TIPXWebPEncoder : NSObject <TIPImageEncoder>
@end

#pragma mark - Implementations

@implementation TIPXWebPCodec

- (instancetype)init
{
    if (self = [super init]) {
        _tip_decoder = [[TIPXWebPDecoder alloc] init];
        _tip_encoder = [[TIPXWebPEncoder alloc] init];
    }
    return self;
}

@end

@implementation TIPXWebPDecoder

- (TIPImageDecoderDetectionResult)tip_detectDecodableData:(NSData *)data earlyGuessImageType:(NSString *)imageType
{
    // RIFF layout is:
    //   Offset  tag
    //   0...3   "RIFF" 4-byte tag
    //   4...7   size of image data (including metadata) starting at offset 8
    //   8...11  "WEBP"   our form-type signature
    if (data.length >= 12) {
        const Byte *bytes = data.bytes;
        if (0 == memcmp(bytes, "RIFF", 4)) {
            bytes += 8;
            if (0 == memcmp(bytes, "WEBP", 4)) {
                return TIPImageDecoderDetectionResultMatch;
            }
        }
        return TIPImageDecoderDetectionResultNoMatch;
    }
    return TIPImageDecoderDetectionResultNeedMoreData;
}

- (id<TIPImageDecoderContext>)tip_initiateDecoding:(nullable id __unused)config expectedDataLength:(NSUInteger)expectedDataLength buffer:(nullable NSMutableData *)buffer
{
    return [[TIPXWebPDecoderContext alloc] initWithExpectedContentLength:expectedDataLength buffer:buffer];
}

- (TIPImageDecoderAppendResult)tip_append:(id<TIPImageDecoderContext>)context data:(NSData *)data
{
    return [(TIPXWebPDecoderContext *)context append:data];
}

- (TIPImageContainer *)tip_renderImage:(id<TIPImageDecoderContext>)context mode:(TIPImageDecoderRenderMode)mode
{
    return [(TIPXWebPDecoderContext *)context renderImage:mode];
}

- (TIPImageDecoderAppendResult)tip_finalizeDecoding:(id<TIPImageDecoderContext>)context
{
    return [(TIPXWebPDecoderContext *)context finalizeDecoding];
}

- (TIPImageContainer *)tip_decodeImageWithData:(NSData *)imageData config:(id)config
{
    int width, height;
    Byte *rgbaBytes = WebPDecodeRGBA(imageData.bytes, imageData.length, &width, &height);
    if (!rgbaBytes) {
        return nil;
    }

    const size_t totalBytes = (size_t)width * (size_t)height * 4 /* RGBA */;
    NSData *rgbaData = [[NSData alloc] initWithBytesNoCopy:rgbaBytes length:totalBytes deallocator:^(void *bytes, NSUInteger length) {
        WebPFree(rgbaBytes);
    }];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)rgbaData);
    TIPXDeferRelease(provider);
    if (!provider) {
        return nil;
    }

    return TIPXWebPConstructImageContainer(provider, (size_t)width, (size_t)height, 4 /* bytes per pixel */, 4 /* components per pixel */);
}

@end

@implementation TIPXWebPEncoder

- (NSData *)tip_writeDataWithImage:(TIPImageContainer *)imageContainer
                   encodingOptions:(TIPImageEncodingOptions)encodingOptions
                  suggestedQuality:(float)quality
                             error:(out NSError * __autoreleasing *)error
{
    __block WebPPicture *pictureRef = NULL;
    __block TIPErrorCode errorCode = TIPErrorCodeUnknown;
    __block NSData *outputData = nil;
    tipx_defer(^{
        if (pictureRef) {
            WebPPictureFree(pictureRef);
        }
        if (error && !outputData) {
            *error = [NSError errorWithDomain:TIPErrorDomain code:errorCode userInfo:nil];
        }
    });

    UIImage *image = imageContainer.image;
    if (imageContainer.animated) {
        // TODO: supported animated
        image = image.images.firstObject;
    }

    CGImageRef imageRef = image.CGImage;
    if (!imageRef) {
        errorCode = TIPErrorCodeMissingCGImage;
        return nil;
    }

    WebPConfig config;
    if (!WebPConfigPreset(&config, WEBP_PRESET_DEFAULT, quality * 100.f)) {
        return nil;
    }
    config.lossless = (quality == 1.f) ? 1 : 0;

    if (!WebPValidateConfig(&config)) {
        return nil;
    }

    WebPPicture pictureStruct;
    if (!WebPPictureInit(&pictureStruct)) {
        return nil;
    }
    pictureRef = &pictureStruct;

    const size_t width = CGImageGetWidth(imageRef);
    const size_t height = CGImageGetHeight(imageRef);

    pictureRef->width = (int)width;
    pictureRef->height = (int)height;

    if (!TIPXWebPPictureImport(pictureRef, imageRef)) {
        return nil;
    }

    WebPMemoryWriter *writerRef = (WebPMemoryWriter *)malloc(sizeof(WebPMemoryWriter));
    WebPMemoryWriterInit(writerRef);

    dispatch_block_t writerDeallocBlock = ^{
        WebPMemoryWriterClear(writerRef);
        free(writerRef);
    };

    pictureRef->writer = WebPMemoryWrite;
    pictureRef->custom_ptr = writerRef;
    if (!WebPEncode(&config, pictureRef)) {
        writerDeallocBlock();
        return nil;
    }

    outputData = [[NSData alloc] initWithBytesNoCopy:writerRef->mem length:writerRef->size deallocator:^(void *bytes, NSUInteger length) {
        writerDeallocBlock();
    }];

    return outputData;
}

@end

@implementation TIPXWebPDecoderContext
{
    struct {
        BOOL didEncounterFailure:1;
        BOOL didFreeDecoderBuffer:1;
        BOOL didLoadHeaders:1;
        BOOL didComplete:1;
    } _flags;

    WebPDecBuffer _decoderBuffer;
    WebPIDecoder *_decoder;
    NSMutableData *_dataBuffer;

    TIPImageContainer *_cachedImageContainer;
}

@synthesize tip_data = _dataBuffer;

- (id)tip_config
{
    return nil;
}

- (instancetype)initWithExpectedContentLength:(NSUInteger)length buffer:(NSMutableData *)buffer
{
    if (self = [super init]) {
        _expectedContentLength = length;
        if (WebPInitDecBuffer(&_decoderBuffer)) {
            _decoderBuffer.colorspace = MODE_RGBA;
            _decoder = WebPINewDecoder(&_decoderBuffer);
        } else {
            _flags.didFreeDecoderBuffer = 1;
        }
        if (!_decoder) {
            _flags.didEncounterFailure = 1;
        }

        _dataBuffer = buffer ?: ((length > 0) ? [NSMutableData dataWithCapacity:length] : [NSMutableData data]);
    }
    return self;
}

- (void)dealloc
{
    [self _tipx_cleanup];
}

- (TIPImageDecoderAppendResult)append:(NSData *)data
{
    if (_flags.didComplete) {
        return TIPImageDecoderAppendResultDidCompleteLoading;
    }

    if (_flags.didEncounterFailure) {
        return TIPImageDecoderAppendResultDidProgress;
    }

    TIPImageDecoderAppendResult result = TIPImageDecoderAppendResultDidProgress;

    // append & update

    if (data) {
        [_dataBuffer appendData:data];

        if (!_flags.didLoadHeaders) {
            WebPBitstreamFeatures features;
            if (VP8_STATUS_OK == WebPGetFeatures(_dataBuffer.bytes, _dataBuffer.length, &features)) {
                _tip_dimensions = CGSizeMake(features.width, features.height);
                _tip_hasAlpha = !!features.has_alpha;

                if (features.has_animation) {
                    // TODO: support animated WebP
                    _flags.didEncounterFailure = 1;
                    return result;
                }

                result = TIPImageDecoderAppendResultDidLoadHeaders;
                _flags.didLoadHeaders = 1;
            }
        }

        if (_flags.didLoadHeaders) {
            VP8StatusCode code = WebPIUpdate(_decoder, _dataBuffer.bytes, _dataBuffer.length);
            if (VP8_STATUS_OK == code) {
                _tip_frameCount = 1;
                _flags.didComplete = 1;
                result = TIPImageDecoderAppendResultDidCompleteLoading;
            } else if (VP8_STATUS_SUSPENDED == code) {
                // more progress to be made

                // TODO: add support for progressive loading once WebP adds support.
                //       planned but NYI by Google as of Nov 11, 2016.
            } else {
                _flags.didEncounterFailure = 1;
            }
        }
    }

    return result;
}

- (TIPImageContainer *)renderImage:(TIPImageDecoderRenderMode)mode
{
    if (!_flags.didComplete) {
        return nil;
    }

    if (!_cachedImageContainer) {
        _cachedImageContainer = [self _tipx_renderImage];
        if (_cachedImageContainer) {
            [self _tipx_cleanup];
        }
    }

    return _cachedImageContainer;
}

- (TIPImageDecoderAppendResult)finalizeDecoding
{
    TIPImageDecoderAppendResult result = [self append:[NSData data]];
    (void)[self renderImage:TIPImageDecoderRenderModeCompleteImage]; // cache
    return result;
}

#pragma mark Private

- (void)_tipx_cleanup
{
    if (_decoder) {
        WebPIDelete(_decoder);
        _decoder = NULL;
    }
    if (!_flags.didFreeDecoderBuffer) {
        WebPFreeDecBuffer(&_decoderBuffer);
        _flags.didFreeDecoderBuffer = 1;
    }
}

- (TIPImageContainer *)_tipx_renderImage
{
    int w, h;
    Byte *rgbaBytes = WebPIDecGetRGB(_decoder, /*last_y*/NULL, &w, &h, /*stride*/NULL);

    static const size_t bitsPerComponent = 8;
    static const size_t bitsPerPixel = 32;
    static const size_t bytesPerPixel = bitsPerPixel / 8;
    static const size_t componentsPerPixel = bitsPerPixel / bitsPerComponent;
    const size_t totalBytes = (size_t)(w * h) * bytesPerPixel;

    // TODO: instead of copying the bytes over (doubling the memory required)
    // we should have a single buffer shared between the output data provider
    // and the WebP decoder.
    // There is a way to create a data provider with raw bytes that has a release
    // callback where the contextual owner of those bytes could be "freed".

    CFDataRef data = CFDataCreate(NULL, rgbaBytes, (CFIndex)totalBytes);
    TIPXDeferRelease(data);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    TIPXDeferRelease(provider);
    if (!provider) {
        return nil;
    }

    return TIPXWebPConstructImageContainer(provider,
                                           (size_t)w,
                                           (size_t)h,
                                           componentsPerPixel,
                                           bytesPerPixel);
}

@end

static TIPImageContainer *TIPXWebPConstructImageContainer(CGDataProviderRef dataProvider, const size_t width, const size_t height, const size_t bytesPerPixel, const size_t componentsPerPixel)
{
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    TIPXDeferRelease(colorSpace);
    if (!colorSpace) {
        return nil;
    }

    const CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaLast;
    const CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
    const BOOL shouldInterpolate = YES;
    const size_t bitsPerComponent = 8;
    const size_t bitsPerPixel = bitsPerComponent * componentsPerPixel;

    CGImageRef imageRef = CGImageCreate(width,
                                        height,
                                        bitsPerComponent,
                                        bitsPerPixel,
                                        bytesPerPixel * width,
                                        colorSpace,
                                        bitmapInfo,
                                        dataProvider,
                                        NULL /* CGFloat *decode */,
                                        shouldInterpolate,
                                        renderingIntent);
    TIPXDeferRelease(imageRef);

    UIImage *image = [UIImage imageWithCGImage:imageRef];
    if (!image) {
        return nil;
    }
    return [[TIPImageContainer alloc] initWithImage:image];
}

static BOOL TIPXWebPPictureImport(WebPPicture *picture, CGImageRef imageRef)
{
    __block vImage_Buffer convertedImageBuffer = {};

    tipx_defer(^{
        if (convertedImageBuffer.data) {
            free(convertedImageBuffer.data);
        }
    });

    if (!TIPXWebPCreateRGBADataForImage(imageRef, &convertedImageBuffer)) {
        return NO;
    }

    return 0 != WebPPictureImportRGBA(picture, convertedImageBuffer.data, (int)convertedImageBuffer.rowBytes);
}

static BOOL TIPXWebPCreateRGBADataForImage(CGImageRef sourceImage, vImage_Buffer *convertedImageBuffer)
{
    if (!convertedImageBuffer) {
        return NO;
    }

    vImage_CGImageFormat sourceImageFormat = {
        .bitsPerComponent = (uint32_t)CGImageGetBitsPerComponent(sourceImage),
        .bitsPerPixel = (uint32_t)CGImageGetBitsPerPixel(sourceImage),
        .colorSpace = CGImageGetColorSpace(sourceImage),
        .bitmapInfo = CGImageGetBitmapInfo(sourceImage)
    };

    CGColorSpaceRef deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB();
    TIPXDeferRelease(deviceRGBColorSpace);

    vImage_CGImageFormat convertedImageFormat = {
        .bitsPerComponent = 8,
        .bitsPerPixel = 32,
        .colorSpace = deviceRGBColorSpace,
        .bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaLast
    };

    vImage_Error errorCode = kvImageNoError;

    __block vImage_Buffer sourceImageBuffer = {};
    tipx_defer(^{
        if (sourceImageBuffer.data) {
            free(sourceImageBuffer.data);
        }
    });

    errorCode = vImageBuffer_InitWithCGImage(&sourceImageBuffer, &sourceImageFormat, NULL, sourceImage, kvImageNoFlags);
    if (errorCode != kvImageNoError) {
        return NO;
    }

    errorCode = vImageBuffer_Init(convertedImageBuffer, sourceImageBuffer.height, sourceImageBuffer.width, convertedImageFormat.bitsPerPixel, kvImageNoFlags);
    if (errorCode != kvImageNoError) {
        return NO;
    }

    vImageConverterRef imageConverter = vImageConverter_CreateWithCGImageFormat(&sourceImageFormat, &convertedImageFormat, NULL, kvImageNoFlags, NULL);
    if (!imageConverter) {
        return NO;
    }
    tipx_defer(^{
        vImageConverter_Release(imageConverter);
    });

    errorCode = vImageConvert_AnyToAny(imageConverter, &sourceImageBuffer, convertedImageBuffer, NULL, kvImageNoFlags);
    if (errorCode != kvImageNoError) {
        return NO;
    }

    return YES;
}
