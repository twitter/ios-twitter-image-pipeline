//
//  TIPImageFetchRequest.h
//  TwitterImagePipeline
//
//  Created on 1/21/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import "TIPImageFetchRequest.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TIPGenericImageFetchRequest
{
@protected
    NSURL *_imageURL;
    NSString *_imageIdentifier;
    CGSize _targetDimensions;
    UIViewContentMode _targetContentMode;
    NSTimeInterval _timeToLive;
    TIPImageFetchOptions _options;
    NSDictionary<NSString *, id<TIPImageFetchProgressiveLoadingPolicy>> *_progressiveLoadingPolicies;
    id<TIPImageFetchTransformer> _transformer;
    TIPImageFetchLoadingSources _loadingSources;
    TIPImageFetchHydrationBlock _imageRequestHydrationBlock;
    NSDictionary<NSString *, id> *_decoderConfigMap;
}

@synthesize imageURL = _imageURL;
@synthesize imageIdentifier = _imageIdentifier;
@synthesize targetDimensions = _targetDimensions;
@synthesize targetContentMode = _targetContentMode;
@synthesize timeToLive = _timeToLive;
@synthesize options = _options;
@synthesize progressiveLoadingPolicies = _progressiveLoadingPolicies;
@synthesize transformer = _transformer;
@synthesize loadingSources = _loadingSources;
@synthesize imageRequestHydrationBlock = _imageRequestHydrationBlock;
@synthesize decoderConfigMap = _decoderConfigMap;

- (instancetype)initWithImageURL:(NSURL *)imageURL
{
    if (self = [super init]) {
        _imageURL = imageURL;
        _targetContentMode = UIViewContentModeCenter;
        _timeToLive = TIPTimeToLiveDefault;
        _options = TIPImageFetchNoOptions;
        _loadingSources = TIPImageFetchLoadingSourcesAll;
    }
    return self;
}

- (instancetype)initWithImageURL:(NSURL *)imageURL identifier:(nullable NSString *)imageIdentifier targetDimensions:(CGSize)dims targetContentMode:(UIViewContentMode)mode
{
    if (self = [self initWithImageURL:imageURL]) {
        _imageIdentifier = [imageIdentifier copy];
        _targetDimensions = dims;
        _targetContentMode = mode;
    }
    return self;
}

- (id)copy
{
    return [self copyWithZone:nil];
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

- (id)mutableCopy
{
    return [self mutableCopyWithZone:nil];
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone
{
    TIPMutableGenericImageFetchRequest *request = [[TIPMutableGenericImageFetchRequest allocWithZone:zone] initWithImageURL:self.imageURL];
    request.imageIdentifier = self.imageIdentifier;
    request.targetDimensions = self.targetDimensions;
    request.targetContentMode = self.targetContentMode;
    request.timeToLive = self.timeToLive;
    request.options = self.options;
    request.progressiveLoadingPolicies = self.progressiveLoadingPolicies;
    request.transformer = self.transformer;
    request.loadingSources = self.loadingSources;
    request.imageRequestHydrationBlock = self.imageRequestHydrationBlock;
    request.decoderConfigMap = self.decoderConfigMap;
    return request;
}

@end

@implementation TIPMutableGenericImageFetchRequest

@dynamic imageURL;
@dynamic imageIdentifier;
@dynamic targetDimensions;
@dynamic targetContentMode;
@dynamic timeToLive;
@dynamic options;
@dynamic progressiveLoadingPolicies;
@dynamic transformer;
@dynamic loadingSources;
@dynamic imageRequestHydrationBlock;
@dynamic decoderConfigMap;

- (void)setImageURL:(NSURL *)imageURL
{
    _imageURL = imageURL;
}

- (void)setImageIdentifier:(nullable NSString *)imageIdentifier
{
    _imageIdentifier = [imageIdentifier copy];
}

- (void)setTargetDimensions:(CGSize)targetDimensions
{
    _targetDimensions = targetDimensions;
}

- (void)setTargetContentMode:(UIViewContentMode)targetContentMode
{
    _targetContentMode = targetContentMode;
}

- (void)setTimeToLive:(NSTimeInterval)timeToLive
{
    _timeToLive = timeToLive;
}

- (void)setOptions:(TIPImageFetchOptions)options
{
    _options = options;
}

- (void)setProgressiveLoadingPolicies:(nullable NSDictionary<NSString *,id<TIPImageFetchProgressiveLoadingPolicy>> *)progressiveLoadingPolicies
{
    _progressiveLoadingPolicies = [progressiveLoadingPolicies copy];
}

- (void)setTransformer:(nullable id<TIPImageFetchTransformer>)transformer
{
    _transformer = transformer;
}

- (void)setLoadingSources:(TIPImageFetchLoadingSources)loadingSources
{
    _loadingSources = loadingSources;
}

- (void)setImageRequestHydrationBlock:(nullable TIPImageFetchHydrationBlock)imageRequestHydrationBlock
{
    _imageRequestHydrationBlock = [imageRequestHydrationBlock copy];
}

- (void)setDecoderConfigMap:(nullable NSDictionary<NSString *,id> *)decoderConfigMap
{
    _decoderConfigMap = [decoderConfigMap copy];
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TIPGenericImageFetchRequest *request = [[TIPGenericImageFetchRequest allocWithZone:zone] initWithImageURL:self.imageURL];
    request->_imageIdentifier = [self.imageIdentifier copyWithZone:zone];
    request->_targetDimensions = self.targetDimensions;
    request->_targetContentMode = self.targetContentMode;
    request->_timeToLive = self.timeToLive;
    request->_options = self.options;
    request->_progressiveLoadingPolicies = self.progressiveLoadingPolicies;
    request->_transformer = self.transformer;
    request->_loadingSources = self.loadingSources;
    request->_imageRequestHydrationBlock = self.imageRequestHydrationBlock;
    request->_decoderConfigMap = self.decoderConfigMap;
    return request;
}

@end

NS_ASSUME_NONNULL_END
