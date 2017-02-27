//
//  TIPImageCodecCatalogue.m
//  TwitterImagePipeline
//
//  Created on 11/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPDefaultImageCodecs.h"
#import "TIPError.h"
#import "TIPImageCodecCatalogue.h"

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
                                                 TIPImageTypeRAW
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
        sCatalogue = [[TIPImageCodecCatalogue alloc] initWithCodecs:[self defaultCodecs]];
    });
    return sCatalogue;
}

- (instancetype)init
{
    return [self initWithCodecs:nil];
}

- (instancetype)initWithCodecs:(NSDictionary<NSString *,id<TIPImageCodec>> *)codecs
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

- (void)removeCodecForImageType:(NSString *)imageType removedCodec:(id<TIPImageCodec>  *)codec
{
    if (codec) {
        dispatch_barrier_sync(_codecQueue, ^{
            *codec = self->_codecs[imageType];
            [self->_codecs removeObjectForKey:imageType];
        });
    } else {
        dispatch_barrier_async(_codecQueue, ^{
            [self->_codecs removeObjectForKey:imageType];
        });
    }
}

- (void)setCodec:(id<TIPImageCodec>)codec forImageType:(NSString *)imageType
{
    dispatch_barrier_async(_codecQueue, ^{
        self->_codecs[imageType] = codec;
    });
}

- (id<TIPImageCodec>)codecForImageType:(NSString *)imageType
{
    __block id<TIPImageCodec> codec;
    dispatch_sync(_codecQueue, ^{
        codec = self->_codecs[imageType];
    });
    return codec;
}

@end

@implementation TIPImageCodecCatalogue (KeyedSubscripting)

- (void)setObject:(id<TIPImageCodec>)codec forKeyedSubscript:(NSString *)imageType
{
    if (codec) {
        [self setCodec:codec forImageType:imageType];
    } else {
        [self removeCodecForImageType:imageType];
    }
}

- (id<TIPImageCodec>)objectForKeyedSubscript:(NSString *)imageType
{
    return [self codecForImageType:imageType];
}

@end

@implementation TIPImageCodecCatalogue (Convenience)

- (BOOL)codecWithImageTypeSupportsProgressiveLoading:(NSString *)type
{
    return TIP_BITMASK_HAS_SUBSET_FLAGS([self propertiesForCodecWithImageType:type], TIPImageCodecSupportsProgressiveLoading);
}

- (BOOL)codecWithImageTypeSupportsAnimation:(NSString *)type
{
    return TIP_BITMASK_HAS_SUBSET_FLAGS([self propertiesForCodecWithImageType:type], TIPImageCodecSupportsAnimation);
}

- (BOOL)codecWithImageTypeSupportsDecoding:(NSString *)type
{
    return TIP_BITMASK_HAS_SUBSET_FLAGS([self propertiesForCodecWithImageType:type], TIPImageCodecSupportsDecoding);
}

- (BOOL)codecWithImageTypeSupportsEncoding:(NSString *)type
{
    return TIP_BITMASK_HAS_SUBSET_FLAGS([self propertiesForCodecWithImageType:type], TIPImageCodecSupportsEncoding);
}

- (TIPImageCodecProperties)propertiesForCodecWithImageType:(NSString *)type
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

- (TIPImageContainer *)decodeImageWithData:(NSData *)data imageType:(out NSString **)imageType
{
    __block TIPImageContainer *container = nil;
    NSDictionary<NSString *, id<TIPImageCodec>> *codecs = self.allCodecs;
    NSString *guessImageType = TIPDetectImageTypeViaMagicNumbers(data);
    id<TIPImageCodec> guessedCodec = (guessImageType) ? codecs[guessImageType] : nil;
    if (guessedCodec) {
        container = TIPDecodeImageFromData(guessedCodec, data, guessImageType);
        if (container) {
            if (imageType) {
                *imageType = guessImageType;
            }
            return container;
        }
    }

    [codecs enumerateKeysAndObjectsUsingBlock:^(NSString *codecImageType, id<TIPImageCodec> codec, BOOL *stop) {
        if (codec != guessedCodec) {
            container = TIPDecodeImageFromData(codec, data, guessImageType);
            if (container) {
                *stop = YES;
                if (imageType) {
                    *imageType = codecImageType;
                }
            }
        }
    }];

    return container;
}

- (BOOL)encodeImage:(TIPImageContainer *)image toFilePath:(NSString *)filePath withImageType:(NSString *)imageType quality:(float)quality options:(TIPImageEncodingOptions)options atomic:(BOOL)atomic error:(out NSError **)error
{
    id<TIPImageCodec> codec = [self codecForImageType:imageType];
    id<TIPImageEncoder> encoder = codec.tip_encoder;
    if (!encoder) {
        if (error) {
            *error = [NSError errorWithDomain:TIPErrorDomain code:TIPErrorCodeEncodingUnsupported userInfo:(imageType) ? @{ @"imageType" : imageType } : nil];
        }
        return NO;
    }

    return TIPEncodeImageToFile(codec, image, filePath, options, quality, atomic, error);
}

- (NSData *)encodeImage:(TIPImageContainer *)image withImageType:(NSString *)imageType quality:(float)quality options:(TIPImageEncodingOptions)options error:(out NSError **)error
{
    NSData *data = nil;
    id<TIPImageCodec> codec = [self codecForImageType:imageType];
    id<TIPImageEncoder> encoder = [codec tip_encoder];
    if (!encoder) {
        if (error) {
            *error = [NSError errorWithDomain:TIPErrorDomain code:TIPErrorCodeEncodingUnsupported userInfo:(imageType) ? @{ @"imageType" : imageType } : nil];
        }
    } else {
        data = [encoder tip_writeDataWithImage:image encodingOptions:options suggestedQuality:quality error:error];
    }
    return data;
}

@end
