//
//  TIPInspectableCache.h
//  TwitterImagePipeline
//
//  Created on 6/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TIPImagePipelineInspectionResult;

NS_ASSUME_NONNULL_BEGIN

typedef void(^TIPInspectableCacheCallback)(NSArray<TIPImagePipelineInspectionResult *> * __nullable completedEntries, NSArray<TIPImagePipelineInspectionResult *> * __nullable partialEntries);

@protocol TIPInspectableCache <NSObject>

@required
- (void)inspect:(TIPInspectableCacheCallback)callback;

@end

NS_ASSUME_NONNULL_END
