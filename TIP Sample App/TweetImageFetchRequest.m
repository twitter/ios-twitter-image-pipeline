//
//  TweetImageFetchRequest.m
//  TwitterImagePipeline
//
//  Created on 2/11/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "AppDelegate.h"
#import "TweetImageFetchRequest.h"
#import "TwitterAPI.h"

@implementation TweetImageFetchRequest
{
    TweetImageInfo *_tweetImage;
    NSURL *_imageURL;
}

@synthesize targetDimensions = _targetDimensions;
@synthesize targetContentMode = _targetContentMode;

- (instancetype)initWithTweetImage:(TweetImageInfo *)tweetImage targetView:(UIView *)view
{
    if (self = [super init]) {
        _tweetImage = tweetImage;
        _targetContentMode = view.contentMode;
        _targetDimensions = TIPDimensionsFromView(view);
    }
    return self;
}

- (NSString *)imageIdentifier
{
    return _tweetImage.baseURLString;
}

- (NSURL *)imageURL
{
    if (!_imageURL) {
        if (self.forcePlaceholder) {
            _imageURL = [NSURL URLWithString:@"placeholder://placeholder.com/placeholder.jpg"];
        } else {
            NSString *URLString = nil;
            if ([_tweetImage.baseURLString hasPrefix:@"https://pbs.twimg.com/media/"]) {
                NSString *variantName = TweetImageDetermineVariant(_tweetImage.originalDimensions, _targetDimensions, _targetContentMode);
                URLString = [NSString stringWithFormat:@"%@?format=%@&name=%@", _tweetImage.baseURLString, (APP_DELEGATE.searchWebP) ? @"webp" : _tweetImage.format, variantName];
            } else {
                URLString = [NSString stringWithFormat:@"%@.%@", _tweetImage.baseURLString, _tweetImage.format];
            }
            _imageURL = [NSURL URLWithString:URLString];
        }
    }
    return _imageURL;
}

- (TIPImageFetchOptions)options
{
    return (self.forcePlaceholder) ? TIPImageFetchTreatAsPlaceholder : TIPImageFetchNoOptions;
}

@end
