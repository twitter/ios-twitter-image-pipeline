//
//  TIPMemoryCache.h
//  TwitterImagePipeline
//
//  Created on 3/3/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import "TIPInspectableCache.h"

NS_ASSUME_NONNULL_BEGIN

@interface TIPImageMemoryCache : NSObject <TIPImageCache, TIPInspectableCache>

- (nullable TIPImageMemoryCacheEntry *)imageEntryForIdentifier:(NSString *)identifier;
- (void)updateImageEntry:(TIPImageCacheEntry *)entry forciblyReplaceExisting:(BOOL)force;
- (void)touchImageWithIdentifier:(NSString *)identifier;
- (void)clearImageWithIdentifier:(NSString *)identifier;
- (void)clearAllImages:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
