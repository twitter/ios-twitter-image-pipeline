//
//  TIPXWebPCodec.h
//  TwitterImagePipeline
//
//  Created on 11/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <TwitterImagePipeline/TIPImageCodecs.h>

NS_ASSUME_NONNULL_BEGIN

//! Custom image type for WebP, `@"google.webp"`
FOUNDATION_EXTERN NSString * const TIPXImageTypeWebP;

/**
 Convenience codec for WebP support.
 Requires WebP.framework from Google.
 This codec is not bundled with __TIP__ to avoid bloating the framework with WebP stuff,
 but there's nothing preventing a consumer from using this decoder.
 */
@interface TIPXWebPCodec : NSObject <TIPImageCodec>
/** WebP decoder */
@property (nonatomic, readonly) id<TIPImageDecoder> tip_decoder;
/** WebP encoder */
@property (nonatomic, readonly) id<TIPImageEncoder> tip_encoder;
@end

NS_ASSUME_NONNULL_END
