//
//  TweetImageFetchRequest.h
//  TwitterImagePipeline
//
//  Created on 2/11/17.
//  Copyright © 2017 Twitter. All rights reserved.
//

#import <TwitterImagePipeline/TwitterImagePipeline.h>

@class TweetImageInfo;

@interface TweetImageFetchRequest : NSObject <TIPImageFetchRequest>
@property (nonatomic) BOOL forcePlaceholder;
- (instancetype)initWithTweetImage:(TweetImageInfo *)tweet targetView:(UIView *)view;
@end
