//
//  TweetImageFetchRequest.h
//  TwitterImagePipeline
//
//  Created on 2/11/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterImagePipeline.h>

@class TweetImageInfo;

NS_ASSUME_NONNULL_BEGIN

@interface TweetImageFetchRequest : NSObject <TIPImageFetchRequest>
@property (nonatomic) BOOL forcePlaceholder;
- (instancetype)initWithTweetImage:(TweetImageInfo *)tweet targetView:(nullable UIView *)view;
@end

NS_ASSUME_NONNULL_END
