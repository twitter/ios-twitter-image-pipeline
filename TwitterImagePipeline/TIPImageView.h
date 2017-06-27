//
//  TIPImageView.h
//  TwitterImagePipeline
//
//  Created on 3/19/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIImageView.h>

@class TIPImagePipeline;
@class TIPImageViewFetchHelper;

NS_ASSUME_NONNULL_BEGIN

/**
 `TIPImageView` is a convenience subclass of `UIImageView` for displaying an image that is loaded
 from a given `TIPImagePipeline`.

 See `UIImageView(TIPImageViewFetchHelper)` category if subclassing `UIImageView` is not desired.
 */
@interface TIPImageView : UIImageView

/** The helper for fetching in this image view */
@property (nonatomic, nullable) TIPImageViewFetchHelper *fetchHelper;

/** initialize the view with a `TIPImageViewFetchHelper` */
- (instancetype)initWithFetchHelper:(nullable TIPImageViewFetchHelper *)fetchHelper;

@end

/**
 Convenience category for `UIImageView` for displaying an image that is loaded from
 a `TIPImagePipeline` via a `TIPImageViewFetchHelper`

 Avoids the need of refactoring to use `TIPImageView`.
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
