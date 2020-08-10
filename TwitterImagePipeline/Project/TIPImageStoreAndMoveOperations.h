//
//  TIPImageStoreAndMoveOperations.h
//  TwitterImagePipeline
//
//  Created on 1/13/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TIPImagePipeline.h"
#import "TIPImageStoreRequest.h"
#import "TIPSafeOperation.h"

NS_ASSUME_NONNULL_BEGIN

@class TIPImageStoreHydrationOperation;

@interface TIPDisabledExternalMutabilityOperation : TIPSafeOperation <TIPDependencyOperation>
@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageStoreOperation : TIPDisabledExternalMutabilityOperation

- (instancetype)initWithRequest:(id<TIPImageStoreRequest>)request
                       pipeline:(TIPImagePipeline *)pipeline
                     completion:(nullable TIPImagePipelineOperationCompletionBlock)completion;

- (void)setHydrationDependency:(nonnull TIPImageStoreHydrationOperation *)dependency;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageStoreHydrationOperation : TIPDisabledExternalMutabilityOperation

@property (nonatomic, readonly, nullable) NSError *error;
@property (nonatomic, readonly, nullable) id<TIPImageStoreRequest> hydratedRequest;

- (instancetype)initWithRequest:(id<TIPImageStoreRequest>)request
                       pipeline:(TIPImagePipeline *)pipeline
                       hydrater:(id<TIPImageStoreRequestHydrater>)hydrater;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageMoveOperation : TIPDisabledExternalMutabilityOperation

@property (nonatomic, readonly, copy) NSString *originalIdentifier;
@property (nonatomic, readonly, copy) NSString *updatedIdentifier;
@property (nonatomic, readonly) TIPImagePipeline *pipeline;

- (instancetype)initWithPipeline:(TIPImagePipeline *)pipeline
              originalIdentifier:(NSString *)oldIdentifier
               updatedIdentifier:(NSString *)newIdentifier
                      completion:(nullable TIPImagePipelineOperationCompletionBlock)completion;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
