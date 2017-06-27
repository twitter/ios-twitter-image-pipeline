//
//  TIPImageFetchTransformer.h
//  TwitterImagePipeline
//
//  Created by Nolan O'Brien on 5/4/17.
//  Copyright © 2017 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIView.h>

@class TIPImageFetchOperation;
@class UIImage;

NS_ASSUME_NONNULL_BEGIN

/**
 Protocol for transforming an image fetched by a `TIPImageFetchOperation`.
 Implementers can do whatever they like to the given image: scale, blur, colorize, etc.
 Target sizing hints are provided as a convenience.  If scaling to the target sizing
 is viable for the transform, doing so can be an optimization.
 */
@protocol TIPImageFetchTransformer <NSObject>

/**
 Transform the provided _image_

 @param image the `UIImage` to transform
 @param progress the progress state of the image.  `1.f` == full image, `-1.f` == preview image, otherwise == progressive scan
 @param targetDimensions hint `CGSize` for the target.  `CGSizeZero` for no hint.
 @param targetContentMode hint `UIViewContentMode` for the target.
 @param op the `TIPImageFetchOperation` being targeted for transform.

 @return the desired transformed `UIImage`.  `nil` to not transform.

 @note Transformed images are NOT cached.  The cache will persist the raw source image.
 */
- (nullable UIImage *)tip_transformImage:(UIImage *)image withProgress:(float)progress hintTargetDimensions:(CGSize)targetDimensions hintTargetContentMode:(UIViewContentMode)targetContentMode forImageFetchOperation:(TIPImageFetchOperation *)op;

@end

NS_ASSUME_NONNULL_END
