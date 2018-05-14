//
//  TIPImageFetchRequest.h
//  TwitterImagePipeline
//
//  Created on 1/21/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <TwitterImagePipeline/TIPDefinitions.h>
#import <TwitterImagePipeline/TIPProgressive.h>

@protocol TIPImageFetchOperationUnderlyingContext;
@protocol TIPImageFetchTransformer;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN const NSTimeInterval TIPTimeToLiveDefault; // 30 days

//! Block to call with the hydrated `NSURLRequest` when hydration is triggered
typedef void(^TIPImageFetchHydrationCompletionBlock)(NSURLRequest * __nullable hydratedRequest,
                                                     NSError * __nullable error);

//! Block to hydrate an `NSURLRequest` for a given _context_
typedef void(^TIPImageFetchHydrationBlock)(NSURLRequest *requestToHydrate,
                                           id<TIPImageFetchOperationUnderlyingContext> context,
                                           TIPImageFetchHydrationCompletionBlock complete);

/** Options for a `TIPImageFetchRequest` */
typedef NS_OPTIONS(NSInteger, TIPImageFetchOptions)
{
    /** No options - default behavior */
    TIPImageFetchNoOptions = 0,
    /** Don't reset the expiry when accessed */
    TIPImageFetchDoNotResetExpiryOnAccess = 1 << 0,
    /**
     When a matching `imageIdentifier` is fetched/stored that doesn't match this fetch's `imageURL`,
     clear this store request's results from cache.
     Useful for _"placeholder"_ fetches/stores that might have the same (or larger) dimensions as a
     non-placeholder fetch/store.
     */
    TIPImageFetchTreatAsPlaceholder = 1 << 1,
};

/**
 `TIPImageFetchRequest` is a protocol that is to be implemented by an object for encapsulating the
 relevant information for retrieving an image via a `TIPImagePipeline`.
 */
@protocol TIPImageFetchRequest <NSObject>

@required

/** The only required property is the `NSURL` of the image to load from the _Network_. */
@property (nonatomic, readonly) NSURL *imageURL;

@optional

/**
 The identifier for an image that is devoid of sizing related information.
 This will be used for matching against existing cached images.
 If not provided (or `nil`), `[imageURL absoluteString]` will be used instead.
 */
@property (nonatomic, readonly, copy, nullable) NSString *imageIdentifier;

/**
 The pixel dimensions (not points) of the target for displaying the image.
 Must be paired with `targetContentMode` to have any effect.
 This value (and `targetContentMode`) are used for scaling the source image to the size desired for
 the target (such as a `UIImageView`) and has no impact on what source image is loaded.
 If you do not provide target sizing information you risk having your target view scale the
 resulting `UIImage` on the main thread, which is expensive and will absolutely yield a drop in FPS.
 Default == `CGSizeZero` indicating the target's dimensions are unknown.
 */
@property (nonatomic, readonly) CGSize targetDimensions;

/**
 The `UIViewContentMode` of the target for displaying the image.
 Must be paired with `targetDimensions` to have any effect.
 This value (and `targetDimensions`) are used for scaling the source image to the size desired for
 the target (such as a `UIImageView`) and has no impact on what source image is loaded.
 If you do not provide target sizing information you risk having your target view scale the
 resulting `UIImage` on the main thread, which is expensive and will absolutely yield a drop in FPS.
 Default == `UIViewContentModeCenter` indicating the image won't be constrained to any specified
 dimensions.
 See `UIViewContentModeScaleToFill`, `UIViewContentModeScaleAspectFit` and/or
 `UIViewContentModeScaleAspectFill` for constrained content modes.
 @note only _targetContentMode_ values that have `UIViewContentModeScale*` will be scaled (others are just positional and do not scale)
 */
@property (nonatomic, readonly) UIViewContentMode targetContentMode;

/**
 The duration that the image will live in the `TIPImagePipeline`'s internal cache(s) if fetched from
 the _Network_. Default == `TIPTimeToLiveDefault`
 */
@property (nonatomic, readonly) NSTimeInterval timeToLive;

/**
 The options for the fetch.
 Default == `TIPImageFetchNoOptions`
 */
@property (nonatomic, readonly) TIPImageFetchOptions options;

/**
 The `TIPImageFetchProgressiveLoadingPolicy` instances for progressively loading images.
 The keys should be _TIPImageType_ values (which are `NSString` objects).
 Any unspecified _TIPImageType_ values will use the fallback policy for that type.
 Default == `nil`.
 Fallback is `[TIPImageFetchProgressiveLoadingPolicy defaultProgressiveLoadingPolicies]`
 See `TIPImageFetchDelegate` and `TIPImageTypes.h`
 */
@property (nonatomic, readonly, copy, nullable) NSDictionary<NSString *, id<TIPImageFetchProgressiveLoadingPolicy>> *progressiveLoadingPolicies;

/**
 Provide a `TIPImageFetchTransformer` to support transforming the fetched image.
 @note providing a transformer will scope what synchronous render cached images can be fetched
 based on the `tip_transformerIdentifier` of the transformer.
 */
@property (nonatomic, readonly, nullable) id<TIPImageFetchTransformer> transformer;

/**
 Specify where to load from.
 Default == `TIPImageFetchLoadingSourcesAll`
 */
@property (nonatomic, readonly) TIPImageFetchLoadingSources loadingSources;

/**
 The `TIPImageFetchHydrationBlock` to use when retrieving the image over the _Network_.
 Use this to modify the `NSURLRequest` that will be loaded over the _Network_.
 This can be valuable for providing auth to the _HTTP Request_ that will be sent.
 The `imageRequestHydrationBlock` MUST NOT change the `URL` nor the _HTTP Method_,
 otherwise doing so will yield an error.
 Default == `nil`
 */
@property (nonatomic, readonly, copy, nullable) TIPImageFetchHydrationBlock imageRequestHydrationBlock;

/**
 An optional decoder config map.
 Can be useful for custom decoder behavior.
 */
@property (nonatomic, readonly, copy, nullable) NSDictionary<NSString *, id> *decoderConfigMap;

@end

/**
 Extended TIPImageFetchRequest that enforces mutable target sizing properties being available.
 */
@protocol TIPMutableTargetSizingImageFetchRequest <TIPImageFetchRequest>

@required
/**
 The pixel dimensions (not points) of the target for displaying the image.
 Default should be `CGSizeZero` indicating the target's dimensions are unknown.
 See `[TIPImageFetchRequest targetDimensions]`
 */
@property (nonatomic) CGSize targetDimensions;
/**
 The `UIViewContentMode` of the target for displaying the image.
 Default should be `UIViewContentModeCenter` indicating the image won't be constrained to any
 specified dimensions.
 See `[TIPImageFetchRequest targetContentMode]`
 */
@property (nonatomic) UIViewContentMode targetContentMode;

@end

///! Convenience function to get the imageIdentifier from a `TIPImageFetchRequest`
NS_INLINE NSString *TIPImageFetchRequestGetImageIdentifier(id<TIPImageFetchRequest> request)
{
    NSString *imageIdentifier = nil;
    if ([request respondsToSelector:@selector(imageIdentifier)]) {
        imageIdentifier = request.imageIdentifier;
    }
    if (!imageIdentifier) {
        imageIdentifier = request.imageURL.absoluteString;
    }
    return imageIdentifier;
}

@class TIPMutableGenericImageFetchRequest;

/**
 * Generic fetch request
 */
@interface TIPGenericImageFetchRequest : NSObject <TIPImageFetchRequest, NSCopying, NSMutableCopying>

@property (nonatomic, readonly) NSURL *imageURL;
@property (nonatomic, readonly, copy, nullable) NSString *imageIdentifier;
@property (nonatomic, readonly) CGSize targetDimensions;
@property (nonatomic, readonly) UIViewContentMode targetContentMode;
@property (nonatomic, readonly) NSTimeInterval timeToLive;
@property (nonatomic, readonly) TIPImageFetchOptions options;
@property (nonatomic, readonly, copy, nullable) NSDictionary<NSString *, id<TIPImageFetchProgressiveLoadingPolicy>> *progressiveLoadingPolicies;
@property (nonatomic, readonly, nullable) id<TIPImageFetchTransformer> transformer;
@property (nonatomic, readonly) TIPImageFetchLoadingSources loadingSources;
@property (nonatomic, readonly, copy, nullable) TIPImageFetchHydrationBlock imageRequestHydrationBlock;
@property (nonatomic, readonly, copy, nullable) NSDictionary<NSString *, id> *decoderConfigMap;

- (instancetype)initWithImageURL:(NSURL *)imageURL
                      identifier:(nullable NSString *)imageIdentifier
                targetDimensions:(CGSize)dims
               targetContentMode:(UIViewContentMode)mode;
- (instancetype)initWithImageURL:(NSURL *)imageURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (TIPGenericImageFetchRequest *)copy;
- (TIPGenericImageFetchRequest *)copyWithZone:(nullable NSZone *)zone;

- (TIPMutableGenericImageFetchRequest *)mutableCopy;
- (TIPMutableGenericImageFetchRequest *)mutableCopyWithZone:(nullable NSZone *)zone;

@end

/**
 * Generic fetch request (mutable)
 */
@interface TIPMutableGenericImageFetchRequest : TIPGenericImageFetchRequest <TIPMutableTargetSizingImageFetchRequest>

@property (nonatomic) NSURL *imageURL;
@property (nonatomic, copy, nullable) NSString *imageIdentifier;
@property (nonatomic) CGSize targetDimensions;
@property (nonatomic) UIViewContentMode targetContentMode;
@property (nonatomic) NSTimeInterval timeToLive;
@property (nonatomic) TIPImageFetchOptions options;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id<TIPImageFetchProgressiveLoadingPolicy>> *progressiveLoadingPolicies;
@property (nonatomic, nullable) id<TIPImageFetchTransformer> transformer;
@property (nonatomic) TIPImageFetchLoadingSources loadingSources;
@property (nonatomic, copy, nullable) TIPImageFetchHydrationBlock imageRequestHydrationBlock;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *decoderConfigMap;

@end

NS_ASSUME_NONNULL_END
