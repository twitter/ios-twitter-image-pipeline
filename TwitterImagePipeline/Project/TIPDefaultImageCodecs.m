//
//  TIPDefaultImageCodecs.m
//  TwitterImagePipeline
//
//  Created on 11/7/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import "NSData+TIPAdditions.h"
#import "TIP_Project.h"
#import "TIPDefaultImageCodecs.h"
#import "TIPError.h"
#import "TIPImageContainer.h"
#import "UIImage+TIPAdditions.h"

NS_ASSUME_NONNULL_BEGIN

#define kJPEG_MARKER_SPECIAL_BYTE   (0xFF)
#define kJPEG_MARKER_START_FRAME    (0xDA)

@interface TIPCGImageSourceDecoderContext : NSObject <TIPImageDecoderContext>
{
    @protected
    NSUInteger _frameCount;
    NSUInteger _lastFrameStartIndex;
    NSUInteger _lastFrameEndIndex;
    NSUInteger _lastSafeByteIndex;
    NSUInteger _lastByteReadIndex;
    NSMutableData *_data;
    BOOL _progressive;
}

- (instancetype)initWithUTType:(NSString *)UTType expectedDataLength:(NSUInteger)expectedDataLength buffer:(NSMutableData *)buffer supportsProgressiveLoading:(BOOL)supportsProgressive;
- (instancetype)initWithUTType:(NSString *)UTType expectedDataLength:(NSUInteger)expectedDataLength buffer:(NSMutableData *)buffer potentiallyAnimated:(BOOL)animated;
- (instancetype)initWithUTType:(NSString *)UTType expectedDataLength:(NSUInteger)expectedDataLength buffer:(NSMutableData *)buffer NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (TIPImageDecoderAppendResult)appendData:(NSData *)data;
- (nullable TIPImageContainer *)renderImage:(TIPImageDecoderRenderMode)mode;
- (TIPImageDecoderAppendResult)finalizeDecoding;

@end

@interface TIPCGImageSourceDecoderContext (Protected)
- (BOOL)readContextualHeaders;
- (BOOL)readMore:(BOOL)complete;
@end

@interface TIPJPEGCGImageSourceDecoderContext : TIPCGImageSourceDecoderContext
@end

@interface TIPAnimatedCGImageSourceDecoder : TIPBasicCGImageSourceDecoder
@end

@interface TIPBasicCGImageSourceDecoder ()
@property (nonatomic, readonly, copy) NSString *UTType;
- (instancetype)initWithUTType:(NSString *)UTType;
@end

@interface TIPBasicCGImageSourceEncoder ()
@property (nonatomic, readonly, copy) NSString *UTType;
- (instancetype)initWithUTType:(NSString *)UTType;
@end

@implementation TIPBasicCGImageSourceCodec

+ (nullable instancetype)codecWithImageType:(NSString *)imageType
{
    BOOL animated = NO;
    id<TIPImageDecoder> decoder = nil;
    id<TIPImageEncoder> encoder = nil;

    if ([imageType isEqualToString:TIPImageTypeJPEG]) {
        // JPEG has a special decoder
        decoder = [[TIPJPEGCGImageSourceDecoder alloc] init];
        encoder = [[TIPBasicCGImageSourceEncoder alloc] initWithUTType:(NSString *)kUTTypeJPEG];
    } else if ([imageType isEqualToString:TIPImageTypeGIF] || [imageType isEqualToString:TIPImageTypePNG]) {
        // GIF & APNG can be animated
        NSString *UTType = TIPImageTypeToUTType(imageType);
        decoder = [[TIPAnimatedCGImageSourceDecoder alloc] initWithUTType:UTType];
        encoder = [[TIPBasicCGImageSourceEncoder alloc] initWithUTType:UTType];
        animated = YES;
    } else if ([imageType isEqualToString:TIPImageTypeJPEG2000] || [imageType isEqualToString:TIPImageTypeTIFF] || [imageType isEqualToString:TIPImageTypeBMP] || [imageType isEqualToString:TIPImageTypeTARGA]) {
        // These are all normal
        NSString *UTType = TIPImageTypeToUTType(imageType);
        decoder = [[TIPBasicCGImageSourceDecoder alloc] initWithUTType:UTType];
        encoder = [[TIPBasicCGImageSourceEncoder alloc] initWithUTType:UTType];
    } else if ([imageType isEqualToString:TIPImageTypeICO] || ([imageType isEqualToString:TIPImageTypeRAW] && &kUTTypeRawImage)) {
        // These cannot be encoded, only decoded
        NSString *UTType = TIPImageTypeToUTType(imageType);
        decoder = [[TIPBasicCGImageSourceDecoder alloc] initWithUTType:UTType];
    }

    return (decoder) ? [[TIPBasicCGImageSourceCodec alloc] initWithDecoder:decoder encoder:encoder animated:animated] : nil;
}

- (instancetype)initWithDecoder:(id<TIPImageDecoder>)decoder encoder:(nullable id<TIPImageEncoder>)encoder animated:(BOOL)animated
{
    if (self = [super init]) {
        _tip_decoder = decoder;
        _tip_encoder = encoder;
        _tip_isAnimated = animated;
    }
    return self;
}

@end

@implementation TIPBasicCGImageSourceDecoder

- (instancetype)initWithUTType:(NSString *)UTType
{
    if (self = [super init]) {
        _UTType = [UTType copy];
    }
    return self;
}

- (TIPImageDecoderDetectionResult)tip_detectDecodableData:(NSData *)data earlyGuessImageType:(nullable NSString *)imageType
{
    if (!imageType) {
        imageType = TIPDetectImageType(data, NULL, NULL, NO);
    }

    NSString *UTType = TIPImageTypeToUTType(imageType);
    if (UTType && UTTypeConformsTo((__bridge CFStringRef)UTType, (__bridge CFStringRef)_UTType)) {
        return TIPImageDecoderDetectionResultMatch;
    }

    return TIPImageDecoderDetectionResultNoMatch;
}

- (id<TIPImageDecoderContext>)tip_initiateDecoding:(nullable id __unused)config expectedDataLength:(NSUInteger)expectedDataLength buffer:(nullable NSMutableData *)buffer
{
    return [[TIPCGImageSourceDecoderContext alloc] initWithUTType:_UTType expectedDataLength:expectedDataLength buffer:buffer];
}

- (TIPImageDecoderAppendResult)tip_append:(id<TIPImageDecoderContext>)context data:(NSData *)data
{
    return [(TIPCGImageSourceDecoderContext *)context appendData:data];
}

- (nullable TIPImageContainer *)tip_renderImage:(id<TIPImageDecoderContext>)context mode:(TIPImageDecoderRenderMode)mode
{
    return [(TIPCGImageSourceDecoderContext *)context renderImage:mode];
}

- (TIPImageDecoderAppendResult)tip_finalizeDecoding:(id<TIPImageDecoderContext>)context
{
    return [(TIPCGImageSourceDecoderContext *)context finalizeDecoding];
}

- (BOOL)tip_supportsProgressiveDecoding
{
    return NO;
}

- (nullable TIPImageContainer *)tip_decodeImageWithData:(NSData *)imageData config:(nullable id)config
{
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((CFDataRef)imageData, NULL);
    TIPDeferRelease(imageSource);
    CFStringRef UTType = CGImageSourceGetType(imageSource);
    if (UTType && UTTypeConformsTo(UTType, (__bridge CFStringRef)_UTType)) {
        return [TIPImageContainer imageContainerWithImageSource:imageSource];
    }
    return nil;
}

@end

@implementation TIPJPEGCGImageSourceDecoder

- (instancetype)init
{
    return [self initWithUTType:(NSString *)kUTTypeJPEG];
}

- (id<TIPImageDecoderContext>)tip_initiateDecoding:(nullable id __unused)config expectedDataLength:(NSUInteger)expectedDataLength buffer:(nullable NSMutableData *)buffer
{
    return [[TIPJPEGCGImageSourceDecoderContext alloc] initWithUTType:self.UTType expectedDataLength:expectedDataLength buffer:buffer supportsProgressiveLoading:[self tip_supportsProgressiveDecoding]];
}

- (BOOL)tip_supportsProgressiveDecoding
{
    return (&kCGImageDestinationEmbedThumbnail != NULL); // iOS 8+ only;
}

@end

@implementation TIPAnimatedCGImageSourceDecoder

- (id<TIPImageDecoderContext>)tip_initiateDecoding:(nullable id __unused)config expectedDataLength:(NSUInteger)expectedDataLength buffer:(nullable NSMutableData *)buffer
{
    return [[TIPCGImageSourceDecoderContext alloc] initWithUTType:self.UTType expectedDataLength:expectedDataLength buffer:buffer potentiallyAnimated:YES];
}

@end

@implementation TIPBasicCGImageSourceEncoder

- (instancetype)initWithUTType:(NSString *)UTType
{
    if (self = [super init]) {
        _UTType = [UTType copy];
    }
    return self;
}

- (nullable NSData *)tip_writeDataWithImage:(TIPImageContainer *)image
                            encodingOptions:(TIPImageEncodingOptions)encodingOptions
                           suggestedQuality:(float)quality
                                      error:(out NSError * __autoreleasing __nullable * __nullable)error
{
    return [image.image tip_writeToDataWithType:TIPImageTypeFromUTType(_UTType) encodingOptions:encodingOptions quality:quality animationLoopCount:image.loopCount animationFrameDurations:image.frameDurations error:error];
}

- (BOOL)tip_writeToFile:(NSString *)filePath
              withImage:(TIPImageContainer *)image
        encodingOptions:(TIPImageEncodingOptions)encodingOptions
       suggestedQuality:(float)quality
             atomically:(BOOL)atomic
                  error:(out NSError * __autoreleasing __nullable * __nullable)error
{
    return [image.image tip_writeToFile:filePath type:TIPImageTypeFromUTType(_UTType) encodingOptions:encodingOptions quality:quality animationLoopCount:image.loopCount animationFrameDurations:image.frameDurations atomically:atomic error:error];
}

@end

@implementation TIPCGImageSourceDecoderContext
{
    NSUInteger _expectedDataLength;
    CGImageSourceRef _imageSourceRef;
    NSString *_UTType;
    NSError *_handledError;

    // Flags
    struct {
        BOOL isPotentiallyProgressive:1;
        BOOL isPotentiallyAnimated:1;

        BOOL didCheckType:1;
        BOOL didDetectProperties:1;
        BOOL didFinishLoadingContextualHeaders:1;
        BOOL didMakeFinalUpdate:1;
        BOOL didCompleteLoading:1;
    } _flags;

    // Cache
    TIPImageContainer * _cachedImageContainer;
    TIPImageDecoderRenderMode _cachedImageRenderMode;
    NSUInteger _cachedImageByteCount;
}

@synthesize tip_hasAlpha = _tip_hasAlpha;
@synthesize tip_dimensions = _tip_dimensions;
@synthesize tip_isAnimated = _tip_isAnimated;
@synthesize tip_hasGPSInfo = _tip_hasGPSInfo;

@synthesize tip_data = _data;
@synthesize tip_frameCount = _frameCount;
@synthesize tip_isProgressive = _progressive;

- (nullable id)tip_config
{
    return nil;
}

- (instancetype)initWithUTType:(NSString *)UTType expectedDataLength:(NSUInteger)expectedDataLength buffer:(NSMutableData *)buffer
{
    if (self = [super init]) {
        _expectedDataLength = expectedDataLength;
        _UTType = [UTType copy];
        _data = buffer;
    }
    return self;
}

- (instancetype)initWithUTType:(NSString *)UTType expectedDataLength:(NSUInteger)expectedDataLength buffer:(NSMutableData *)buffer supportsProgressiveLoading:(BOOL)supportsProgressive
{
    if (self = [self initWithUTType:UTType expectedDataLength:expectedDataLength buffer:buffer]) {
        _flags.isPotentiallyProgressive = !!supportsProgressive;
    }
    return self;
}

- (instancetype)initWithUTType:(NSString *)UTType expectedDataLength:(NSUInteger)expectedDataLength buffer:(NSMutableData *)buffer potentiallyAnimated:(BOOL)animated
{
    if (self = [self initWithUTType:UTType expectedDataLength:expectedDataLength buffer:buffer]) {
        _flags.isPotentiallyAnimated = !!animated;
    }
    return self;
}

- (void)dealloc
{
    if (_imageSourceRef) {
        CFRelease(_imageSourceRef);
    }
}

- (TIPImageDecoderAppendResult)appendData:(NSData *)data
{
    return [self _tip_appendData:data complete:NO];
}

- (nullable TIPImageContainer *)renderImage:(TIPImageDecoderRenderMode)mode
{
    TIPImageContainer *imageContainer = nil;

    if (_flags.didCompleteLoading) {
        mode = TIPImageDecoderRenderModeCompleteImage;
    }
    imageContainer = [self _tip_cachedImageWithMode:mode];

    if (!imageContainer) {
        NSData *chunk = [self _tip_extractChunkWithMode:mode];
        imageContainer = [self _tip_generateImageWithChunk:chunk complete:(TIPImageDecoderRenderModeCompleteImage == mode)];
        [self _tip_cacheImage:imageContainer mode:mode];
    }

    return imageContainer;
}

- (TIPImageDecoderAppendResult)finalizeDecoding
{
    return [self _tip_appendData:nil complete:YES];
}

#pragma mark - Private

- (void)_tip_cacheImage:(nullable TIPImageContainer *)imageContainer mode:(TIPImageDecoderRenderMode)mode
{
    if (!imageContainer) {
        return;
    }

    if (mode >= TIPImageDecoderRenderModeFullFrameProgress || !_cachedImageContainer) {
        _cachedImageContainer = imageContainer;
        _cachedImageByteCount = _data.length;
        _cachedImageRenderMode = mode;
    }
}

- (nullable TIPImageContainer *)_tip_cachedImageWithMode:(TIPImageDecoderRenderMode)mode
{
    TIPImageContainer *imageContainer = nil;
    if (_cachedImageContainer) {
        if (TIPImageDecoderRenderModeCompleteImage == _cachedImageRenderMode) {
            imageContainer = _cachedImageContainer;
        } else if (_cachedImageRenderMode == mode) {
            if (_tip_isAnimated) {
                if (!_flags.didCompleteLoading) {
                    imageContainer = _cachedImageContainer;
                }
            } else {
                if (TIPImageDecoderRenderModeFullFrameProgress == mode) {
                    if (_frameCount == _cachedImageContainer.frameCount) {
                        imageContainer = _cachedImageContainer;
                    }
                } else if (TIPImageDecoderRenderModeAnyProgress == mode) {
                    if (_data.length == _cachedImageByteCount) {
                        imageContainer = _cachedImageContainer;
                    }
                } else {
                    TIPAssertNever();
                }
            }
        }
    }

    return imageContainer;
}

- (nullable NSData *)_tip_extractChunkWithMode:(TIPImageDecoderRenderMode)mode
{
    if (_handledError != nil) {
        return nil;
    }

    NSUInteger len = 0;
    switch (mode) {
        case TIPImageDecoderRenderModeAnyProgress:
            len = _data.length;
            break;
        case TIPImageDecoderRenderModeFullFrameProgress:
            if (_tip_isAnimated) {
                len = _data.length;
            } else {
                if (_flags.didCompleteLoading) {
                    len = _data.length;
                } else {
                    len = _lastFrameEndIndex + 1;
                }
            }
            break;
        case TIPImageDecoderRenderModeCompleteImage:
            if (_flags.didCompleteLoading) {
                len = _data.length;
            }
            break;
    }

    if (len) {
        return [_data tip_safeSubdataNoCopyWithRange:NSMakeRange(0, len)];
    }

    return nil;
}

- (nullable TIPImageContainer *)_tip_generateImageWithChunk:(NSData *)chunk complete:(BOOL)complete
{
    if (_handledError != nil) {
        return nil;
    }

    if (chunk.length) {
        if (_tip_isAnimated) {
            const size_t count = CGImageSourceGetCount(_imageSourceRef);

            if (0 == count) {
                // no frames
                return nil;
            } else if (1 == count) {
                // animated image with 1 frame... needs extra handling
                if (CGImageSourceGetStatusAtIndex(_imageSourceRef, 0) != kCGImageStatusComplete) {
                    // didn't have the subframe status, but could still be a finished image
                    if (!complete || CGImageSourceGetStatus(_imageSourceRef) != kCGImageStatusComplete) {
                        // really don't have the image
                        return nil;
                    }
                }
            } else if (CGImageSourceGetStatusAtIndex(_imageSourceRef, 0) != kCGImageStatusComplete) {
                // not enough data to render any frames of an animated image
                return nil;
            }

            if (!complete) {
                // just want the first frame
                CGImageRef cgImage = CGImageSourceCreateImageAtIndex(_imageSourceRef, 0, NULL);
                TIPDeferRelease(cgImage);
                UIImage *image = (cgImage) ? [UIImage imageWithCGImage:cgImage scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp] : nil;
                return (image) ? [[TIPImageContainer alloc] initWithImage:image] : nil;
            }
        } else {
            // Animated always updates the source as data flows in,
            // so only update the source for progressive/normal
            [self _tip_updateImageSourceData:chunk complete:complete];
        }

        // Get what we have (all frames for animated image, all bytes in the "chunk" for non-animated)
        return [TIPImageContainer imageContainerWithImageSource:_imageSourceRef];
    }

    return nil;
}

- (void)_tip_appendPrep
{
    // Prep data
    if (!_data) {
        _data = (_expectedDataLength) ? [NSMutableData dataWithCapacity:_expectedDataLength] : [NSMutableData data];
    }

    // Prep the source
    if (!_imageSourceRef) {
        NSDictionary *options = @{ (NSString *)kCGImageSourceShouldCache : @NO };
        _imageSourceRef = CGImageSourceCreateIncremental((__bridge CFDictionaryRef)options);
        TIPAssert(_imageSourceRef);
    }
}

- (TIPImageDecoderAppendResult)_tip_appendData:(nullable NSData *)data complete:(BOOL)complete
{
    // Check state
    if (_flags.didCompleteLoading) {
        return TIPImageDecoderAppendResultDidCompleteLoading;
    }

    // Prep
    [self _tip_appendPrep];
    TIPImageDecoderAppendResult result = TIPImageDecoderAppendResultDidProgress;

    // Update our data
    if (data) {
        [_data appendData:data];
    }

    if (!_handledError) {
        @try {
            // Read headers if needed
            if (!_flags.didFinishLoadingContextualHeaders) {
                [self _tip_attemptToReadHeadersWithResult:&result complete:complete];
            }

            // Read image if possible
            if (_flags.didFinishLoadingContextualHeaders) {
                [self _tip_attemptToLoadMoreImageWithResult:&result complete:complete];
            }
        } @catch (NSException *exception) {
            _handledError = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINTR userInfo:@{ @"exception" : exception }];
        }
    }

    if (_handledError && complete && !_flags.didCompleteLoading) {

        // Ugh... ImageIO can crash with some malformed image data.
        // If an exception was thrown (vs a signal) we can handle it.
        // Handle it by only doing any work on "final" in order to
        // generate the final image without any progressive loading
        // or property detection.

        UIImage *image = [UIImage imageWithData:_data];
        if (image) {
            result = TIPImageDecoderAppendResultDidCompleteLoading;
            _flags.didCompleteLoading = 1;
            TIPImageContainer *imageContainer = [[TIPImageContainer alloc] initWithImage:image];
            if (imageContainer) {
                _progressive = NO;
                [self _tip_cacheImage:imageContainer mode:TIPImageDecoderRenderModeCompleteImage];
            }
        }
    }

    return result;
}

- (void)_tip_attemptToLoadMoreImageWithResult:(inout TIPImageDecoderAppendResult *)result complete:(BOOL)complete
{
    const NSUInteger lastFrameCount = _frameCount;
    if (_tip_isAnimated) {
        [self _tip_updateImageSourceData:_data complete:complete];
        BOOL canUpdateFrameCount;
        if (@available(iOS 11.0, *)) {
            // We want to avoid decoding the animation data here in case it conflicts with
            // the data already being decoded in the UI.
            // On iOS 10, concurrent decoding of the same image (triggered by
            // CGImageSourceGetCount and a UIImageView displaying the same image data)
            // easily leads to crashes.
            canUpdateFrameCount = YES;
        } else {
            canUpdateFrameCount = complete;
        }
        if (canUpdateFrameCount) {
            _frameCount = CGImageSourceGetCount(_imageSourceRef);
        }
    } else {
        [self readMore:complete];
    }

    if (lastFrameCount != _frameCount || complete) {
        *result = (complete) ? TIPImageDecoderAppendResultDidCompleteLoading : TIPImageDecoderAppendResultDidLoadFrame;
    }

    if (complete) {
        _flags.didCompleteLoading = YES;
    }
}

- (void)_tip_attemptToReadHeadersWithResult:(inout TIPImageDecoderAppendResult *)result complete:(BOOL)complete
{
    [self _tip_updateImageSourceData:_data complete:complete];

    [self _tip_appendCheckType];

    [self _tip_appendAttemptToLoadPropertiesFromHeaders];

    [self _tip_appendAttemptToFinishLoadingContextualHeaders];

    if (_flags.didDetectProperties && _flags.didFinishLoadingContextualHeaders) {
        *result = TIPImageDecoderAppendResultDidLoadHeaders;
    }
}

- (void)_tip_updateImageSourceData:(NSData *)data complete:(BOOL)complete
{
    if (!_flags.didMakeFinalUpdate) {
        CGImageSourceUpdateData(_imageSourceRef, (__bridge CFDataRef)data, complete);
        if (complete) {
            _flags.didMakeFinalUpdate = 1;
        }
    } else {
        TIPLogWarning(@"Called %@ after already finalized!", NSStringFromSelector(_cmd));
    }
}

- (void)_tip_appendCheckType
{
    // Read type
    if (!_flags.didCheckType) {
        CFStringRef imageSourceTypeRef = CGImageSourceGetType(_imageSourceRef);
        if (imageSourceTypeRef) {
            _flags.didCheckType = 1;
            if (!UTTypeConformsTo(imageSourceTypeRef, (__bridge CFStringRef)_UTType)) {
                NSDictionary *userInfo = @{
                                           @"decoder" : _UTType,
                                           @"data" : (__bridge NSString *)imageSourceTypeRef
                                           };
                @throw [NSException exceptionWithName:NSGenericException reason:@"Decoder image type mismatch!" userInfo:userInfo];
            }
        }
    }
}

- (void)_tip_appendAttemptToLoadPropertiesFromHeaders
{
    // Read properties (if possible)
    if (_flags.didCheckType && !_flags.didDetectProperties) {

        // Check the status first

        const CGImageSourceStatus status = CGImageSourceGetStatus(_imageSourceRef);

        switch (status) {
            case kCGImageStatusUnexpectedEOF:
                // something's wrong
                _flags.didDetectProperties = YES;
                return;
            case kCGImageStatusInvalidData:
                // gonna fail no matter what
                _flags.didDetectProperties = YES;
                return;
            case kCGImageStatusComplete:
            case kCGImageStatusIncomplete:
                // we've got headers!  fall through to read them
                break;
            case kCGImageStatusUnknownType:
            case kCGImageStatusReadingHeader:
                // need more bytes
                return;
            default:
                // unexpected...keep reading more bytes
                return;
        }

        // Looks like we have headers, take a peek

        CFDictionaryRef imageProperties = CGImageSourceCopyPropertiesAtIndex(_imageSourceRef, 0, NULL);
        TIPDeferRelease(imageProperties);
        if (imageProperties != NULL && CFDictionaryGetCount(imageProperties) > 0) {

            // Size

            CFNumberRef widthNum  = CFDictionaryGetValue(imageProperties, kCGImagePropertyPixelWidth);
            CFNumberRef heightNum = CFDictionaryGetValue(imageProperties, kCGImagePropertyPixelHeight);

            if (widthNum && heightNum) {
                _tip_dimensions = CGSizeMake([(__bridge NSNumber *)widthNum floatValue], [(__bridge NSNumber *)heightNum floatValue]);
            }

            // Alpha

            // The "has alpha" property of a JPEG can incorrectly report "YES"
            // This check ensures we don't get the "has alpha" for JPEGs
            if (![_UTType isEqualToString:(NSString *)kUTTypeJPEG]) {
                CFBooleanRef hasAlphaBool = CFDictionaryGetValue(imageProperties, kCGImagePropertyHasAlpha) ?: kCFBooleanFalse;
                _tip_hasAlpha = !!CFBooleanGetValue(hasAlphaBool);
            }

            // Progressive

            if (_flags.isPotentiallyProgressive) {
                if ([_UTType isEqualToString:(NSString *)kUTTypeJPEG]) {
                    CFDictionaryRef jfifProperties = CFDictionaryGetValue(imageProperties, kCGImagePropertyJFIFDictionary);
                    if (jfifProperties) {
                        CFBooleanRef isProgressiveBool = CFDictionaryGetValue(jfifProperties, kCGImagePropertyJFIFIsProgressive) ?: kCFBooleanFalse;
                        _progressive = !!CFBooleanGetValue(isProgressiveBool);
                    }
                }
            }

            // Animated

            if (!_progressive && _flags.isPotentiallyAnimated) {
                if ([_UTType isEqualToString:(NSString *)kUTTypeGIF]) {
                    CFDictionaryRef gifProperties = CFDictionaryGetValue(imageProperties, kCGImagePropertyGIFDictionary);
                    if (gifProperties) {
                        _tip_isAnimated = YES;
                    }
                } else if ([_UTType isEqualToString:(NSString *)kUTTypePNG]) {
                    CFDictionaryRef pngProperties = CFDictionaryGetValue(imageProperties, kCGImagePropertyPNGDictionary);
                    if (pngProperties && [[NSProcessInfo processInfo] respondsToSelector:@selector(operatingSystemVersion)] /* iOS 8+ */) {
                        if (CFDictionaryGetValue(pngProperties, kCGImagePropertyAPNGDelayTime) != NULL) {
                            _tip_isAnimated = YES;
                        }
                    }
                }
            }

            // GPS Info
            CFDictionaryRef gpsInfo = CFDictionaryGetValue(imageProperties, kCGImagePropertyGPSDictionary);
            if (gpsInfo != NULL && CFDictionaryGetCount(gpsInfo) > 0) {
                _tip_hasGPSInfo = YES;
            }

            _flags.didDetectProperties = YES;
        }
    }
}

- (void)_tip_appendAttemptToFinishLoadingContextualHeaders
{
    if (_flags.didDetectProperties && !_flags.didFinishLoadingContextualHeaders) {
        _flags.didFinishLoadingContextualHeaders = !![self readContextualHeaders];
    }
}

@end

@implementation TIPCGImageSourceDecoderContext (Protected)

- (BOOL)readContextualHeaders
{
    return YES;
}

- (BOOL)readMore:(BOOL)complete
{
    _lastByteReadIndex = _data.length - 1;
    _lastSafeByteIndex = _lastByteReadIndex;

    if (complete) {
        _frameCount++;
        return YES;
    }

    return NO;
}

@end

@implementation TIPJPEGCGImageSourceDecoderContext
{
    BOOL _lastByteWasEscapeMarker;
}

- (BOOL)readContextualHeaders
{
    return YES;
}

- (BOOL)readMore:(BOOL)complete
{
    // Detect boundaries of "frames"

    NSData *data = _data;
    const NSUInteger oldFrameCount = _frameCount;

    NSUInteger lastByteReadIndex = _lastByteReadIndex;
    NSData *subdata = [data subdataWithRange:NSMakeRange(lastByteReadIndex, data.length - lastByteReadIndex)];
    [subdata enumerateByteRangesUsingBlock:^(const void * __nonnull rawBytes, NSRange byteRange, BOOL * __nonnull stop) {
        byteRange.location += lastByteReadIndex;
        [self _tip_readMoreBytes:rawBytes range:byteRange];
    }];

    // If we've reached the end but didn't complete our frame, complete it now
    if (complete && (_lastFrameEndIndex < _lastFrameStartIndex)) {
        _frameCount++;
    }

    // Update our last safe byte
    _lastSafeByteIndex = _lastByteReadIndex;

    return oldFrameCount != _frameCount;
}

- (void)_tip_readMoreBytes:(const unsigned char *)bytes range:(NSRange)byteRange
{
    const NSUInteger limitIndex = byteRange.location + byteRange.length;

    if (_lastByteReadIndex >= limitIndex) {
        // already read these bytes
        return;
    }

    // Iterate through bytes from our last progress to as many bytes as we have
    for (const unsigned char *endBytes = bytes + byteRange.length; bytes < endBytes; bytes++) {
        if (_lastByteWasEscapeMarker) {
            _lastByteWasEscapeMarker = 0;
            if (*bytes == kJPEG_MARKER_START_FRAME) {

                // OK, did we get a full frame of bytes?
                if (_lastFrameStartIndex > _lastFrameEndIndex) {
                    _lastFrameEndIndex = _lastByteReadIndex - 2;

                    // This was a new frame, increment
                    _frameCount++;
                }

                _lastFrameStartIndex = _lastByteReadIndex - 1;

            }
        } else if (*bytes == kJPEG_MARKER_SPECIAL_BYTE) {
            _lastByteWasEscapeMarker = 1;
        }
        _lastByteReadIndex++;
    }
}

@end

NS_ASSUME_NONNULL_END
