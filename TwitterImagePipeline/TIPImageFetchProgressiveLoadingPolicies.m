//
//  TIPImageFetchProgressiveLoadingPolicies.m
//  TwitterImagePipeline
//
//  Created on 4/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIPImageFetchProgressiveLoadingPolicies.h"

NS_ASSUME_NONNULL_BEGIN

NSDictionary<NSString *, id<TIPImageFetchProgressiveLoadingPolicy>> *TIPImageFetchProgressiveLoadingPolicyDefaultPolicies()
{
    static NSDictionary *sDefaultPolicies = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if __LP64__
        // fast
        sDefaultPolicies = @{
                             TIPImageTypeJPEG : [[TIPFullFrameProgressiveLoadingPolicy alloc] init]
                             };
#else
        // slow
        sDefaultPolicies = @{
                             TIPImageTypeJPEG : [[TIPFirstAndLastFrameProgressiveLoadingPolicy alloc] init]
                             };
#endif
    });
    return sDefaultPolicies;
}

@implementation TIPFirstAndLastFrameProgressiveLoadingPolicy

- (instancetype)init
{
    if (self = [super init]) {
        _shouldRenderLowQualityFrame = YES;
    }
    return self;
}

- (TIPImageFetchProgressUpdateBehavior)tip_imageFetchOperation:(TIPImageFetchOperation *)op
                                           behaviorForProgress:(TIPImageFetchProgress)frameProgress
                                                    frameCount:(NSUInteger)frameCount
                                                      progress:(float)progress
                                                          type:(NSString *)type
                                                    dimensions:(CGSize)dimensions
                                                   renderCount:(NSUInteger)renderCount
{
    if (TIPImageFetchProgressFullFrame == frameProgress) {
        // Always load the last frame
        if (progress >= 1.0f) {
            return TIPImageFetchProgressUpdateBehaviorUpdateWithFullFrameProgress;
        }

        // Rendered yet?
        if (!renderCount) {
            if (self.shouldRenderLowQualityFrame || frameCount >= 2) {
                // Load the frame
                return TIPImageFetchProgressUpdateBehaviorUpdateWithFullFrameProgress;
            }
        }
    }

    return TIPImageFetchProgressUpdateBehaviorNone;
}

@end

@implementation TIPFullFrameProgressiveLoadingPolicy

- (instancetype)init
{
    if (self = [super init]) {
        _shouldRenderLowQualityFrame = YES;
    }
    return self;
}

- (TIPImageFetchProgressUpdateBehavior)tip_imageFetchOperation:(TIPImageFetchOperation *)op
                                           behaviorForProgress:(TIPImageFetchProgress)frameProgress
                                                    frameCount:(NSUInteger)frameCount
                                                      progress:(float)progress
                                                          type:(NSString *)type
                                                    dimensions:(CGSize)dimensions
                                                   renderCount:(NSUInteger)renderCount
{
    // We don't want to use any partial frames.
    // When I refer to "frame" in the comments below, I'm refering to full frames.
    if (TIPImageFetchProgressFullFrame == frameProgress) {

        // Ignoring the first frame, load every frame
        if (frameCount > 1) {
            return TIPImageFetchProgressUpdateBehaviorUpdateWithFullFrameProgress;
        }

        // For the first frame:
        // if it has 20% or more of the data loaded, we can use it
        // also, if we are marked for rendering the low quality frame, we can use it
        if (frameCount == 1 && (self.shouldRenderLowQualityFrame || progress >= 0.2f)) {
            return TIPImageFetchProgressUpdateBehaviorUpdateWithFullFrameProgress;
        }
    }

    return TIPImageFetchProgressUpdateBehaviorNone;
}

@end

@implementation TIPGreedyProgressiveLoadingPolicy

- (TIPImageFetchProgressUpdateBehavior)tip_imageFetchOperation:(TIPImageFetchOperation *)op
                                           behaviorForProgress:(TIPImageFetchProgress)frameProgress
                                                    frameCount:(NSUInteger)frameCount
                                                      progress:(float)progress
                                                          type:(NSString *)type
                                                    dimensions:(CGSize)dimensions
                                                   renderCount:(NSUInteger)renderCount
{
    return (progress > self.minimumProgress) ?
                TIPImageFetchProgressUpdateBehaviorUpdateWithAnyProgress :
                TIPImageFetchProgressUpdateBehaviorNone;
}

@end

@implementation TIPFirstAndLastOpportunityProgressiveLoadingPolicy

- (TIPImageFetchProgressUpdateBehavior)tip_imageFetchOperation:(TIPImageFetchOperation *)op
                                           behaviorForProgress:(TIPImageFetchProgress)frameProgress
                                                    frameCount:(NSUInteger)frameCount
                                                      progress:(float)progress
                                                          type:(NSString *)type
                                                    dimensions:(CGSize)dimensions
                                                   renderCount:(NSUInteger)renderCount
{
    if (progress >= 1.f) {
        return TIPImageFetchProgressUpdateBehaviorUpdateWithFullFrameProgress;
    }

    if (0 == renderCount && progress > self.minimumProgress) {
        return TIPImageFetchProgressUpdateBehaviorUpdateWithAnyProgress;
    }

    return TIPImageFetchProgressUpdateBehaviorNone;
}

@end

@implementation TIPDisabledProgressiveLoadingPolicy

- (TIPImageFetchProgressUpdateBehavior)tip_imageFetchOperation:(TIPImageFetchOperation *)op
                                           behaviorForProgress:(TIPImageFetchProgress)frameProgress
                                                    frameCount:(NSUInteger)frameCount
                                                      progress:(float)progress
                                                          type:(NSString *)type
                                                    dimensions:(CGSize)dimensions
                                                   renderCount:(NSUInteger)renderCount
{
    return TIPImageFetchProgressUpdateBehaviorNone;
}

@end

@implementation TIPWrapperProgressiveLoadingPolicy

- (instancetype)init
{
    return [self initWithProgressiveLoadingPolicy:nil];
}

- (instancetype) initWithProgressiveLoadingPolicy:(nullable id<TIPImageFetchProgressiveLoadingPolicy>)policy
{
    if (self = [super init]) {
        _wrappedPolicy = policy;
    }
    return self;
}

- (TIPImageFetchProgressUpdateBehavior)tip_imageFetchOperation:(TIPImageFetchOperation *)op
                                           behaviorForProgress:(TIPImageFetchProgress)frameProgress
                                                    frameCount:(NSUInteger)frameCount
                                                      progress:(float)progress
                                                          type:(NSString *)type
                                                    dimensions:(CGSize)dimensions
                                                   renderCount:(NSUInteger)renderCount
{
    id<TIPImageFetchProgressiveLoadingPolicy> policy = self.wrappedPolicy;
    if (policy) {
        return [policy tip_imageFetchOperation:op
                           behaviorForProgress:frameProgress
                                    frameCount:frameCount
                                      progress:progress
                                          type:type
                                    dimensions:dimensions
                                   renderCount:renderCount];
    }
    return TIPImageFetchProgressUpdateBehaviorNone;
}

@end

NS_ASSUME_NONNULL_END
