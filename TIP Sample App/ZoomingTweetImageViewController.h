//
//  ZoomingTweetImageViewController.h
//  TwitterImagePipeline
//
//  Created on 2/11/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <UIKit/UIKit.h>

@class TweetImageInfo;

@interface ZoomingTweetImageViewController : UIViewController

- (instancetype)initWithTweetImage:(TweetImageInfo *)imageInfo;

@end
