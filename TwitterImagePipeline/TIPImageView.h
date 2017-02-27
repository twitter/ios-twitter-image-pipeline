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

/**
 `TIPImageView` is a convenience subclass of `UIImageView` for displaying an image that is loaded
 from a given `TIPImagePipeline`.
 */
@interface TIPImageView : UIImageView

/** The helper for fetching in this image view */
@property (nonatomic, nullable) TIPImageViewFetchHelper *fetchHelper;

/** initialize the view with a `TIPImageViewFetchHelper` */
- (nonnull instancetype)initWithFetchHelper:(nullable TIPImageViewFetchHelper *)fetchHelper;

@end
