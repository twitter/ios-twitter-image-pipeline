//
//  TIPPartialImage.m
//  TwitterImagePipeline
//
//  Created on 3/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPImageCodecCatalogue.h"
#import "TIPPartialImage.h"

NS_ASSUME_NONNULL_BEGIN

// Primary class gets the SELF_ARG convenience
#define SELF_ARG PRIVATE_SELF(TIPPartialImage)

@interface TIPPartialImageCodecDetector : NSObject
@property (nullable, nonatomic, readonly) NSMutableData *codecDetectionBuffer;
@property (nullable, nonatomic, readonly) id<TIPImageCodec> detectedCodec;
@property (nullable, nonatomic, readonly, copy) NSString *detectedImageType;
- (instancetype)initWithExpectedDataLength:(NSUInteger)expectedDataLength;
- (BOOL)appendData:(NSData *)data final:(BOOL)final;
@end

static const float kUnfinishedImageProgressCap = 0.999f;

@interface TIPPartialImage ()
@property (atomic, readwrite) TIPPartialImageState state;
@end

@implementation TIPPartialImage
{
    TIPPartialImageCodecDetector *_codecDetector;
    id<TIPImageCodec> _codec;
    id<TIPImageDecoder> _decoder;
    id<TIPImageDecoderContext> _decoderContext;
    NSDictionary<NSString *, id> *_decoderConfigMap;
    dispatch_queue_t _renderQueue;
}

// the following getters may appear superfluous, and would be, if it weren't for the need to
// annotate them with __attribute__((no_sanitize("thread")).  the getters make the @synthesize
// lines necessary.
//
// the reason these are thread safe is that the ivars are assigned/mutated in
// _tip_extractState, which is only ever called from within _tip_appendData:
// within a dispatch_sync{_renderQueue, ^{...}),  making their access thread safe via nonatomic.

@synthesize byteCount = _byteCount;
@synthesize dimensions = _dimensions;
@synthesize frameCount = _frameCount;

@synthesize hasAlpha = _hasAlpha;
@synthesize animated = _animated;
@synthesize progressive = _progressive;

- (NSUInteger)byteCount TIP_THREAD_SANITIZER_DISABLED
{
    return _byteCount;
}

- (CGSize)dimensions TIP_THREAD_SANITIZER_DISABLED
{
    return _dimensions;
}

- (NSUInteger)frameCount TIP_THREAD_SANITIZER_DISABLED
{
    return _frameCount;
}

- (BOOL)hasAlpha TIP_THREAD_SANITIZER_DISABLED
{
    return _hasAlpha;
}

- (BOOL)isAnimated TIP_THREAD_SANITIZER_DISABLED
{
    return _animated;
}

- (BOOL)isProgressive TIP_THREAD_SANITIZER_DISABLED
{
    return _progressive;
}

- (nullable NSData *)data
{
    __block NSData *data = nil;
    dispatch_sync(_renderQueue, ^{
        data = self->_decoderContext.tip_data;
    });
    return data;
}

- (instancetype)initWithExpectedContentLength:(NSUInteger)contentLength
{
    if (self = [super init]) {
        _expectedContentLength = contentLength;
        _renderQueue = dispatch_queue_create("com.twitter.tip.partial.image.render.queue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (float)progress
{
    if (!_expectedContentLength) {
        return 0.0f;
    }

    const float progress = MIN(kUnfinishedImageProgressCap, (float)((double)self.byteCount / (double)_expectedContentLength));
    return progress;
}

- (void)updateDecoderConfigMap:(nullable NSDictionary<NSString *, id> *)configMap
{
    tip_dispatch_async_autoreleasing(_renderQueue, ^{
        self->_decoderConfigMap = [configMap copy];
    });
}

- (TIPImageDecoderAppendResult)appendData:(nullable NSData *)data final:(BOOL)final
{
    __block TIPImageDecoderAppendResult result = TIPImageDecoderAppendResultDidProgress;

    tip_dispatch_sync_autoreleasing(_renderQueue, ^{
        result = _appendData(self, data, final);
    });

    return result;
}

- (nullable TIPImageContainer *)renderImageWithMode:(TIPImageDecoderRenderMode)mode decoded:(BOOL)decode
{
    __block TIPImageContainer *image = nil;

    tip_dispatch_sync_autoreleasing(_renderQueue, ^{
        image = [self->_decoder tip_renderImage:self->_decoderContext mode:mode];
        if (image && decode) {
            [image decode];
        }
    });

    return image;
}

#pragma mark Private

static BOOL _detectCodec(SELF_ARG,
                         NSData *data,
                         BOOL final)
{
    if (!self) {
        return NO;
    }

    if (!self->_codec) {
        if (!self->_codecDetector) {
            self->_codecDetector = [[TIPPartialImageCodecDetector alloc] initWithExpectedDataLength:self->_expectedContentLength];
        }

        if ([self->_codecDetector appendData:data final:final]) {
            self->_type = self->_codecDetector.detectedImageType;
            self->_codec = self->_codecDetector.detectedCodec;
            self->_decoder = self->_codec.tip_decoder;
            NSMutableData *buffer = self->_codecDetector.codecDetectionBuffer;
            if (buffer.length == 0) {
                buffer = [NSMutableData dataWithCapacity:self->_expectedContentLength];
                [buffer appendData:data];
            }
            id config = self->_decoderConfigMap[self->_type];
            self->_decoderContext = [self->_decoder tip_initiateDecoding:config
                                                      expectedDataLength:self->_expectedContentLength
                                                                  buffer:buffer];
            self->_codecDetector = nil;
            return YES;
        }
    }

    return NO;
}

static TIPImageDecoderAppendResult _appendData(SELF_ARG,
                                               NSData *data,
                                               BOOL final)
{
    if (!self) {
        return 0;
    }

    if (TIPPartialImageStateComplete == self.state) {
        return TIPImageDecoderAppendResultDidCompleteLoading;
    }

    TIPImageDecoderAppendResult result = TIPImageDecoderAppendResultDidProgress;
    if (!self->_codec) {
        if (_detectCodec(self, data, final)) {
            // We want our append to be unified below
            // but at this point we'll have prepopulated the buffer.
            // Change "data" to be 0 bytes so that we can keep our logic
            // without doubling the data that's being appended :)
            data = [NSData data];
        }
    }

    if (self->_decoder) {
        result = [self->_decoder tip_append:self->_decoderContext data:data];
        if (final) {
            if ([self->_decoder tip_finalizeDecoding:self->_decoderContext] == TIPImageDecoderAppendResultDidCompleteLoading) {
                result = TIPImageDecoderAppendResultDidCompleteLoading;
            }
        }
        _extractState(self);
    }

    _updateState(self ,result);
    return result;
}

static void _updateState(SELF_ARG,
                         TIPImageDecoderAppendResult latestResult)
{
    if (!self) {
        return;
    }

    switch (latestResult) {
        case TIPImageDecoderAppendResultDidLoadHeaders:
        case TIPImageDecoderAppendResultDidLoadFrame:
            if (self.state <= TIPPartialImageStateLoadingImage) {
                self.state = TIPPartialImageStateLoadingImage;
            }
            break;
        case TIPImageDecoderAppendResultDidCompleteLoading:
            if (self.state <= TIPPartialImageStateComplete) {
                self.state = TIPPartialImageStateComplete;
            }
            break;
        case TIPImageDecoderAppendResultDidProgress:
        default:
            if (self.state <= TIPPartialImageStateLoadingHeaders) {
                self.state = TIPPartialImageStateLoadingHeaders;
            }
            break;
    }
}

static void _extractState(SELF_ARG)
{
    if (!self) {
        return;
    }

    if (self->_decoderContext) {
        self->_byteCount = self->_decoderContext.tip_data.length;
        self->_frameCount = self->_decoderContext.tip_frameCount;
        self->_dimensions = self->_decoderContext.tip_dimensions;
        if ([self->_decoderContext respondsToSelector:@selector(tip_isProgressive)]) {
            self->_progressive = self->_decoderContext.tip_isProgressive;
        }
        if ([self->_decoderContext respondsToSelector:@selector(tip_isAnimated)]) {
            self->_animated = self->_decoderContext.tip_isAnimated;
        }
        if ([self->_decoderContext respondsToSelector:@selector(tip_hasAlpha)]) {
            self->_hasAlpha = self->_decoderContext.tip_hasAlpha;
        }
        if ([self->_decoderContext respondsToSelector:@selector(tip_hasGPSInfo)]) {
            self->_hasGPSInfo = self->_decoderContext.tip_hasGPSInfo;
        }
    }
}

@end

@implementation TIPPartialImageCodecDetector
{
    NSUInteger _expectedDataLength;
    CGImageSourceRef _codecDetectionImageSource;
    NSMutableDictionary<NSString *, id<TIPImageCodec>> *_potentialCodecs;
}

- (instancetype)initWithExpectedDataLength:(NSUInteger)expectedDataLength
{
    if (self = [super init]) {
        _expectedDataLength = expectedDataLength;
    }
    return self;
}

- (BOOL)appendData:(NSData *)data final:(BOOL)final
{
    if (!_codecDetectionImageSource) {
        TIPAssert(!_codecDetectionBuffer);

        if (_quickDetectCodec(self, data)) {
            TIPAssert(_detectedCodec != nil);
            return YES;
        }

        _codecDetectionBuffer = [[NSMutableData alloc] initWithCapacity:_expectedDataLength];

        NSDictionary *options = @{ (NSString *)kCGImageSourceShouldCache : @NO };
        _codecDetectionImageSource = CGImageSourceCreateIncremental((CFDictionaryRef)options);

        _potentialCodecs = [[TIPImageCodecCatalogue sharedInstance].allCodecs mutableCopy];
    }

    if (data) {
        [_codecDetectionBuffer appendData:data];
    }
    CGImageSourceUpdateData(_codecDetectionImageSource, (CFDataRef)_codecDetectionBuffer, final);

    _fullDetectCodec(self);
    return _detectedCodec != nil;
}

- (void)dealloc
{
    if (_codecDetectionImageSource) {
        CFRelease(_codecDetectionImageSource);
    }
}

static BOOL _quickDetectCodec(PRIVATE_SELF(TIPPartialImageCodecDetector),
                              NSData *data)
{
    if (!self) {
        return NO;
    }

    NSString *quickDetectType = TIPDetectImageTypeViaMagicNumbers(data);
    if (quickDetectType) {
        id<TIPImageCodec> quickCodec = [TIPImageCodecCatalogue sharedInstance][quickDetectType];
        if (quickCodec) {
            TIPImageDecoderDetectionResult result = [quickCodec.tip_decoder tip_detectDecodableData:data
                                                                                earlyGuessImageType:quickDetectType];
            if (TIPImageDecoderDetectionResultMatch == result) {
                self->_detectedCodec = quickCodec;
                self->_detectedImageType = [quickDetectType copy];
                return YES;
            }
        }
    }
    return NO;
}

static void _fullDetectCodec(PRIVATE_SELF(TIPPartialImageCodecDetector))
{
    if (!self) {
        return;
    }

    TIPAssert(self->_codecDetectionImageSource != nil);
    if (self->_detectedCodec || self->_potentialCodecs.count == 0) {
        return;
    }

    NSString *detectedImageType = nil;
    NSString *detectedUTType = (NSString *)CGImageSourceGetType(self->_codecDetectionImageSource);
    if (detectedUTType) {
        detectedImageType = TIPImageTypeFromUTType(detectedUTType);
    }

    id<TIPImageCodec> matchingImageTypeCodec = (detectedImageType) ? self->_potentialCodecs[detectedImageType] : nil;
    if (matchingImageTypeCodec) {
        TIPImageDecoderDetectionResult result;
        result = [matchingImageTypeCodec.tip_decoder tip_detectDecodableData:self->_codecDetectionBuffer
                                                         earlyGuessImageType:detectedImageType];
        if (TIPImageDecoderDetectionResultMatch == result) {
            self->_detectedCodec = matchingImageTypeCodec;
            self->_detectedImageType = detectedImageType;
            return;
        } else if (TIPImageDecoderDetectionResultNoMatch == result) {
            [self->_potentialCodecs removeObjectForKey:detectedImageType];
            if (0 == self->_potentialCodecs.count) {
                return;
            }
        }
    }

    NSMutableArray<NSString *> *excludedCodecImageTypes = [[NSMutableArray alloc] initWithCapacity:self->_potentialCodecs.count];
    [self->_potentialCodecs enumerateKeysAndObjectsUsingBlock:^(NSString *imageType, id<TIPImageCodec> codec, BOOL *stop) {
        TIPImageDecoderDetectionResult result;
        result = [codec.tip_decoder tip_detectDecodableData:self->_codecDetectionBuffer
                                        earlyGuessImageType:detectedImageType];
        if (TIPImageDecoderDetectionResultMatch == result) {
            self->_detectedCodec = codec;
            self->_detectedImageType = imageType;
            *stop = YES;
        } else if (TIPImageDecoderDetectionResultNoMatch == result) {
            [excludedCodecImageTypes addObject:imageType];
        }
    }];

    if (!self->_detectedCodec) {
        [self->_potentialCodecs removeObjectsForKeys:excludedCodecImageTypes];
    }
}

@end

NS_ASSUME_NONNULL_END
