//
//  TIPDefaultImageCodecs.h
//  TwitterImagePipeline
//
//  Created on 11/7/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIPImageCodecs.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Codecs

@interface TIPBasicCGImageSourceCodec : NSObject <TIPImageCodec>

@property (nonatomic, readonly) id<TIPImageDecoder> tip_decoder;
@property (nullable, nonatomic, readonly) id<TIPImageEncoder> tip_encoder;
@property (nonatomic, readonly) BOOL tip_isAnimated;

+ (nullable instancetype)codecWithImageType:(NSString *)imageType;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

#pragma mark - Decoders

@interface TIPBasicCGImageSourceDecoder : NSObject <TIPImageDecoder>
@end

@interface TIPJPEGCGImageSourceDecoder : TIPBasicCGImageSourceDecoder
@end

#pragma mark - Encoders

@interface TIPBasicCGImageSourceEncoder : NSObject <TIPImageEncoder>
@end

NS_ASSUME_NONNULL_END
