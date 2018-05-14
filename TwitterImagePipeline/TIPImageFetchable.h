//
//  TIPImageFetchable.h
//  TwitterImagePipeline
//
//  Created on 11/27/17.
//  Copyright © 2017 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A protocol for enabling a `UIView` to become compliant with `TIPImageViewFetchHelper`
 */
@protocol TIPImageFetchable <NSObject>

@required

/**
 This property is to set the underlying image of the view for display.
 For example, __TIP__ implements `TIPImageFetchable` on `UIImageView` such that
 the `tip_fetchedImage` just redirects to `UIImageView` class' `image` property.
 */
@property (nonatomic, readwrite, nullable) UIImage *tip_fetchedImage;

@end

NS_ASSUME_NONNULL_END
