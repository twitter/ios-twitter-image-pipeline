//
//  TIPImageFetchRequest.h
//  TwitterImagePipeline
//
//  Created on 1/21/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import "TIPDefinitions.h"
#import "TIPProgressive.h"

@protocol TIPImageFetchOperationUnderlyingContext;

//! Block to call with the hydrated `NSURLRequest` when hydration is triggered
typedef void(^TIPImageFetchHydrationCompletionBlock)(NSURLRequest * __nullable hydratedRequest, NSError * __nullable error);

//! Block to hydrate an `NSURLRequest` for a given _context_
typedef void(^TIPImageFetchHydrationBlock)(NSURLRequest * __nonnull requestToHydrate, id<TIPImageFetchOperationUnderlyingContext> __nonnull context, TIPImageFetchHydrationCompletionBlock __nonnull complete);

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
@property (nonnull, nonatomic, readonly) NSURL *imageURL;

@optional

/**
 The identifier for an image that is devoid of sizing related information.
 This will be used for matching against existing cached images.
 If not provided (or `nil`), `[imageURL absoluteString]` will be used instead.
 */
@property (nullable, nonatomic, readonly, copy) NSString *imageIdentifier;

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
@property (nullable, nonatomic, readonly, copy) NSDictionary<NSString *, id<TIPImageFetchProgressiveLoadingPolicy>> *progressiveLoadingPolicies;

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
@property (nullable, nonatomic, copy, readonly) TIPImageFetchHydrationBlock imageRequestHydrationBlock;

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
