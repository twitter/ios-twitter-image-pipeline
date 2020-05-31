//
//  TIPImageFetchable.h
//  TwitterImagePipeline
//
//  Created on 11/27/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TIPImageContainer;
@class UIImage;
@class UIView;

#pragma mark - TIPImageFetchable protocol

/**
 A protocol for enabling a `UIView` to become compliant with `TIPImageViewFetchHelper`.
 At least one of `tip_fetchedImage` or `tip_fetchedImageContainer` must be implemented.
 */
@protocol TIPImageFetchable <NSObject>

@optional

/**
 This property is to set the underlying image of the view for display.
 For example, a view can implement `TIPImageFetchable` such that
 the `tip_fetchedImageContainer` can show an animated image since that information
 is encapsulated in `TIPImageContainer`.
 @note `tip_fetchedImageContainer` takes precedent over `tip_fetchImage`
 */
@property (nonatomic, readwrite, nullable) TIPImageContainer *tip_fetchedImageContainer;

/**
 This property is to set the underlying image of the view for display.
 For example, __TIP__ implements `TIPImageFetchable` on `UIImageView` such that
 the `tip_fetchedImage` just redirects to `UIImageView` class' `image` property.
 @note `tip_fetchedImageContainer` takes precedent over `tip_fetchImage`
 */
@property (nonatomic, readwrite, nullable) UIImage *tip_fetchedImage;

@end

#pragma mark - Helper functions

#pragma mark Image helper functions

/** does the _fetchable_ have an image (via `tip_fetchedImageContainer` or `tip_fetchedImage`) */
FOUNDATION_EXTERN BOOL TIPImageFetchableHasImage(id<TIPImageFetchable> __nullable fetchable);

/** get the fetched image from the _fetchable_ (via `tip_fetchedImageContainer` or `tip_fetchedImage`) */
FOUNDATION_EXTERN UIImage * __nullable TIPImageFetchableGetImage(id<TIPImageFetchable> __nullable fetchable);
/** get the fetched image with container from the _fetchable_ (via `tip_fetchedImageContainer` or `tip_fetchedImage`) */
FOUNDATION_EXTERN TIPImageContainer * __nullable TIPImageFetchableGetImageContainer(id<TIPImageFetchable> __nullable fetchable);

/** set the _fetchable_ fetch image (via `tip_fetchedImageContainer` or `tip_fetchedImage`) */
FOUNDATION_EXTERN void TIPImageFetchableSetImage(id<TIPImageFetchable> __nullable fetchable, UIImage * __nullable image);
/** set the _fetchable_ fetch image with a container (via `tip_fetchedImageContainer` or `tip_fetchedImage`) */
FOUNDATION_EXTERN void TIPImageFetchableSetImageContainer(id<TIPImageFetchable> __nullable fetchable, TIPImageContainer * __nullable imageContainer);


NS_ASSUME_NONNULL_END
