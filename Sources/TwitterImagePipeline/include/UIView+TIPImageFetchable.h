//
//  UIView+TIPImageFetchable.h
//  TwitterImagePipeline
//
//  Created on 3/19/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <TIPImageFetchable.h>
#import <UIKit/UIImageView.h>

@class TIPImageViewFetchHelper;

NS_ASSUME_NONNULL_BEGIN

/**
 Convenience category for `UIView` for associating a `TIPImageViewFetchHelper`
 */
@interface UIView (TIPImageFetchable)

/**
 An `TIPImageViewFetchHelper` for loading `TIPImageFetchRequests` into this view.

 Setting this value for the first time will add an invisible "observer"
 subview to this view for observing events that `TIPImageViewFetchHelper` needs
 in order to work properly.

 @warning the `tip_fetchHelper` may only be set on `UIView` instances that adopt
 `TIPImageFetchable`.  To extend fetch helper support to a new `UIView` subclass,
 implement a category for that object that implements `TIPImageFetchable`.
 */
@property (nullable, nonatomic) TIPImageViewFetchHelper *tip_fetchHelper;

@end

/**
 Convenience category for `UIImageView` for adopting `TIPImageFetchable`.
 Just maps `tip_fetchedImage` property to `image` property, easy.
 */
@interface UIImageView (TIPImageFetchable) <TIPImageFetchable>
@end

NS_ASSUME_NONNULL_END
