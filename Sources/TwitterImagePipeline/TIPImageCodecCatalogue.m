//
//  TIPImageCodecCatalogue.m
//  TwitterImagePipeline
//
//  Created on 11/9/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPDefaultImageCodecs.h"
#import "TIPError.h"
#import "TIPGlobalConfiguration.h"
#import "TIPImageCodecCatalogue.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TIPImageCodecCatalogue
{
    dispatch_queue_t _codecQueue;
    NSMutableDictionary<NSString *, id<TIPImageCodec>> *_codecs;
}

+ (NSDictionary<NSString *, id<TIPImageCodec>> *)defaultCodecs
{
    static NSDictionary<NSString *, id<TIPImageCodec>> *sDefaultsCodecs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSString *, id<TIPImageCodec>> *codecs = [NSMutableDictionary dictionary];
        NSArray<NSString *> *knownImageTypes = @[
                                                 TIPImageTypeJPEG,
                                                 TIPImageTypeJPEG2000,
                                                 TIPImageTypePNG,
                                                 TIPImageTypeGIF,
                                                 TIPImageTypeTIFF,
                                                 TIPImageTypeBMP,
                                                 TIPImageTypeTARGA,
                                                 TIPImageTypePICT,
                                                 TIPImageTypeQTIF,
                                                 TIPImageTypeICNS,
                                                 TIPImageTypeICO,
                                                 TIPImageTypeRAW,
                                                 TIPImageTypeHEIC,
                                                 TIPImageTypeAVCI,
                                                 TIPImageTypeWEBP,
                                                 ];
        for (NSString *imageType in knownImageTypes) {
            id<TIPImageCodec> codec = [TIPBasicCGImageSourceCodec codecWithImageType:imageType];
            if (codec) {
                codecs[imageType] = codec;
            }
        }
        sDefaultsCodecs = [codecs copy];
    });

    return sDefaultsCodecs;
}

+ (instancetype)sharedInstance
{
    static TIPImageCodecCatalogue *sCatalogue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const BOOL loadAsync = [TIPGlobalConfiguration sharedInstance].loadCodecsAsync;
        if (loadAsync) {
            sCatalogue = [[TIPImageCodecCatalogue alloc] initWithCodecsProvider:^NSDictionary<NSString *,id<TIPImageCodec>> * _Nullable{
                return [self defaultCodecs];
            }];
        } else {
            sCatalogue = [[TIPImageCodecCatalogue alloc] initWithCodecs:[self defaultCodecs]];
        }
    });
    return sCatalogue;
}

- (instancetype)init
{
    return [self initWithCodecs:nil];
}

- (instancetype)initWithCodecsProvider:(TIPImageCodecCatalogueCodecsProvider)codecProvider
{
    if (self = [super init]) {
        _codecQueue = dispatch_queue_create("TIPImageCodecCatalogue.queue", DISPATCH_QUEUE_CONCURRENT);
        dispatch_barrier_async(_codecQueue, ^{
            self->_codecs = [NSMutableDictionary dictionaryWithDictionary:codecProvider()];
        });
    }
    return self;
}

- (instancetype)initWithCodecs:(nullable NSDictionary<NSString *,id<TIPImageCodec>> *)codecs
{
    if (self = [super init]) {
        _codecQueue = dispatch_queue_create("TIPImageCodecCatalogue.queue", DISPATCH_QUEUE_CONCURRENT);
        _codecs = [NSMutableDictionary dictionaryWithDictionary:codecs];
    }
    return self;
}

- (NSDictionary<NSString *, id<TIPImageCodec>> *)allCodecs
{
    __block NSDictionary<NSString *, id<TIPImageCodec>> * allCodecs;
    dispatch_sync(_codecQueue, ^{
        allCodecs = [self->_codecs copy];
    });
    return allCodecs;
}

- (void)removeCodecForImageType:(NSString *)imageType
{
    [self removeCodecForImageType:imageType removedCodec:NULL];
}

- (void)removeCodecForImageType:(NSString *)imageType
                   removedCodec:(id<TIPImageCodec> __autoreleasing *)codec
{
    if (codec) {
        dispatch_barrier_sync(_codecQueue, ^{
            *codec = self->_codecs[imageType];
            [self->_codecs removeObjectForKey:imageType];
        });
    } else {
        tip_dispatch_barrier_async_autoreleasing(_codecQueue, ^{
            [self->_codecs removeObjectForKey:imageType];
        });
    }
}

- (void)setCodec:(id<TIPImageCodec>)codec forImageType:(NSString *)imageType
{
    tip_dispatch_barrier_async_autoreleasing(_codecQueue, ^{
        self->_codecs[imageType] = codec;
    });
}

- (void)replaceCodecForImageType:(NSString *)imageType usingBlock:(id<TIPImageCodec> (^)(id<TIPImageCodec> _Nullable existingCodec))replacementBlock
{
    tip_dispatch_barrier_async_autoreleasing(_codecQueue, ^{
        id<TIPImageCodec> replacementCodec = replacementBlock(self->_codecs[imageType]);
        if (replacementCodec != nil) {
            self->_codecs[imageType] = replacementCodec;
        }
    });
}

- (nullable id<TIPImageCodec>)codecForImageType:(NSString *)imageType
{
    __block id<TIPImageCodec> codec;
    dispatch_sync(_codecQueue, ^{
        codec = self->_codecs[imageType];
    });
    return codec;
}

@end

@implementation TIPImageCodecCatalogue (KeyedSubscripting)

- (void)setObject:(nullable id<TIPImageCodec>)codec forKeyedSubscript:(NSString *)imageType
{
    if (codec) {
        [self setCodec:codec forImageType:imageType];
    } else {
        [self removeCodecForImageType:imageType];
    }
}

- (nullable id<TIPImageCodec>)objectForKeyedSubscript:(NSString *)imageType
{
    return [self codecForImageType:imageType];
}

@end

@implementation TIPImageCodecCatalogue (Convenience)

- (BOOL)codecWithImageTypeSupportsProgressiveLoading:(nullable NSString *)type
{
    return TIP_BITMASK_HAS_SUBSET_FLAGS([self propertiesForCodecWithImageType:type], TIPImageCodecSupportsProgressiveLoading);
}

- (BOOL)codecWithImageTypeSupportsAnimation:(nullable NSString *)type
{
    return TIP_BITMASK_HAS_SUBSET_FLAGS([self propertiesForCodecWithImageType:type], TIPImageCodecSupportsAnimation);
}

- (BOOL)codecWithImageTypeSupportsDecoding:(nullable NSString *)type
{
    return TIP_BITMASK_HAS_SUBSET_FLAGS([self propertiesForCodecWithImageType:type], TIPImageCodecSupportsDecoding);
}

- (BOOL)codecWithImageTypeSupportsEncoding:(nullable NSString *)type
{
    return TIP_BITMASK_HAS_SUBSET_FLAGS([self propertiesForCodecWithImageType:type], TIPImageCodecSupportsEncoding);
}

- (TIPImageCodecProperties)propertiesForCodecWithImageType:(nullable NSString *)type
{
    __block id<TIPImageCodec> codec = nil;
    if (type) {
        dispatch_sync(_codecQueue, ^{
            codec = self->_codecs[type];
        });
    }

    TIPImageCodecProperties properties = 0;
    if (codec) {
        properties |= TIPImageCodecSupportsDecoding;
        id<TIPImageDecoder> decoder = [codec tip_decoder];
        id<TIPImageEncoder> encoder = [codec tip_encoder];
        if (encoder) {
            properties |= TIPImageCodecSupportsEncoding;
        }
        if ([decoder respondsToSelector:@selector(tip_supportsProgressiveDecoding)] && [decoder tip_supportsProgressiveDecoding]) {
            properties |= TIPImageCodecSupportsProgressiveLoading;
        }
        if ([codec respondsToSelector:@selector(tip_isAnimated)] && [codec tip_isAnimated]) {
            properties |= TIPImageCodecSupportsAnimation;
        }
    }

    return properties;
}

- (nullable TIPImageContainer *)decodeImageWithData:(NSData *)data
                                   targetDimensions:(CGSize)targetDimensions
                                  targetContentMode:(UIViewContentMode)targetContentMode
                                   decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
                                          imageType:(out NSString * __autoreleasing __nullable * __nullable)imageType
{
    __block NSString *localImageType = nil;
    tip_defer(^{
        if (imageType) {
            *imageType = localImageType;
        }
    });
    __block TIPImageContainer *container = nil;
    NSDictionary<NSString *, id<TIPImageCodec>> *codecs = self.allCodecs;
    NSString *guessImageType = TIPDetectImageTypeViaMagicNumbers(data);
    if (!guessImageType) {
        guessImageType = TIPDetectImageType(data, NULL, NULL, YES);
    }
    id<TIPImageCodec> guessedCodec = (guessImageType) ? codecs[guessImageType] : nil;
    if (guessedCodec) {
        id config = decoderConfigMap[guessImageType];
        container = TIPDecodeImageFromData(guessedCodec, config, data, targetDimensions, targetContentMode, guessImageType);
        if (container) {
            localImageType = guessImageType;
            return container;
        }
    }

    [codecs enumerateKeysAndObjectsUsingBlock:^(NSString *codecImageType, id<TIPImageCodec> codec, BOOL *stop) {
        if (codec != guessedCodec) {
            id config = decoderConfigMap[codecImageType];
            container = TIPDecodeImageFromData(codec, config, data, targetDimensions, targetContentMode, guessImageType);
            if (container) {
                *stop = YES;
                localImageType = codecImageType;
            }
        }
    }];

    return container;
}

- (BOOL)encodeImage:(TIPImageContainer *)image
         toFilePath:(NSString *)filePath
      withImageType:(NSString *)imageType
            quality:(float)quality
            options:(TIPImageEncodingOptions)options
             atomic:(BOOL)atomic
              error:(out NSError **)error
{
    id<TIPImageCodec> codec = [self codecForImageType:imageType];
    id<TIPImageEncoder> encoder = codec.tip_encoder;
    if (!encoder) {
        if (error) {
            *error = [NSError errorWithDomain:TIPErrorDomain
                                         code:TIPErrorCodeEncodingUnsupported
                                     userInfo:(imageType) ? @{ @"imageType" : imageType } : nil];
        }
        return NO;
    }

    return TIPEncodeImageToFile(codec, image, filePath, options, quality, atomic, error);
}

- (nullable NSData *)encodeImage:(TIPImageContainer *)image
                   withImageType:(NSString *)imageType
                         quality:(float)quality
                         options:(TIPImageEncodingOptions)options
                           error:(out NSError * __autoreleasing __nullable * __nullable)error
{
    NSData *data = nil;
    id<TIPImageCodec> codec = [self codecForImageType:imageType];
    id<TIPImageEncoder> encoder = [codec tip_encoder];
    if (!encoder) {
        if (error) {
            *error = [NSError errorWithDomain:TIPErrorDomain
                                         code:TIPErrorCodeEncodingUnsupported
                                     userInfo:(imageType) ? @{ @"imageType" : imageType } : nil];
        }
    } else {
        data = [encoder tip_writeDataWithImage:image
                               encodingOptions:options
                              suggestedQuality:quality
                                         error:error];
    }
    return data;
}

@end

NS_ASSUME_NONNULL_END
