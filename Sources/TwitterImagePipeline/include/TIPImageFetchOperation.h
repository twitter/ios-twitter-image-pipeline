//
//  TIPImageFetchOperation.h
//  TwitterImagePipeline
//
//  Created on 3/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <TIPDefinitions.h>
#import <TIPImageContainer.h>
#import <TIPImageUtils.h>
#import <TIPSafeOperation.h>
#import <UIKit/UIImage.h>

@class TIPImagePipeline;
@class TIPImageFetchMetrics;
@protocol TIPImageFetchRequest;
@protocol TIPImageFetchDelegate;
@protocol TIPImageFetchResult;

NS_ASSUME_NONNULL_BEGIN

/**
 Enum of different states the `TIPImageFetchOperation` can transition through.

 __TIPImageFetchOperationStateIsActive(state)__

 Helper macro to determine if the `TIPImageFetchOperationState` is an active (busy) state

 __TIPImageFetchOperationStateIsFinished(state)__

 Helper macro to determine if the `TIPImageFetchOperationState` is a finished state
 */
typedef NS_ENUM(NSInteger, TIPImageFetchOperationState){
    /** The operation is idle (has not yet started) */
    TIPImageFetchOperationStateIdle = 0,
    /** The operation is starting */
    TIPImageFetchOperationStateStarting,
    /** The operation is looking at the memory cache for a match */
    TIPImageFetchOperationStateLoadingFromMemory,
    /** The operation is looking at the disk cache for a match */
    TIPImageFetchOperationStateLoadingFromDisk,
    /**
     The operation is looking at the additional cache (if set on the `TIPImagePipeline`) for a match
     */
    TIPImageFetchOperationStateLoadingFromAdditionalCache,
    /** The operation is retrieving the image from the _Network_ */
    TIPImageFetchOperationStateLoadingFromNetwork,
    /** The operation was cancelled */
    TIPImageFetchOperationStateCancelled = -1,
    /** The operation failed */
    TIPImageFetchOperationStateFailed = -2,
    /** The operation succeeded */
    TIPImageFetchOperationStateSucceeded = -100
};

//! Test if the `TIPImageFetchOperationState` is an active state
#define TIPImageFetchOperationStateIsActive(state) ((state) > 0)
//! Test if the `TIPImageFetchOperationState` is a finished state
#define TIPImageFetchOperationStateIsFinished(state) ((state) < 0)

/**
 The `NSOperation` subclass for encapsulating the work of fetching an image.
 */
@interface TIPImageFetchOperation : TIPSafeOperation

/** The state of the operation (KVO compliant) */
@property (nonatomic, readonly) TIPImageFetchOperationState state;

/** The request for the operation */
@property (nonatomic, readonly) id<TIPImageFetchRequest> request;

/**
 The delegate for the operation.
 The delegate is weakly held and will `cancel` the operation when it is deallocated.
 */
@property (atomic, readonly, weak, nullable) id<TIPImageFetchDelegate> delegate;

/** The image pipeline for the operation */
@property (nonatomic, readonly) TIPImagePipeline *imagePipeline;

/** Result data for preview load */
@property (nonatomic, readonly, nullable) id<TIPImageFetchResult> previewResult;
/** Result data for progressive load or first animated frame load */
@property (nonatomic, readonly, nullable) id<TIPImageFetchResult> progressiveResult;
/** Result data for the final load */
@property (nonatomic, readonly, nullable) id<TIPImageFetchResult> finalResult;

/** Set as soon as the type is detected. */
@property (nonatomic, nullable, copy, readonly) NSString *networkLoadImageType;
/** The dimensions of the image loading/loaded via the network. */
@property (nonatomic, readonly) CGSize networkImageOriginalDimensions;

/** The number of frames loaded thus far */
@property (nonatomic, readonly) NSUInteger progressiveFrameCount;
/** The progress of what has been loaded from the _Network_ */
@property (nonatomic, readonly) float progress;
/** The error that occurred preventing the image from being loaded */
@property (nonatomic, readonly, nullable) NSError *error;

/**
 The metrics providing insight into how this image fetch performed.
 `nil` until the operation completes.
 */
@property (nonatomic, readonly, nullable) TIPImageFetchMetrics *metrics;

/**
 The amount of time this operation has spent in its queue idle (waiting to start).
 */
@property (atomic, readonly) NSTimeInterval timeSpentIdleInQueue;
/**
 The amount of time this operation has spent executing.
 */
@property (atomic, readonly) NSTimeInterval timeSpentExecuting;

/**
 The priority of the operation, which can be modified at any time.
 Default == `NSOperationQueuePriorityNormal`.
 */
@property (nonatomic) NSOperationQueuePriority priority;

/**
 Unavailable.
 Queue priority is managed by the `priority` property until the operation is enqueued
 */
@property NSOperationQueuePriority queuePriority NS_UNAVAILABLE;
/**
 Unavailable.
 Quality of service is managed by the `priority` property until the operation is enqueued
 */
@property NSQualityOfService qualityOfService NS_UNAVAILABLE;

/** The arbitrary context that the caller wishes to associate with the operation */
@property (nonatomic, nullable) id context;

/** Initialization is private to the _Twitter Image Pipeline_ so `init` is unavailable. */
- (instancetype)init NS_UNAVAILABLE;
/** Initialization is private to the _Twitter Image Pipeline_ so `new` is unavailable. */
+ (instancetype)new NS_UNAVAILABLE;

/**
 Wait for the operation to finish.  See `[NSOperation waitUntilFinished]`.
 @warning This blocks on a semaphore so the thread will be completely blocked.
 To wait without blocking the thread by pumping the runloop,
 use `waitUntilFinishedWithoutBlockingRunLoop`
 */
- (void)waitUntilFinished;

/**
 Since `waitUntilFinished` is prone to deadlocks with a heavily asynchronous system like __TIP__,
 `waitUntilFinishedWithoutBlockingRunLoop` is provided so that the run loop can be pumped while
 waiting for the operation to finish (be sure there are sources to pump when using this method).
 */
- (void)waitUntilFinishedWithoutBlockingRunLoop;

/**
 Discard the delegate so no more callbacks can be made.
 */
- (void)discardDelegate;

/**
 Cancel the operation.  The delegate will be asynchronously called back with the cancel failure.
 */
- (void)cancel;

/**
 Cancel the operation and discard the delegate so it will not be notified of the cancel failure.
 See `cancel` and `discardDelegate`.
 */
- (void)cancelAndDiscardDelegate;

@end

#pragma mark - TIPImageFetchOperation support declarations

/**
 A protocol for the underlying context of a `TIPImageFetchRequestOperation`
 */
@protocol TIPImageFetchOperationUnderlyingContext <NSObject>

@required

/** An accessor to the associated image fetch operation */
- (nullable TIPImageFetchOperation *)associatedImageFetchOperation;

@end

#pragma mark - TIPImageFetchResult

/**
 A protocol encapsulating the result of a phase of a `TIPImageFetchOperation`.
 Could be for:
    1. Preview image
    2. Progressive image or First Animated Frame image
    3. Final image
 */
@protocol TIPImageFetchResult <NSObject>

@required

/** The result image container, if loaded */
@property (nonatomic, readonly) TIPImageContainer *imageContainer;
/** Source of result image */
@property (nonatomic, readonly) TIPImageLoadSource imageSource;
/** The `NSURL` of the image that was loaded for this result */
@property (nonatomic, readonly) NSURL *imageURL;
/** The dimensions of the result image prior to being scaled for completion. */
@property (nonatomic, readonly) CGSize imageOriginalDimensions;
/** Whether the result image is a placeholder or not.  Always `false` for progressive results. */
@property (nonatomic, readonly) BOOL imageIsTreatedAsPlaceholder;
/** Whether the result image was a transformed image or not. */
@property (nonatomic, readonly) BOOL imageWasTransformed;
/** Identifier for the result image */
@property (nonatomic, readonly, copy) NSString *imageIdentifier;

@end

NS_ASSUME_NONNULL_END
