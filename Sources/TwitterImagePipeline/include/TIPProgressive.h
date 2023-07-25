//
//  TIPProgressive.h
//  TwitterImagePipeline
//
//  Created on 7/14/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <TIPImageUtils.h>

@class TIPImageFetchOperation;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Constants

/**
 The latest progress made in loading a progressive image.
 See `[TIPImageFetchProgressiveLoadingPolicy tip_imageFetchOperation:behaviorForProgress:frameCount:progress:type:dimensions:renderCount:]`.
 */
typedef NS_ENUM(NSInteger, TIPImageFetchProgress)
{
    /** No progress was made */
    TIPImageFetchProgressNone = 0,
    /** Data was loaded, but no frames were completed */
    TIPImageFetchProgressPartialFrame,
    /** One or more full frames finished loading */
    TIPImageFetchProgressFullFrame,
};

/**
 The behavior for how to update the delegate with the progressive image that has been loaded thus
 far.
 See `[TIPImageFetchProgressiveLoadingPolicy tip_imageFetchOperation:behaviorForProgress:frameCount:progress: type:dimensions:renderCount:]`.
 */
typedef NS_ENUM(NSInteger, TIPImageFetchProgressUpdateBehavior)
{
    /** Don't update the progressive image to the delegate */
    TIPImageFetchProgressUpdateBehaviorNone = TIPImageFetchProgressNone,
    /** Update the progressive image to the delegate with as much of the image that is loaded */
    TIPImageFetchProgressUpdateBehaviorUpdateWithAnyProgress = TIPImageFetchProgressPartialFrame,
    /** Update the progressive image to the delegate but only with the latest fully loaded frame */
    TIPImageFetchProgressUpdateBehaviorUpdateWithFullFrameProgress = TIPImageFetchProgressFullFrame
};

#pragma mark - Protocols

/**
 `TIPImageFetchProgressiveLoadingPolicy` is a protocol for supporting custom progressive loading
 behavior. By providing a progressive loading policy to a `TIPImageFetchRequest`, the image can be
 progressively loaded in any desired fashion from loading as much as possible as bytes are loaded,
 to loading only full frames, to loading differently based on context.
 */
@protocol TIPImageFetchProgressiveLoadingPolicy <NSObject>

@required
/**
 The callback used to determine how a progressive image should be updated as it is loaded.
 Requires the image being requested support progressive loading AND the delegate must implement
 `imageFetchOperation:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:` to
 return `YES`.

 @param op            The related image fetch operation
 @param frameProgress `TIPImageFetchProgress` since last full frame
 @param frameCount    number of full frames loaded, doesn't include any partial frame progress
 @param progress      total progress
 @param type          the _TIPImageType_ of the image being progressively loaded
 @param dimensions    the dimensions of the image being loaded
 @param renderCount   the number of times the progress has been rendered thus far

 @return the `TIPImageFetchProgressUpdateBehavior` to perform.
 `TIPImageFetchProgressUpdateBehaviorNone` == don't update,
 `TIPImageFetchProgressUpdateBehaviorUpdateWithAnyProgress` == update no matter the progress,
 `TIPImageFetchProgressUpdateBehaviorUpdateWithFullFrameProgress` == only update to that last full
 frame loaded, nothing further.  By default, if there is no policy, a strong default will be used.
 */
- (TIPImageFetchProgressUpdateBehavior)tip_imageFetchOperation:(TIPImageFetchOperation *)op behaviorForProgress:(TIPImageFetchProgress)frameProgress frameCount:(NSUInteger)frameCount progress:(float)progress type:(NSString *)type dimensions:(CGSize)dimensions renderCount:(NSUInteger)renderCount;

@end

#pragma mark - Default Policies

/**
 The default progressive loading policies if progressive loading is supported and enabled.
 The returned `NSDictionary` uses `NSNumber` wrapped `TIPImageType` values as keys.
 If a progressive loading policy is not given on a request that is loading an image type that is
 progressive, the default policy will be used.

 `TIPImageTypeJPEG`:
 - 64-bit: `TIPFullFrameProgressiveLoadingPolicy` w/ `shouldRenderLowQualityFrame` == `YES`
 - 32-bit: `TIPFirstAndLastFrameProgressiveLoadingPolicy` w/ `shouldRenderLowQualityFrame` == `YES`
 */
FOUNDATION_EXTERN NSDictionary<NSString *, id<TIPImageFetchProgressiveLoadingPolicy>> *TIPImageFetchProgressiveLoadingPolicyDefaultPolicies(void);

NS_ASSUME_NONNULL_END
