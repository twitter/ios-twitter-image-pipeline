//
//  TIPImageRenderedCache.h
//  TwitterImagePipeline
//
//  Created on 4/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <UIKit/UIImage.h>
#import <UIKit/UIView.h>

#import "TIPInspectableCache.h"

@class TIPImageCacheEntry;

@interface TIPImageRenderedCache : NSObject <TIPImageCache, TIPInspectableCache>

- (nullable TIPImageCacheEntry *)imageEntryWithIdentifier:(nonnull NSString *)identifier targetDimensions:(CGSize)size targetContentMode:(UIViewContentMode)mode;
- (void)storeImageEntry:(nonnull TIPImageCacheEntry *)entry;
- (void)clearImagesWithIdentifier:(nonnull NSString *)identifier;
- (void)clearAllImages:(void (^ __nullable)(void))completion;

@end
