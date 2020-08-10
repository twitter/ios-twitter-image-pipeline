//
//  TIPPartialImage.h
//  TwitterImagePipeline
//
//  Created on 3/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIPImageCodecs.h"
#import "TIPImageContainer.h"
#import "TIPImageUtils.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TIPPartialImageState) {
    TIPPartialImageStateNoData = 0,
    TIPPartialImageStateLoadingHeaders,
    TIPPartialImageStateLoadingImage,
    TIPPartialImageStateComplete,
};

TIP_OBJC_FINAL
@interface TIPPartialImage : NSObject

// State
@property (atomic, readonly) TIPPartialImageState state;
@property (nonatomic, readonly) NSUInteger expectedContentLength;

// After headers are read
@property (nonatomic, nullable, copy, readonly) NSString *type;
@property (nonatomic, readonly) CGSize dimensions;
@property (nonatomic, readonly) BOOL hasAlpha;
@property (nonatomic, readonly, getter=isProgressive) BOOL progressive; // mutually exclusive from animated
@property (nonatomic, readonly, getter=isAnimated) BOOL animated; // mutually exclusive from progressive
@property (nonatomic, readonly) BOOL hasGPSInfo; // very bad! we should never have user GPS info in our served images!

// Progress
@property (nonatomic, readonly) NSUInteger frameCount; // for progressive or animated images
@property (atomic, readonly, nullable) NSData *data;
@property (nonatomic, readonly) NSUInteger byteCount;
@property (nonatomic, readonly) float progress;

- (void)updateDecoderConfigMap:(nullable NSDictionary<NSString *, id> *)configMap;

- (instancetype)initWithExpectedContentLength:(NSUInteger)contentLength NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (TIPImageDecoderAppendResult)appendData:(nullable NSData *)data
                                    final:(BOOL)final;
- (nullable TIPImageContainer *)renderImageWithMode:(TIPImageDecoderRenderMode)mode
                                   targetDimensions:(CGSize)targetDimensions
                                  targetContentMode:(UIViewContentMode)targetContentMode
                                            decoded:(BOOL)decode;

@end

NS_ASSUME_NONNULL_END
