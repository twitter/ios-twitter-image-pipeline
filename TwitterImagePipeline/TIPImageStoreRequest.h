//
//  TIPImageStoreRequest.h
//  TwitterImagePipeline
//
//  Created on 1/21/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol TIPImageStoreRequestHydrater;

NS_ASSUME_NONNULL_BEGIN

/** store options */
typedef NS_OPTIONS(NSInteger, TIPImageStoreOptions)
{
    /** No options - default behavior */
    TIPImageStoreNoOptions = 0,
    /** Don't reset the expiry when accessed */
    TIPImageStoreDoNotResetExpiryOnAccess = 1 << 0,
    /**
     When a matching `imageIdentifier` is fetched/stored that doesn't match this fetch's `imageURL`,
     clear this store request's results from cache.
     Useful for _"placeholder"_ fetches/stores that might have the same (or larger) dimensions as a
     non-placeholder fetch/store.
     */
    TIPImageStoreTreatAsPlaceholder = 1 << 1,
};

/**
 `TIPImageStoreRequest` is a protocol that is to be implemented by an object for encapsulating the
 relevant information for storing an image.

 The store request requires the `imageURL` be provided, but also at least one of `image`,
 `imageData` or `imageFilePath`.

 # Providing multiple representations

 `TIPImageStoreRequest` supports uploading multiple forms (`UIImage`, `NSData` and/or a path as an
 `NSString`).  This can provide optimizations in computation by reducing how many times the CPU
 needs to decode/encode an image for the different representations that are stored in the caches.

 ## Logic for chosing the Memory Cache representation

 * If `image` is provided, use that `UIImage`
 * If `imageData` is provided, construct a `UIImage` with that `NSData` and use it
 * If `imageFilePath` is provided, construct a `UIImage` with that file path and use it

 ## Logic for chosing the Disk Cache representation

 * If `imageFilePath` is provided, copy that file to the disk cache
 * If `imageData` is provided, write that data to the disk cache
 * If `image` is provided, serialize the `image` to `NSData`, then write that data to the disk cache

 */
@protocol TIPImageStoreRequest <NSObject>

@required

/**
 The `NSURL` of the image.
 This doesn't necessarily have to match the _URL_ of where the image would be retrieved from over
 the _Network_.

 @note the `imageURL` is actually less important with storage than it is with retrieval.
 The more important choice is what `imageIdentifier` to provide since that will be the primary
 mechanism for matching image fetches to the internal cache(s).  Not providing an `imageIdentifier`
 (or `nil`) will fall back to using `[imageURL absoluteString]`.
 */
@property (nonatomic, readonly) NSURL *imageURL;

@optional

/**
 The identifier for an image that is devoid of sizing related information.
 This will be used for matching against existing cached images.
 If not provided (or `nil`), `[imageURL absoluteString]` will be used instead.
 */
@property (nullable, nonatomic, readonly, copy) NSString *imageIdentifier;

/**
 The duration that the image will live in the `TIPImagePipeline`'s internal cache(s).
 Default == 30 days
 */
@property (nonatomic, readonly) NSTimeInterval timeToLive;

/**
 The options for the store.
 Default == `TIPImageStoreNoOptions`
 */
@property (nonatomic, readonly) TIPImageStoreOptions options;

@optional // one of the following is required

/**
 The `UIImage` representation for storing.
 Optionally providing the `imageType` property will specify how to encode the image to disk.
 Takes precedence over `imageData` and `imageFilePath`.
 */
@property (nullable, nonatomic, readonly) UIImage *image; // TODO: refactor to be a `TIPImageContainer` instead of a `UIImage`

/**
 The `NSData` of encoded image bytes for storing.
 MUST provide the `imageDimensions` property too for the cache metadata.
 Takes precedence over `imageFilePath`, but is subservient to `image`.
 */
@property (nullable, nonatomic, readonly) NSData *imageData;

/**
 The `NSString` file path to the encoded image stored on disk.
 MUST provide the `imageDimensions` property too for the cache metadata.
 Is subservient to `image` and `imageData`.
 */
@property (nullable, nonatomic, readonly, copy) NSString *imageFilePath;

@optional // methods that accompany the above image methods

/**
 The type of image to encode the provided `image` as, when stored to the disk cache.
 Default == `nil`, which is the same as _automatic_
 (currently: _GIF_ for animated images, _PNG_ for images w/ alpha, _JPEG_ with 85% quality for
 everything else).
 See `TIPImageTypes.h`
 */
@property (nonatomic, nullable, copy, readonly) NSString *imageType;

/**
 The pixel dimensions (not points) of the image itself.
 MUST be provided for either `imageData` or `imageFilePath` based store requests.
 */
@property (nonatomic, readonly) CGSize imageDimensions;

/**
 The loop count if the `image` is animated.
 Only applies to `image` based store requests.
 Default == `0` (aka loop forever)
 */
@property (nonatomic, readonly) NSUInteger animationLoopCount;

/**
 The durations (as `float` `NSNumber` objects) matching the frames of the `image` to be stored.
 Only applies to `image` based store requests.
 Default == calculated based on the `image` object's `duration` property
 */
@property (nullable, nonatomic, readonly, copy) NSArray<NSNumber *> *animationFrameDurations;

@optional // methods for extending work done in a store operation

/**
 The hydrater to asynchronously prepare the request for the store operation to execute on.
 See `TIPImageStoreRequestHydrater`.
 Default == `nil`.
 */
@property (nullable, nonatomic, readonly) id<TIPImageStoreRequestHydrater> hydrater;

/**
 A decoder config map for cases when we need to decode the image for memory cache storage
 */
@property (nullable, nonatomic, readonly, copy) NSDictionary<NSString *, id> *decoderConfigMap;

@end

///! Convenience function to get the imageIdentifier from a `TIPImageStoreRequest`
NS_INLINE NSString *TIPImageStoreRequestGetImageIdentifier(id<TIPImageStoreRequest> request)
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

/** `TIPImageStoreRequest` specifically for `UIImage` based store requests */
@protocol TIPImageObjectStoreRequest <TIPImageStoreRequest>

@required
/** Required */
@property (nullable, nonatomic, readonly) UIImage *image;
/** Required */
@property (nullable, nonatomic, copy, readonly) NSString *imageType;

@optional
/** Optional */
@property (nonatomic, readonly) NSUInteger animationLoopCount;
/** Optional */
@property (nullable, nonatomic, readonly, copy) NSArray<NSNumber *> *animationFrameDurations;

@end

/** `TIPImageStoreRequest` specifically for `NSData` based store requests */
@protocol TIPImageDataStoreRequest <TIPImageStoreRequest>
@required
/** Required */
@property (nullable, nonatomic, readonly) NSData *imageData;
/** Required */
@property (nonatomic, readonly) CGSize imageDimensions;
@end

/** `TIPImageStoreRequest` specifically for file path based store requests */
@protocol TIPImageFileStoreRequest <TIPImageStoreRequest>
@required
/** Required */
@property (nullable, nonatomic, readonly, copy) NSString *imageFilePath;
/** Required */
@property (nonatomic, readonly) CGSize imageDimensions;
@end

//! Completion callback to call when the _request_ being stored has hydrated
typedef void(^TIPImageStoreHydraterCompletionBlock)(id<TIPImageStoreRequest> __nullable request,
                                                    NSError *__nullable error);

/**
 A protocol for extending the work that a store operation can perform on a `TIPImageStoreRequest`.
 */
@protocol TIPImageStoreRequestHydrater <NSObject>

@required

/**
 Method to implement that offers asynchronous (or synchronous) time to prepare the store request for
 execution on the image store operation.

 Provide either an `NSError` to the _error_ argument, a new `TIPImageStoreRequest` to use or `nil`
 to use the original _request_.

 @note Hydration does _NOT_ cascade. That is, if the hydrater provides a new `TIPImageStoreRequest`
 that has a `hydrater` value provided, that subsequent `hydrater` will be ignored.

 @param request The original `TIPImageStoreRequest`
 @param pipeline The `TIPImagePipeline` executing the storage
 @param completion The completionBlock that must be called whenever hydration has completed.
 */
- (void)tip_hydrateImageStoreRequest:(id<TIPImageStoreRequest>)request
                       imagePipeline:(TIPImagePipeline *)pipeline
                          completion:(TIPImageStoreHydraterCompletionBlock)completion;

@end

NS_ASSUME_NONNULL_END
