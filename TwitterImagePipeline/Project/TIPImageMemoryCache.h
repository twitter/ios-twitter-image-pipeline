//
//  TIPMemoryCache.h
//  TwitterImagePipeline
//
//  Created on 3/3/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import "TIPInspectableCache.h"

@interface TIPImageMemoryCache : NSObject <TIPImageCache, TIPInspectableCache>

- (nullable TIPImageMemoryCacheEntry *)imageEntryForIdentifier:(nonnull NSString *)identifier;
- (void)updateImageEntry:(nonnull TIPImageCacheEntry *)entry forciblyReplaceExisting:(BOOL)force;
- (void)touchImageWithIdentifier:(nonnull NSString *)identifier;
- (void)clearImageWithIdentifier:(nonnull NSString *)identifier;
- (void)clearAllImages:(void (^ __nullable)(void))completion;

@end
