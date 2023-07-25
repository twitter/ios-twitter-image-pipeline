//
//  TIPImagePipeline.h
//  TwitterImagePipeline
//
//  Created on 2/5/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIImage.h>
#import <UIKit/UIView.h>

@protocol TIPImageFetchRequest;
@protocol TIPImageStoreRequest;
@protocol TIPImageFetchDelegate;
@protocol TIPImageAdditionalCache;
@protocol TIPImagePipelineObserver;
@class TIPImageFetchOperation;
@class TIPImageContainer;

NS_ASSUME_NONNULL_BEGIN

//! Completion block for a `TIPImageFetchOperation` that didn't use a delegate
typedef void(^TIPImagePipelineFetchCompletionBlock)(id<TIPImageFetchResult> __nullable finalResult,  NSError * __nullable error);
//! Completion block for an image pipeline operation
typedef void(^TIPImagePipelineOperationCompletionBlock)(NSObject<TIPDependencyOperation> *op, BOOL succeeded, NSError * __nullable error);
//! Completion block for copying a file from an image pipeline's disk cache to a _temporaryFilePath_
typedef void(^TIPImagePipelineCopyFileCompletionBlock)(NSString * __nullable temporaryFilePath, NSError * __nullable error);

//! Notification when an image was store to the pipeline's cache(s). `object` => `TIPImagePipeline`
FOUNDATION_EXTERN NSString * const TIPImagePipelineDidStoreCachedImageNotification;
//! Notification when a pipeline was created. `object` => `TIPImagePipeline`
FOUNDATION_EXTERN NSString * const TIPImagePipelineDidStandUpImagePipelineNotification;
//! Notification when a pipeline was destroyed. `object` => `nil`
FOUNDATION_EXTERN NSString * const TIPImagePipelineDidTearDownImagePipelineNotification;

//! Key to the relevant image's identifier, `NSString`
FOUNDATION_EXTERN NSString * const TIPImagePipelineImageIdentifierNotificationKey;
//! Key to the relevant image's URL, `NSURL`
FOUNDATION_EXTERN NSString * const TIPImagePipelineImageURLNotificationKey;
//! Key to the relevant image's dimensions (in pixels), `NSValue` wrapping a `CGSize`
FOUNDATION_EXTERN NSString * const TIPImagePipelineImageDimensionsNotificationKey;
//! Key to the relevant image's container, `TIPImageContainer`
FOUNDATION_EXTERN NSString * const TIPImagePipelineImageContainerNotificationKey;
//! Key to if the relevant image was manually stored, `NSNumber` wrapping a `BOOL`
FOUNDATION_EXTERN NSString * const TIPImagePipelineImageWasManuallyStoredNotificationKey;
//! Key to the relevant image pipeline's identifier, `NSString`
FOUNDATION_EXTERN NSString * const TIPImagePipelineImagePipelineIdentifierNotificationKey;
//! Key to indicate if the relevant image was a placeholder image
FOUNDATION_EXTERN NSString * const TIPImagePipelineImageTreatAsPlaceholderNofiticationKey;

/**
 A pipeline object is the encapsulation of fetching and storing images via requests.
 It encapsulates the caches and networking for fetching and storing operations to utilize.

 ## Execution

 When a fetch is made, the operation will traverse the pipelines caches looking for the desired
 image.  If not found, or a different variant is desired, the operation will proceed to download
 from the network.  Wherever an image is loaded from, it will percolate the loaded image up through
 the caches for reuse concurrently as it vends the resulting image to a delegate or block. The
 order is:

    1. Rendered Memory Cache (synchronously accessed)
    2. Image Data Memory Cache
    3. On Disk Cache
    4. Other pipeline disk caches
    5. Additional Cache(s)
    6. Network

 ## Construction / Reuse

 It is up to the framework consumer to construct and reuse pipelines based on their needs.
 Pipelines support siloing (keeping caches separate), if multiple pipelines are desired.
 The simplest option is to create a single shared pipeline for reuse during the lifetime of the app.

 Here's an example of having a global pipeline for a specific use case (in this example, Avatars):

 @interface AvatarImagePipeline : TIPImagePipeline

 + (instancetype)sharedAvatarPipeline;

 @end

 @implementation AvatarImagePipeline

 + (instancetype)sharedAvatarPipeline
 {
    // Singleton for the Avatar Pipeline

    static AvatarImagePipeline *sPipeline;
    static dispatch_once_t sToken;
    dispatch_once(&sToken, ^{
        sPipeline = [[AvatarImagePipeline alloc] initWithIdentifier:@"com.myapplication.pipeline"];
        sPipeline.additionalCaches = @[ [LegacyAvatarCache sharedAvatarCache] ];
    });
    return sPipeline;
 }

 - (void)fetchImageWithOperation:(TIPImageFetchOperation *)op
 {
     // here's a contrived example of how subclassing might be useful

     NSArray<NSOperation *> *globalHighPriorityOperations = AppGlobalRunningHighPriorityOperations();
     for (NSOperation *dependency in globalHighPriorityOperations) {
       [op addDependency:dependency];
     }
     [super fetchImageOperation:op];
 }

 @end

 ## Using `TIPImagePipeline` objects

 When using _TIP_, there are 2 ways to do image loading.  One is to fetch using a `TIPImagePipeline`
 directly and having a delegate or completion block for handling decisions and results.  Second
 is to use the `TIPImageView` combined with a `TIPImageViewFetchHelper` which encapsulates the
 common logic for tying images fetches to a target image view via a delegate and data source
 pattern.  The first option gives you greater flexibility in how to handle the fetched image, while
 the latter is an easier plug and play.  Both options, however, are built on the use of a
 `TIPImagePipeline` and `TIPImageFetchRequest` requests.

 ## Notifications

 # TIPImagePipelineDidStoreCachedImageNotification

 The `TIPImagePipelineDidStoreCachedImageNotification` is sent whenever an image is cached.
 The notification's `userInfo` dictionary will carry context regarding the image that was cached as
 well as whether the image was manually cached or automatically cached
 (`TIPImagePipelineImageWasManuallyStoredNotificationKey`).

 # TIPImagePipelineDidStandUpImagePipelineNotification

 The `TIPImagePipelineDidStandUpImagePipelineNotification` is sent whenever a new `TIPImagePipeline`
 is initialized.  The _object_ will be the `TIPImagePipeline` and
 `TIPImagePipelineImagePipelineIdentifierNotificationKey` will be populated in the _userInfo_.

 # TIPImagePipelineDidTearDownImagePipelineNotification

 The `TIPImagePipelineDidStandUpImagePipelineNotification` is sent whenever a new `TIPImagePipeline`
 is initialized.  The _object_ will be `nil` and
 `TIPImagePipelineImagePipelineIdentifierNotificationKey` will be populated in the _userInfo_.

 */
@interface TIPImagePipeline : NSObject

#pragma mark Properties

/**
 Additional custom caches that can be specified for additional locations for the _pipeline_ to
 attempt to read an image from.  The _pipeline_ does not write to these additional caches.
 */
@property (atomic, copy, nullable) NSArray<id<TIPImageAdditionalCache>> *additionalCaches;
/**
 An optional observer object to be notified as the image pipeline fetches and/or stores images.
 Callbacks are not synchronized, that is the responsibility of the observer.
 */
@property (atomic, nullable) id<TIPImagePipelineObserver> observer;

/** The identifier of the _pipeline_.  __See Also:__ `initWithIdentifier:` */
@property (nonatomic, readonly, copy) NSString *identifier;

#pragma mark Init

/**
 Designated initializer for the _image pipeline_.

 @param identifier The identifier for the pipeline.
 _identifier_ must be composed of ASCII alpha, numeric, `'.'`, `'_'`, and `'-'` characters.
 Other characters will yield a `nil` image pipeline.
 Also, no two image pipelines can have the same _identifier_,
 so initializing with an existing _identifier_ will yield a `nil` image pipeline too.

 @return an _image pipeline_ ready for fetching and storing images.
 */
- (nullable instancetype)initWithIdentifier:(NSString *)identifier NS_DESIGNATED_INITIALIZER;

/** `NS_UNAVAILABLE` */
- (instancetype)init NS_UNAVAILABLE;
/** `NS_UNAVAILABLE` */
+ (instancetype)new NS_UNAVAILABLE;

#pragma mark Fetch

/**
 Construct a new `TIPImageFetchOperation` for fetching an image with this `TIPImagePipeline`.
 See `fetchImageWithOperation:` for starting the operation.

 Subclasses can override this method in order to customize the parameters
 (_request_, _context_ and/or _delegate_).
 Must finish the override by returning a call to super.

 @param request The details of what image to request
 @param context An additional object for context, optional
 @param delegate The delegate for all callbacks

 @return A `TIPImageFetchOperation` for supporting cancellation, maintaining state, offering dynamic
 priority and providing support for `NSOperation` based dependencies

 @note The _delegate_ is weakly held by the vended `TIPImageFetchOperation` and the operation will
 be cancelled if the _delegate_ `deallocates` before the operation has finished.
 */
- (TIPImageFetchOperation *)operationWithRequest:(id<TIPImageFetchRequest>)request
                                         context:(nullable id)context
                                        delegate:(nullable id<TIPImageFetchDelegate>)delegate NS_REQUIRES_SUPER;
/**
 Same as `operationWithRequest:context:delegate:` but without the benefit of all the callbacks of a
 delegate, just a simple callback block.  This method calls into the delegate variation, so
 subclasses should not need to override this method.
 */
- (TIPImageFetchOperation *)operationWithRequest:(id<TIPImageFetchRequest>)request
                                         context:(nullable id)context
                                      completion:(nullable TIPImagePipelineFetchCompletionBlock)completion;

/**
 Fetch an image by starting the provided operation.  All callbacks to the delegate are made on the
 main queue, with the exception of
 `imageFetchOperation:shouldLoadProgressivelyWithIdentifier:URL:imageType:originalDimensions:`.

 The order of operations for the fetch operation is as follows:

 1. Synchronously attempt to load the already rendered image from memory (from the main thread)
 2. Asynchronously attempt to load from memory and render
 3. Asynchronously attempt to load from disk and render
 4. Asynchronously attempt to load from other pipeline disk caches and render
 5. Asynchronously attempt to load from the specified "additional caches" and render
 6. Asynchronously attempt to load from network and render

 _6_ can also do progressive loading, if supported and enabled by the _delegate_ and _request_

 See `operationWithRequest:context:delegate:` for constructing a `TIPImageFetchOperation`.

 @note Throws an `NSInvalidArgumentException` if the provided _op_ is `nil` or was not constructed by this `TIPImagePipeline`.

 @param op The `TIPImageFetchOperation` to start.
 */
- (void)fetchImageWithOperation:(TIPImageFetchOperation *)op;

#pragma mark Manual Store / Move

/**
 Store an image with the provided request.  The storing is performed asynchronously.

 @param request The store request for what image to store
 @param completion The callback for when the storing has been performed, called from the main queue

 @return an opaque _Operation_ for the store operation.
 The vended `TIPDependencyOperation` supports being made a dependency,
 being waited on for completion, and KVO for finishing and executing transitions.
 */
- (NSObject<TIPDependencyOperation> *)storeImageWithRequest:(id<TIPImageStoreRequest>)request
                                                 completion:(nullable TIPImagePipelineOperationCompletionBlock)completion;

/**
 Change the `imageIdentifier` of an existing cached image.

 @param currentIdentifier the identifier of the current cached image
 @param newIdentifier the identifier of change the cached image to using
 @param completion the callback for when the update has completed/failed, called from the main queue

 @return an opaque _Operation_ for the change operation.
 The vended `TIPDependencyOperation` supports being made a dependency,
 being waited on for completion, and KVO for finishing and executing transitions.
 */
- (NSObject<TIPDependencyOperation> *)changeIdentifierForImageWithIdentifier:(NSString *)currentIdentifier
                                                                toIdentifier:(NSString *)newIdentifier
                                                                  completion:(nullable TIPImagePipelineOperationCompletionBlock)completion;

#pragma mark Manual Purge

/**
 Asynchronously clears all cached image representations matching the given _imageIdentifier_.

 @param imageIdentifier The image identifier to match against when clearing cached images
 */
- (void)clearImageWithIdentifier:(NSString *)imageIdentifier;

/**
 Clear the rendered memory cache image representation matching the given _imageIdentifier_.

 @param imageIdentifier The image identifier to match against when clearing a rendered cache image entry
 */
- (void)clearRenderedMemoryCacheImageWithIdentifier:(NSString *)imageIdentifier;

/**
 Dirty the rendered memory cache image representation matching the given _imageIdentifier_.

 @param imageIdentifier The image identifier to match against when dirtying a rendered cache image entry
 */
- (void)dirtyRenderedMemoryCacheImageWithIdentifier:(NSString *)imageIdentifier;

/**
 Asynchronously clears the memory caches.
 Memory caching is composed of two separate caches:
 1) for rendered images that can be synchronously accessed if the already sized image is available
 2) for the image data of the largest encountered variant of an image (by identifier) that is asynchronously accessed.
 This method clears both of these caches.
 */
- (void)clearMemoryCaches;

/**
 Asynchronously clears the disk cache.
 */
- (void)clearDiskCache;

#pragma mark Access On Disk Image File

/**
 Copy the on disk cache's file entry to a temporary file.

 _completion_ will either be provided a _temporaryFilePath_ or an _error_.
 If the _temporaryFilePath_ is not `nil`, the file will be at the location for the duration of the
 _completion_ callback's execution.
 After the block returns, the temporary file (if not moved) will be deleted.
 You should either read the file or move the file to a different location within the _completion_
 block.

 @param imageIdentifier the identifier of the entry to copy
 @param completion the completion block when the copy completes.
 This block will be called back on a background thread.
 */
- (void)copyDiskCacheFileWithIdentifier:(NSString *)imageIdentifier
                             completion:(nullable TIPImagePipelineCopyFileCompletionBlock)completion;

#pragma mark Access Known Image Pipeline References

/**
 Asynchronously get all the known image pipelines by their identifiers.
 These identifiers include active image pipeline instances as well as inactive instances
 (whose cache costs are not considered with cache capping).

 @param callback the callback that will be called asynchronously on the main thread with the
 complete list of all known identifiers.
 */
+ (void)getKnownImagePipelineIdentifiers:(void (^)(NSSet<NSString *> *identifiers))callback;

@end

#pragma mark - TIPImagePipeline extended support

@class TIPImagePipelineInspectionResult;

//! Callback block for `[TIPImagePipeline inspect:]` with inspection results
typedef void(^TIPImagePipelineInspectionCallback)(TIPImagePipelineInspectionResult * __nullable result);

/**
 Category for inspecting a specific `TIPImagePipeline`.  See `TIPGlobalConfiguration(Inspect)` too.
 */
@interface TIPImagePipeline (Inspect)

/**
 Asynchronously inspect the `TIPImagePipeline` to gather information about it.

 @param callback A callback to be called with a `TIPImagePipelineInspectionResult`
 */
- (void)inspect:(TIPImagePipelineInspectionCallback)callback;

@end

#pragma mark - TIPImagePipeline support declarations

/**
 `TIPImagePipelineObserver` is a protocol that provides callbacks for when events occur on the image
 pipeline that may need to be observed.
 Callbacks are not synchronized, that is the responsibility of the observer.
 */
@protocol TIPImagePipelineObserver <NSObject>

@optional

/**
 Callback when a `TIPImageFetchOperation` has started.
 */
- (void)tip_imageFetchOperationDidStart:(TIPImageFetchOperation *)op;

/**
 Callback when a `TIPImageFetchOperation` has finished.
 */
- (void)tip_imageFetchOperationDidFinish:(TIPImageFetchOperation *)op;

/**
 Callback when a `TIPImageFetchOperation` has started downloading an image.

 @param op The `TIPImageFetchOperation` that started
 @param URL The `NSURL` of the image that started being downloaded
 */
- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
  didStartDownloadingImageAtURL:(NSURL *)URL;

/**
 Callback when a `TIPImageFetchOperation` has finished downloading an image.

 See `TIPImageTypes.h`

 @param op The `TIPImageFetchOperation` that completed
 @param URL The `NSURL` of the image that was downloaded
 @param type The _TIPImageType_ of the image that was downloaded
 @param byteSize The size in bytes of the image that was downloaded
 @param dimensions The size in pixels of the image that was downloaded
 @param wasResumed Whether or not the download was a resumed download
 */
- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
 didFinishDownloadingImageAtURL:(NSURL *)URL
                      imageType:(NSString *)type
                    sizeInBytes:(NSUInteger)byteSize
                     dimensions:(CGSize)dimensions
                     wasResumed:(BOOL)wasResumed;

@end

typedef void(^TIPImageAdditionalCacheFetchCompletion)(UIImage * __nullable image);

/**
 `TIPImageAdditionalCache` is a protocol that provides backwards compatibility support to
 `TIPImagePipeline` by permitting an object implementing the protocol to be used for fetching
 (but not storing) images.  See `[TIPImagePipeline additionalCache]`.
 */
@protocol TIPImageAdditionalCache <NSObject>

@optional
/**
 Method for retrieving an image given a specific `NSURL`.

    typedef void(^TIPImageAdditionalCacheFetchCompletion)(UIImage *image);

 Provide either the `UIImage` or `nil`.  The `completion` callback can be called asynchronously,
 but it isn't required and calling it synchronously is fine too.

 @param URL        the `NSURL` to retrieve an image with
 @param completion the completion block to execute when the image is either retrieved or not
 */
- (void)tip_retrieveImageForURL:(NSURL *)URL
                     completion:(TIPImageAdditionalCacheFetchCompletion)completion;

@end

NS_ASSUME_NONNULL_END
