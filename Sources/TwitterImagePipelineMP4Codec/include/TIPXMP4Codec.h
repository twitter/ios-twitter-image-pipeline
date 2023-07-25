//
//  TIPXMP4Codec.h
//  TwitterImagePipeline
//
//  Created on 3/16/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TIPImageCodecs.h>

@protocol TIPXMP4DecoderConfig;

NS_ASSUME_NONNULL_BEGIN

//! Custom image type for MP4 animated images, `@"public.mp4"`
FOUNDATION_EXTERN NSString * const TIPXImageTypeMP4;

/**
 Convenience codec for MP4 animation support.
 Requires AVFoundation.framework be linked.
 This codec is not bundled with __TIP__ to avoid bloating it with MP4 animated image stuff,
 but there's nothing preventing a consumer from using this decoder.
 @warning this codec (decoder) definitely works, however it loads the entire animation into RAM.
 An MP4 animation that is large (in duration and/or pixels) will lead to memory pressure.
 Many MP4 animations will lead to memory pressure.
 GIF using native iOS decoding does not have this issue as the UIImage has smarts to offload
 the memory usage transparently.
 To avoid these pressures, a developer should custom implement a similar behavior to what UIImage
 does under the hood for GIFs, which is use a ring buffer of decoded images - decoding and cycling
 through the buffer as the animation progresses.  This is outside the scope of __TIP__ though.
 */
@interface TIPXMP4Codec : NSObject <TIPImageCodec>
/** MP4 decoder */
@property (nonatomic, readonly) id<TIPImageDecoder> tip_decoder;
/** MP4 encoder (`nil` at the moment) */
@property (nonatomic, readonly, nullable) id<TIPImageEncoder> tip_encoder;

/**
 designated initializer
 @param decoderConfig optional `TIPXMP4DecoderConfig` for default decoding behavior
*/
- (instancetype)initWithDefaultDecoderConfig:(nullable id<TIPXMP4DecoderConfig>)decoderConfig NS_DESIGNATED_INITIALIZER;

/** MP4 decoder default config */
@property(nonatomic, readonly, nullable) id<TIPXMP4DecoderConfig> defaultDecoderConfig;

/** Construct a decoder config */
+ (id<TIPXMP4DecoderConfig>)decoderConfigWithMaxDecodableFramesCount:(NSUInteger)max;

@end

/** config object for decoding behavior */
@protocol TIPXMP4DecoderConfig <NSObject>

/** configure a max number of frames to decode, 0 == unlimited */
@property (nonatomic, readonly) NSUInteger maxDecodableFramesCount;

@end

NS_ASSUME_NONNULL_END
