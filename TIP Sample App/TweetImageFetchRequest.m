//
//  TweetImageFetchRequest.m
//  TwitterImagePipeline
//
//  Created on 2/11/17.
//  Copyright © 2017 Twitter. All rights reserved.
//

#import "AppDelegate.h"
#import "TweetImageFetchRequest.h"
#import "TwitterAPI.h"

#define kSMALL  @"small"
#define kMEDIUM @"medium"
#define kLARGE  @"large"

typedef struct {
    void * const name;
    CGFloat const dim;
} VariantInfo;

static VariantInfo const sVariantSizeMap[] = {
    { .name = kSMALL,   .dim = 680 },
    { .name = kMEDIUM,  .dim = 1200 },
    { .name = kLARGE,   .dim = 2048 },
};

static NSString *DetermineVariant(CGSize aspectRatio, const CGSize targetDimensions, UIViewContentMode targetContentMode);

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
                NSString *variantName = DetermineVariant(_tweetImage.originalDimensions, _targetDimensions, _targetContentMode);
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

static NSString *DetermineVariant(CGSize aspectRatio, const CGSize dimensions, UIViewContentMode contentMode)
{
    if (aspectRatio.height <= 0 || aspectRatio.width <= 0) {
        aspectRatio = CGSizeMake(1, 1);
    }

    const BOOL scaleToFit = (UIViewContentModeScaleAspectFit == contentMode);
    const CGSize scaledToTargetDimensions = TIPDimensionsScaledToTargetSizing(aspectRatio, dimensions, (scaleToFit ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill));

    NSString * selectedVariantName = nil;
    for (size_t i = 0; i < (sizeof(sVariantSizeMap) / sizeof(sVariantSizeMap[0])); i++) {
        const CGSize variantSize = CGSizeMake(sVariantSizeMap[i].dim, sVariantSizeMap[i].dim);
        const CGSize scaledToVariantDimensions = TIPDimensionsScaledToTargetSizing(aspectRatio, variantSize, UIViewContentModeScaleAspectFit);
        if (scaledToVariantDimensions.width >= scaledToTargetDimensions.width && scaledToVariantDimensions.height >= scaledToTargetDimensions.height) {
            selectedVariantName = (__bridge NSString *)sVariantSizeMap[i].name;
            break;
        }
    }

    if (!selectedVariantName) {
        selectedVariantName = kLARGE;
    }

    return selectedVariantName;
}

