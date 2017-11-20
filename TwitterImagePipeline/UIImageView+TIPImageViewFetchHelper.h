//
//  UIImageView+TIPImageViewFetchHelper.h
//  TwitterImagePipeline
//
//  Created on 3/19/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <UIKit/UIImageView.h>

@class TIPImageViewFetchHelper;

NS_ASSUME_NONNULL_BEGIN

/**
 Convenience category for `UIImageView` for displaying an image that is loaded from
 a `TIPImagePipeline` via a `TIPImageViewFetchHelper`
 */
@interface UIImageView (TIPImageViewFetchHelper)

/**
 An `TIPImageViewFetchHelper` for loading `TIPImageFetchRequests` into this image view.

 Setting this value for the first time will add an invisible "observer"
 subview to this view for observing events that `TIPImageViewFetchHelper` needs
 in order to work properly.
 */
@property (nullable, nonatomic) TIPImageViewFetchHelper *tip_fetchHelper;

@end

NS_ASSUME_NONNULL_END
