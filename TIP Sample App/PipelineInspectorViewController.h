//
//  PipelineInspectorViewController.h
//  TwitterImagePipeline
//
//  Created on 2/21/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <UIKit/UIKit.h>

@class TIPImagePipelineInspectionResult;

@interface PipelineInspectorViewController : UIViewController

- (instancetype)initWithPipelineInspectionResult:(TIPImagePipelineInspectionResult *)result;

@end
