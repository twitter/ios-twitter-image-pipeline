//
//  TIPImageMemoryCache.h
//  TwitterImagePipeline
//
//  Created on 3/3/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import "TIPInspectableCache.h"

NS_ASSUME_NONNULL_BEGIN

@interface TIPImageMemoryCache : NSObject <TIPImageCache, TIPInspectableCache>

- (nullable TIPImageMemoryCacheEntry *)imageEntryForIdentifier:(NSString *)identifier
                                              targetDimensions:(CGSize)targetDimensions
                                             targetContentMode:(UIViewContentMode)targetContentMode
                                              decoderConfigMap:(nullable NSDictionary<NSString *,id> *)configMap TIP_OBJC_DIRECT;
- (void)updateImageEntry:(TIPImageCacheEntry *)entry
 forciblyReplaceExisting:(BOOL)force TIP_OBJC_DIRECT;
- (void)touchImageWithIdentifier:(NSString *)identifier TIP_OBJC_DIRECT;

@end

NS_ASSUME_NONNULL_END
