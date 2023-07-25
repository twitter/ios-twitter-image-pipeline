//
//  TIPXWebPCodec.m
//  TwitterImagePipeline
//
//  Created on 11/9/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#pragma mark imports

#import <Accelerate/Accelerate.h>

#import "TIPXUtils.h"
#import "TIPXWebPCodec.h"

#pragma mark WebP includes

#import <WebP/decode.h>
#import <WebP/encode.h>
#if TIPX_WEBP_ANIMATION_DECODING_ENABLED
#import <WebPDemux/demux.h>
#define WEBP_HAS_DEMUX 1
#endif

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Declarations

static UIImage * __nullable TIPXWebPRenderImage(NSData *dataBuffer,
                                                CGSize sourceDimensions,
                                                CGSize targetDimensions,
                                                UIViewContentMode targetContentMode,
                                                CGRect framingRect,
                                                CGContextRef __nullable canvas);
static UIImage * __nullable TIPXWebPConstructImage(CGDataProviderRef dataProvider,
                                                   const size_t width,
                                                   const size_t height,
                                                   const size_t bytesPerPixel,
                                                   const size_t componentsPerPixel);
static BOOL TIPXWebPPictureImport(WebPPicture *picture,
                                  CGImageRef imageRef);
static BOOL TIPXWebPCreateRGBADataForImage(CGImageRef sourceImage,
                                           vImage_Buffer *convertedImageBuffer);

@interface TIPXWebPDecoderContext : NSObject <TIPImageDecoderContext>

@property (nonatomic, readonly) NSData *tip_data;
@property (nonatomic, readonly) CGSize tip_dimensions;
@property (nonatomic, readonly) BOOL tip_hasAlpha;
@property (nonatomic, readonly) NSUInteger tip_frameCount;
@property (nonatomic, readonly) BOOL tip_isAnimated;

- (instancetype)initWithExpectedContentLength:(NSUInteger)length
                                       buffer:(NSMutableData *)buffer;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (tipx_nonatomic_direct, readonly) NSUInteger expectedContentLength;

- (TIPImageDecoderAppendResult)append:(NSData *)data TIPX_OBJC_DIRECT;
- (nullable TIPImageContainer *)renderImage:(TIPImageDecoderRenderMode)renderMode
                           targetDimensions:(CGSize)targetDimensions
                          targetContentMode:(UIViewContentMode)targetContentMode TIPX_OBJC_DIRECT;
- (TIPImageDecoderAppendResult)finalizeDecoding TIPX_OBJC_DIRECT;

@end

@interface TIPXWebPDecoder : NSObject <TIPImageDecoder>
@end

@interface TIPXWebPEncoder : NSObject <TIPImageEncoder>
@end

#pragma mark - Implementations

@implementation TIPXWebPCodec

- (instancetype)init
{
    // Shouldn't be called, but will permit in case of type erasure
    return [self initWithPreferredCodec:nil];
}

- (instancetype)initWithPreferredCodec:(nullable id<TIPImageCodec>)preferredCodec
{
    if (self = [super init]) {
        _tip_decoder = preferredCodec.tip_decoder ?: [[TIPXWebPDecoder alloc] init];
        _tip_encoder = preferredCodec.tip_encoder ?: [[TIPXWebPEncoder alloc] init];
    }
    return self;
}

+ (BOOL)hasAnimationDecoding
{
#if WEBP_HAS_DEMUX
    return YES;
#else
    return NO;
#endif
}

@end

@implementation TIPXWebPDecoder

- (TIPImageDecoderDetectionResult)tip_detectDecodableData:(NSData *)data
                                           isCompleteData:(BOOL)complete
                                      earlyGuessImageType:(nullable NSString *)imageType
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

- (id<TIPImageDecoderContext>)tip_initiateDecoding:(nullable id __unused)config
                                expectedDataLength:(NSUInteger)expectedDataLength
                                            buffer:(nullable NSMutableData *)buffer
{
    return [[TIPXWebPDecoderContext alloc] initWithExpectedContentLength:expectedDataLength
                                                                  buffer:buffer];
}

- (TIPImageDecoderAppendResult)tip_append:(TIPXWebPDecoderContext *)context
                                     data:(NSData *)data
{
    return [context append:data];
}

- (nullable TIPImageContainer *)tip_renderImage:(TIPXWebPDecoderContext *)context
                                     renderMode:(TIPImageDecoderRenderMode)renderMode
                               targetDimensions:(CGSize)targetDimensions
                              targetContentMode:(UIViewContentMode)targetContentMode
{
    return [context renderImage:renderMode targetDimensions:targetDimensions targetContentMode:targetContentMode];
}

- (TIPImageDecoderAppendResult)tip_finalizeDecoding:(TIPXWebPDecoderContext *)context
{
    return [context finalizeDecoding];
}

@end

@implementation TIPXWebPEncoder

- (nullable NSData *)tip_writeDataWithImage:(TIPImageContainer *)imageContainer
                            encodingOptions:(TIPImageEncodingOptions)encodingOptions
                           suggestedQuality:(float)quality
                                      error:(out NSError * __nullable __autoreleasing * __nullable)error
{
    __block WebPPicture *pictureRef = NULL;
    __block TIPErrorCode errorCode = TIPErrorCodeUnknown;
    __block NSData *outputData = nil;
    tipx_defer(^{
        if (pictureRef) {
            WebPPictureFree(pictureRef);
        }
        if (error && !outputData) {
            *error = [NSError errorWithDomain:TIPErrorDomain
                                         code:errorCode
                                     userInfo:nil];
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

    WebPMemoryWriter *writerRef = (WebPMemoryWriter *)WebPMalloc(sizeof(WebPMemoryWriter));
    WebPMemoryWriterInit(writerRef);

    dispatch_block_t writerDeallocBlock = ^{
        WebPMemoryWriterClear(writerRef);
        WebPFree(writerRef);
    };

    pictureRef->writer = WebPMemoryWrite;
    pictureRef->custom_ptr = writerRef;
    if (!WebPEncode(&config, pictureRef)) {
        writerDeallocBlock();
        return nil;
    }

    outputData = [[NSData alloc] initWithBytesNoCopy:writerRef->mem
                                              length:writerRef->size
                                         deallocator:^(void *bytes, NSUInteger length) {
        writerDeallocBlock();
    }];

    return outputData;
}

@end

@implementation TIPXWebPDecoderContext
{
    struct {
        BOOL didEncounterFailure:1;
        BOOL didLoadHeaders:1;
        BOOL didLoadFrame:1;
        BOOL didComplete:1;
        BOOL isAnimated:1;
        BOOL isCachedImageFirstFrame:1;
    } _flags;

    NSMutableData *_dataBuffer;
    TIPImageContainer *_cachedImageContainer;
}

@synthesize tip_data = _dataBuffer;

- (BOOL)tip_isAnimated
{
    return _flags.isAnimated;
}

- (nullable id)tip_config
{
    return nil;
}

- (instancetype)initWithExpectedContentLength:(NSUInteger)length
                                       buffer:(NSMutableData *)buffer
{
    if (self = [super init]) {
        _expectedContentLength = length;

        if (buffer) {
            _dataBuffer = buffer;
        } else if (length > 0) {
            _dataBuffer = [NSMutableData dataWithCapacity:length];
        } else {
            _dataBuffer = [NSMutableData data];
        }
    }
    return self;
}

- (void)dealloc
{
    [self _cleanup];
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
                if (!features.has_animation) {
                    _tip_frameCount = 1;
                } else {
#if WEBP_HAS_DEMUX
                    _flags.isAnimated = 1;
                    // WebP animations do not have a header indicating the number of frames,
                    // will have to decode entire file to get number of frames.
                    // Set number of frames to 2 for now and update along the way.
                    _tip_frameCount = 2;
#else
                    _flags.didEncounterFailure = 1;
                    return result;
#endif
                }
                result = TIPImageDecoderAppendResultDidLoadHeaders;
                _flags.didLoadHeaders = 1;
            }
        }
    }

#if WEBP_HAS_DEMUX
    if (_flags.didLoadHeaders && !_flags.didLoadFrame && _flags.isAnimated) {
        WebPData webpData = (WebPData){ .bytes = _dataBuffer.bytes, .size = _dataBuffer.length };
        WebPDemuxState state = WEBP_DEMUX_PARSING_HEADER;
        WebPDemuxer* demuxer = WebPDemuxPartial(&webpData, &state);
        tipx_defer(^{
            WebPDemuxDelete(demuxer);
        });
        if (demuxer && state >= WEBP_DEMUX_PARSED_HEADER) {
            if (WebPDemuxGetI(demuxer, WEBP_FF_FRAME_COUNT) > 1) {
                _flags.didLoadFrame = 1;
                result = TIPImageDecoderAppendResultDidLoadFrame;
            }
        }
    }
#endif

    return result;
}

- (nullable TIPImageContainer *)renderImage:(TIPImageDecoderRenderMode)renderMode
                           targetDimensions:(CGSize)targetDimensions
                          targetContentMode:(UIViewContentMode)targetContentMode
{
    @autoreleasepool {
#if WEBP_HAS_DEMUX
        if (_flags.isAnimated) {
            return [self _renderAnimatedImage:renderMode
                             targetDimensions:targetDimensions
                            targetContentMode:targetContentMode];
        }
#endif

        return [self _renderStaticImage:renderMode
                       targetDimensions:targetDimensions
                      targetContentMode:targetContentMode];
    }
}

- (nullable TIPImageContainer *)_renderStaticImage:(TIPImageDecoderRenderMode)renderMode
                                  targetDimensions:(CGSize)targetDimensions
                                 targetContentMode:(UIViewContentMode)targetContentMode TIPX_OBJC_DIRECT
{
    if (!_flags.didComplete) {
        return nil;
    }

    if (!_cachedImageContainer && !_flags.didEncounterFailure) {
        UIImage *image = TIPXWebPRenderImage(_dataBuffer,
                                             _tip_dimensions,
                                             targetDimensions,
                                             targetContentMode,
                                             CGRectZero,
                                             NULL);
        if (image) {
            _cachedImageContainer = [[TIPImageContainer alloc] initWithImage:image];
            [self _cleanup];
        } else {
            _flags.didEncounterFailure = 1;
        }
    }

    return _cachedImageContainer;
}

#if WEBP_HAS_DEMUX
- (nullable TIPImageContainer *)_renderAnimatedImage:(TIPImageDecoderRenderMode)renderMode
                                    targetDimensions:(CGSize)targetDimensions
                                   targetContentMode:(UIViewContentMode)targetContentMode TIPX_OBJC_DIRECT
{
    BOOL justFirstFrame = NO;
    if (!_flags.didComplete) {
        if (TIPImageDecoderRenderModeCompleteImage == renderMode) {
            return nil;
        }

        if (!_flags.didLoadFrame) {
            return nil;
        }

        if (_flags.isCachedImageFirstFrame && _cachedImageContainer) {
            return _cachedImageContainer;
        }

        justFirstFrame = YES; // <-- we only need the first frame as a preview
    }

    if (!justFirstFrame) {
        if (_cachedImageContainer && !_flags.isCachedImageFirstFrame) {
            return _cachedImageContainer;
        }
    }

    // Create our demuxer (defer delete it)
    WebPData data = (WebPData){ .bytes = _dataBuffer.bytes, .size = _dataBuffer.length };
    WebPDemuxState state = WEBP_DEMUX_PARSING_HEADER;
    WebPDemuxer* demuxer = WebPDemuxPartial(&data, &state);
    tipx_defer(^{
        WebPDemuxDelete(demuxer);
    });
    if (state < WEBP_DEMUX_PARSED_HEADER) {
        return nil;
    }

    // Allocate the WebPIterator (and defer free it)
    WebPIterator* iter = (WebPIterator*)WebPMalloc(sizeof(WebPIterator));
    memset(iter, 0, sizeof(WebPIterator));
    tipx_defer(^{
        WebPFree(iter);
    });

    // Populate the WebPIterator with the first frame (1 based index, 0 index is the last frame)
    if (!WebPDemuxGetFrame(demuxer, 1, iter)) {
        // Failed to get the frame, nothing populated on the iterator
        return nil;
    }
    // Iterator was populated with bookkeeping/allocations for the first frame, defer releasing those references
    tipx_defer(^{
        WebPDemuxReleaseIterator(iter);
    });

    // Go through the animation and pull out the frames (stopping after the first frame if `justFirstFrame` is `YES`)
    NSTimeInterval totalDuration = 0;
    const NSUInteger loopCount = (NSUInteger)WebPDemuxGetI(demuxer, WEBP_FF_LOOP_COUNT);
#if DEBUG
    const CGSize canvasDimensions = CGSizeMake(WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_WIDTH), WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_HEIGHT));
    NSCParameterAssert(canvasDimensions.width == _tip_dimensions.width);
    NSCParameterAssert(canvasDimensions.height == _tip_dimensions.height);
#endif
    const CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    TIPXDeferRelease(colorSpace);
    CGContextRef canvas = CGBitmapContextCreate(NULL /*data*/,
                                                (size_t)_tip_dimensions.width,
                                                (size_t)_tip_dimensions.height,
                                                8,
                                                4 * (size_t)_tip_dimensions.width,
                                                colorSpace,
                                                bitmapInfo);
    TIPXDeferRelease(canvas);
    CGContextClearRect(canvas, (CGRect){ .origin = CGPointZero, .size = _tip_dimensions });
    NSMutableArray<UIImage *> *frames = [[NSMutableArray alloc] initWithCapacity:(NSUInteger)iter->num_frames];
    NSMutableArray<NSNumber *> *frameDurations = [[NSMutableArray alloc] initWithCapacity:(NSUInteger)iter->num_frames];
    do {

        NSData *fragment = [[NSData alloc] initWithBytesNoCopy:(void*)iter->fragment.bytes
                                                        length:iter->fragment.size
                                                  freeWhenDone:NO];
        const CGRect framingRect = CGRectMake(iter->x_offset,
                                              iter->y_offset,
                                              iter->width,
                                              iter->height);
        // CGBitmapContext is bottem-left aligned instead of top-left aligned, so adjust the origin for that use case
        const CGRect canvasFramingRect = CGRectMake(framingRect.origin.x,
                                                    _tip_dimensions.height - framingRect.size.height - framingRect.origin.y,
                                                    framingRect.size.width,
                                                    framingRect.size.height);

        const BOOL isSizedToCanvas = CGSizeEqualToSize(framingRect.size, _tip_dimensions) && CGPointEqualToPoint(framingRect.origin, CGPointZero);

        if (iter->blend_method == WEBP_MUX_NO_BLEND) {
            // clear the area we are about to draw to
            CGContextClearRect(canvas, canvasFramingRect);
        }
        UIImage *frame = TIPXWebPRenderImage(fragment,
                                             _tip_dimensions,
                                             (justFirstFrame && isSizedToCanvas) ? targetDimensions : CGSizeZero,
                                             targetContentMode,
                                             framingRect,
                                             canvas);
        if (iter->dispose_method == WEBP_MUX_DISPOSE_BACKGROUND) {
            // clear the area we just finished drawing to
            CGContextClearRect(canvas, canvasFramingRect);
        }

        if (!frame) {
            return nil;
        }

        const NSTimeInterval duration = (NSTimeInterval)iter->duration / 1000.;
        [frames addObject:frame];
        [frameDurations addObject:@(duration)];
        totalDuration += duration;

    } while (!justFirstFrame && WebPDemuxNextFrame(iter));

    if (justFirstFrame) {
        // Static image (a preview of the full animation)
        _cachedImageContainer = [[TIPImageContainer alloc] initWithImage:frames.firstObject];
    } else {
        // Full animation
        UIImage *image = [UIImage animatedImageWithImages:frames
                                                 duration:totalDuration];
        _cachedImageContainer = [[TIPImageContainer alloc] initWithAnimatedImage:image
                                                                       loopCount:loopCount
                                                                  frameDurations:frameDurations];
    }

    if (_cachedImageContainer) {
        _flags.isCachedImageFirstFrame = !!justFirstFrame;
    }
    return _cachedImageContainer;
}
#endif

- (TIPImageDecoderAppendResult)finalizeDecoding
{
    if (_flags.didEncounterFailure) {
        return TIPImageDecoderAppendResultDidCompleteLoading;
    }

    if (!_flags.didLoadHeaders) {
        return TIPImageDecoderAppendResultDidProgress;
    }

#if WEBP_HAS_DEMUX
    if (_flags.isAnimated) {
        WebPData data = (WebPData){ .bytes = _dataBuffer.bytes, .size = _dataBuffer.length };
        WebPDemuxState state = WEBP_DEMUX_PARSING_HEADER;
        WebPDemuxer* demuxer = WebPDemuxPartial(&data, &state);
        tipx_defer(^{
            WebPDemuxDelete(demuxer);
        });
        if (!demuxer || WEBP_DEMUX_DONE != state) {
            _flags.didEncounterFailure = 1;
            return TIPImageDecoderAppendResultDidCompleteLoading;
        }

        // Update the frame count to the full count (was set to "2" as a placeholder)
        _tip_frameCount = WebPDemuxGetI(demuxer, WEBP_FF_FRAME_COUNT);
    }
#endif

    _flags.didComplete = 1;
    return TIPImageDecoderAppendResultDidCompleteLoading;
}

#pragma mark Private

- (void)_cleanup TIPX_OBJC_DIRECT
{
    // clean up any temporary state before decoding to a TIPImageContainer
}

static UIImage *TIPXWebPRenderImage(NSData *dataBuffer,
                                    CGSize sourceDimensions,
                                    CGSize targetDimensions,
                                    UIViewContentMode targetContentMode,
                                    CGRect framingRect,
                                    CGContextRef __nullable canvas)
{
    __block WebPDecoderConfig* config = (WebPDecoderConfig*)WebPMalloc(sizeof(WebPDecoderConfig));
    tipx_defer(^{
        if (config) {
            WebPFree(config);
        }
    });
    if (!WebPInitDecoderConfig(config)) {
        return nil;
    }

    BOOL isAligned = canvas != NULL; // having a canvas indicates an animation, always treat fragment as being "aligned"
    if (!isAligned) {
        // is aligned if the origin is offset
        isAligned = !CGPointEqualToPoint(framingRect.origin, CGPointZero);
        if (!isAligned) {
            // is aligned if the size is not the canvas size (nor zero size)
            isAligned =     !CGSizeEqualToSize(framingRect.size, sourceDimensions)
                        &&  !CGSizeEqualToSize(framingRect.size, CGSizeZero);
        }
    }

    if (!isAligned) {
        const CGSize scaledDimensions = TIPDimensionsScaledToTargetSizing(sourceDimensions,
                                                                          targetDimensions,
                                                                          targetContentMode);
        if (!CGSizeEqualToSize(scaledDimensions, sourceDimensions)) {
            config->options.scaled_width = (int)scaledDimensions.width;
            config->options.scaled_height = (int)scaledDimensions.height;
            config->options.use_scaling = 1;
            // should we stop fancy upscaling? config.options.no_fancy_upsampling = 1;
        }
        framingRect.origin = CGPointZero;
        framingRect.size = scaledDimensions;
    }

    // Set the output colorspace as RGB (TODO: there might be a device optimization using BGRA or ABGR...)
    config->output.colorspace = MODE_RGBA;

    if (VP8_STATUS_OK != WebPDecode(dataBuffer.bytes, dataBuffer.length, config)) {
        return nil;
    }

    static const size_t bitsPerComponent = 8;
    static const size_t bitsPerPixel = 32;
    static const size_t bytesPerPixel = bitsPerPixel / 8;
    static const size_t componentsPerPixel = bitsPerPixel / bitsPerComponent;

    WebPDecoderConfig* configLongLived = config;
    os_compiler_barrier();
    config = nil; // clear the ref to avoid being free on scope exit
    NSData *data = [[NSData alloc] initWithBytesNoCopy:configLongLived->output.u.RGBA.rgba
                                                length:configLongLived->output.u.RGBA.size
                                           deallocator:^(void * _Nonnull bytes, NSUInteger length) {
        WebPFreeDecBuffer(&configLongLived->output);
        WebPFree(configLongLived);
    }];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    TIPXDeferRelease(provider);
    if (!provider) {
        return nil;
    }

    UIImage *image = TIPXWebPConstructImage(provider,
                                            (size_t)configLongLived->output.width,
                                            (size_t)configLongLived->output.height,
                                            componentsPerPixel,
                                            bytesPerPixel);
    if (image && isAligned) {

        if (canvas) {
            framingRect.origin.y = sourceDimensions.height - framingRect.size.height - framingRect.origin.y;
            CGContextDrawImage(canvas, framingRect, image.CGImage);
            CGImageRef imageRef = CGBitmapContextCreateImage(canvas);
            TIPXDeferRelease(imageRef);
            image = [UIImage imageWithCGImage:imageRef];
        } else {
            UIGraphicsBeginImageContextWithOptions(sourceDimensions, !configLongLived->input.has_alpha, 1.0);
            tipx_defer(^{
                UIGraphicsEndImageContext();
            });
            CGContextClearRect(UIGraphicsGetCurrentContext(), (CGRect){ .origin = CGPointZero, .size = sourceDimensions });
            [image drawInRect:framingRect];
            image = UIGraphicsGetImageFromCurrentImageContext();
        }

    }
    return image;
}

@end

static UIImage *TIPXWebPConstructImage(CGDataProviderRef dataProvider,
                                       const size_t width,
                                       const size_t height,
                                       const size_t bytesPerPixel,
                                       const size_t componentsPerPixel)
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

    return [UIImage imageWithCGImage:imageRef];
}

static BOOL TIPXWebPPictureImport(WebPPicture *picture,
                                  CGImageRef imageRef)
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

    return 0 != WebPPictureImportRGBA(picture,
                                      convertedImageBuffer.data,
                                      (int)convertedImageBuffer.rowBytes);
}

static BOOL TIPXWebPCreateRGBADataForImage(CGImageRef sourceImage,
                                           vImage_Buffer *convertedImageBuffer)
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

    errorCode = vImageBuffer_InitWithCGImage(&sourceImageBuffer,
                                             &sourceImageFormat,
                                             NULL /*backgroundColor*/,
                                             sourceImage,
                                             kvImageNoFlags);
    if (errorCode != kvImageNoError) {
        return NO;
    }

    errorCode = vImageBuffer_Init(convertedImageBuffer,
                                  sourceImageBuffer.height,
                                  sourceImageBuffer.width,
                                  convertedImageFormat.bitsPerPixel,
                                  kvImageNoFlags);
    if (errorCode != kvImageNoError) {
        return NO;
    }

    vImageConverterRef imageConverter = vImageConverter_CreateWithCGImageFormat(&sourceImageFormat,
                                                                                &convertedImageFormat,
                                                                                NULL /*backgroundColor*/,
                                                                                kvImageNoFlags,
                                                                                NULL /*error out*/);
    if (!imageConverter) {
        return NO;
    }
    tipx_defer(^{
        vImageConverter_Release(imageConverter);
    });

    errorCode = vImageConvert_AnyToAny(imageConverter,
                                       &sourceImageBuffer,
                                       convertedImageBuffer,
                                       NULL /*tempBuffer*/,
                                       kvImageNoFlags);
    if (errorCode != kvImageNoError) {
        return NO;
    }

    return YES;
}

NS_ASSUME_NONNULL_END

