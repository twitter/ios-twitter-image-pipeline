//
//  TIPImageFetchRequest.m
//  TwitterImagePipeline
//
//  Created on 1/21/16.
//  Copyright © 2020 Twitter. All rights reserved.
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
    TIPImageFetchAuthorizationBlock _imageRequestAuthorizationBlock;
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
@synthesize imageRequestAuthorizationBlock = _imageRequestAuthorizationBlock;
@synthesize decoderConfigMap = _decoderConfigMap;

+ (instancetype)genericImageFetchRequestWithRequest:(id<TIPImageFetchRequest>)request
{
    TIPGenericImageFetchRequest *genericRequest = [[[self class] alloc] initWithImageURL:request.imageURL];

#define COPY_PROP(prop) \
    if ([request respondsToSelector:@selector( prop )]) { \
        genericRequest->_##prop = [request. prop copy]; \
    }
#define GET_PROP(prop) \
    if ([request respondsToSelector:@selector( prop )]) { \
        genericRequest->_##prop = request. prop ; \
    }

    COPY_PROP(imageIdentifier);
    GET_PROP(targetDimensions);
    GET_PROP(targetContentMode);
    GET_PROP(timeToLive);
    GET_PROP(options);
    COPY_PROP(progressiveLoadingPolicies);
    GET_PROP(transformer);
    GET_PROP(loadingSources);
    COPY_PROP(imageRequestHydrationBlock);
    COPY_PROP(imageRequestAuthorizationBlock);
    COPY_PROP(decoderConfigMap);

#undef COPY_PROP
#undef GET_PROP

    return genericRequest;

}

- (instancetype)initWithImageURL:(NSURL *)imageURL
{
    return [self initWithImageURL:imageURL identifier:nil targetDimensions:CGSizeZero targetContentMode:UIViewContentModeCenter];
}

- (instancetype)initWithImageURL:(NSURL *)imageURL
                      identifier:(nullable NSString *)imageIdentifier
                targetDimensions:(CGSize)dims
               targetContentMode:(UIViewContentMode)mode
{
    if (self = [super init]) {
        _imageURL = imageURL;
        _imageIdentifier = [imageIdentifier copy];
        _targetDimensions = dims;
        _targetContentMode = mode;
        _timeToLive = TIPTimeToLiveDefault;
        _options = TIPImageFetchNoOptions;
        _loadingSources = TIPImageFetchLoadingSourcesAll;
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
    request.imageRequestAuthorizationBlock = self.imageRequestAuthorizationBlock;
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
@dynamic imageRequestAuthorizationBlock;
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

- (void)setImageRequestAuthorizationBlock:(nullable TIPImageFetchAuthorizationBlock)imageRequestAuthorizationBlock
{
    _imageRequestAuthorizationBlock = [imageRequestAuthorizationBlock copy];
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
    request->_imageRequestAuthorizationBlock = self.imageRequestAuthorizationBlock;
    request->_decoderConfigMap = self.decoderConfigMap;
    return request;
}

@end

NS_ASSUME_NONNULL_END
