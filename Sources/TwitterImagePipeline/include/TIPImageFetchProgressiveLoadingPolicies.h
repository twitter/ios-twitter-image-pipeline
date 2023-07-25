//
//  TIPImageFetchProgressiveLoadingPolicies.h
//  TwitterImagePipeline
//
//  Created on 4/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <TIPProgressive.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A policy that loads the first and last frames of a progressive image.
 */
@interface TIPFirstAndLastFrameProgressiveLoadingPolicy : NSObject <TIPImageFetchProgressiveLoadingPolicy>

/** Whether the policy should render the low quality frame.  Default is `YES`. */
@property (nonatomic) BOOL shouldRenderLowQualityFrame;

@end

/**
 A policy that loads all frames (skipping the low quality frame if `shouldRenderLowQualityFrame` is
 `NO`).
 */
@interface TIPFullFrameProgressiveLoadingPolicy : NSObject <TIPImageFetchProgressiveLoadingPolicy>

/** Whether the policy should render the low quality frame.  Default is `YES`. */
@property (nonatomic) BOOL shouldRenderLowQualityFrame;

@end

/**
 A policy that loads any progress encountered, even incomplete frames.
 */
@interface TIPGreedyProgressiveLoadingPolicy : NSObject <TIPImageFetchProgressiveLoadingPolicy>

/**
 The minimum amount of progress required before attempting to render a progressive image.
 Default == 0.0f
 */
@property (nonatomic) float minimumProgress;
@end

/**
 A policy that loads as much as possible after the `minimumProgress` has been completed (even
 incomplete frames) and the last final frame.
 */
@interface TIPFirstAndLastOpportunityProgressiveLoadingPolicy : NSObject <TIPImageFetchProgressiveLoadingPolicy>

/**
 The minimum amount of progress required before attempting to render a progressive image.
 Default == 0.0f
 */
@property (nonatomic) float minimumProgress;
@end

/**
 A policy that never loads any progress encountered, not even complete frames.
 */
@interface TIPDisabledProgressiveLoadingPolicy : NSObject <TIPImageFetchProgressiveLoadingPolicy>
@end

/**
 A policy to wrap another policy that is weakly held to help avoid retain cycles if they would be
 possible.  Behaves just like the `TIPDisabledProgressiveLoadingPolicy` if the wrapped policy has
 become `nil`.
 */
@interface TIPWrapperProgressiveLoadingPolicy : NSObject <TIPImageFetchProgressiveLoadingPolicy>
/** The wrapped policy or `nil` */
@property (nonatomic, readonly, weak, nullable) id<TIPImageFetchProgressiveLoadingPolicy> wrappedPolicy;
/** Designated initializer.  Provide the _policy_ to wrap. */
- (instancetype)initWithProgressiveLoadingPolicy:(nullable id<TIPImageFetchProgressiveLoadingPolicy>)policy NS_DESIGNATED_INITIALIZER;
@end

NS_ASSUME_NONNULL_END
