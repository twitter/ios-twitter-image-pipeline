//
//  PipelineCacheInspectionResultsViewController.h
//  TwitterImagePipeline
//
//  Created on 2/21/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <UIKit/UIKit.h>

@class TIPImagePipeline;
@protocol TIPImagePipelineInspectionResultEntry;

@interface PipelineCacheInspectionResultsViewController : UIViewController

@property (nonatomic, readonly) BOOL didClearAnyEntries;

- (instancetype)initWithResults:(NSArray<id<TIPImagePipelineInspectionResultEntry>> *)results pipeline:(TIPImagePipeline *)pipeline;

@end
