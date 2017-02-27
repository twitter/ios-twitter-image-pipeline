//
//  TIPImageStoreOperation.h
//  TwitterImagePipeline
//
//  Created on 1/13/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TIPImagePipeline.h"
#import "TIPImageStoreRequest.h"

NS_ASSUME_NONNULL_BEGIN

@class TIPImageStoreHydrationOperation;

@interface TIPDisabledExternalMutabilityOperation : NSOperation <TIPDependencyOperation>
@end

@interface TIPImageStoreOperation : TIPDisabledExternalMutabilityOperation

- (instancetype)initWithRequest:(id<TIPImageStoreRequest>)request pipeline:(TIPImagePipeline *)pipeline completion:(nullable TIPImagePipelineStoreCompletionBlock)completion;

- (void)setHydrationDependency:(nonnull TIPImageStoreHydrationOperation *)dependency;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface TIPImageStoreHydrationOperation : TIPDisabledExternalMutabilityOperation

@property (nonatomic, readonly) NSError *error;
@property (nonatomic, readonly) id<TIPImageStoreRequest> hydratedRequest;

- (instancetype)initWithRequest:(id<TIPImageStoreRequest>)request pipeline:(TIPImagePipeline *)pipeline hydrater:(id<TIPImageStoreRequestHydrater>)hydrater;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
