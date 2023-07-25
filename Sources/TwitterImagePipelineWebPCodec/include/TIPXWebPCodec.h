//
//  TIPXWebPCodec.h
//  TwitterImagePipeline
//
//  Created on 11/9/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TIPImageCodecs.h>


NS_ASSUME_NONNULL_BEGIN

/**
 Convenience codec for WebP support.
 Requires WebP.framework from Google (WebPDemux.framework for animation decoding).
 This codec is not bundled with __TIP__ to avoid bloating the framework with WebP stuff,
 but there's nothing preventing a consumer from using this decoder.

 @note WebP support was added to iOS 14, so it is preferable to use that decoder as it supports animated WebP images.
 @note To support Animation decoding, must be compiled with `TIPX_WEBP_ANIMATION_DECODING_ENABLED=1`
 */
@interface TIPXWebPCodec : NSObject <TIPImageCodec>
/** WebP decoder */
@property (nonatomic, readonly) id<TIPImageDecoder> tip_decoder;
/** WebP encoder */
@property (nonatomic, readonly) id<TIPImageEncoder> tip_encoder;

/**
 Initializer
 @param preferredCodec Pass the default system encoder and/or decoder if possible. If they are not provided (including if a nil `tip_decoder` or `tip_encoder` are found), use the `TIPXWebPCodec` implementations.
 @return a new `TIPXWebPCodec` instance
 */
- (instancetype)initWithPreferredCodec:(nullable id<TIPImageCodec>)preferredCodec NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/** Convenience check to see if animation decoding was compiled */
+ (BOOL)hasAnimationDecoding;

@end

NS_ASSUME_NONNULL_END

