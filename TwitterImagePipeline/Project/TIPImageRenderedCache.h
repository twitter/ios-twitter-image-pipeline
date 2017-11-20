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

NS_ASSUME_NONNULL_BEGIN

@interface TIPImageRenderedCache : NSObject <TIPImageCache, TIPInspectableCache>

- (nullable TIPImageCacheEntry *)imageEntryWithIdentifier:(NSString *)identifier transformerIdentifier:(nullable NSString *)transformerIdentifier targetDimensions:(CGSize)size targetContentMode:(UIViewContentMode)mode;
- (void)storeImageEntry:(TIPImageCacheEntry *)entry transformerIdentifier:(nullable NSString *)transformerIdentifier;
- (void)clearImagesWithIdentifier:(NSString *)identifier;
- (void)clearAllImages:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
