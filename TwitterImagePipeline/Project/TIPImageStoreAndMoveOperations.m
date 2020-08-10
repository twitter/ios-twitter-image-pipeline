//
//  TIPImageStoreAndMoveOperations.m
//  TwitterImagePipeline
//
//  Created on 1/13/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#include <stdatomic.h>

#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageDiskCache.h"
#import "TIPImageFetchRequest.h"
#import "TIPImageMemoryCache.h"
#import "TIPImagePipeline+Project.h"
#import "TIPImageRenderedCache.h"
#import "TIPImageStoreAndMoveOperations.h"
#import "UIImage+TIPAdditions.h"

// Static asserts to ensure the Fetch/Store options are 1:1 matching

TIPStaticAssert(TIPImageFetchNoOptions == TIPImageStoreNoOptions, NoOptionsMissmatch);
TIPStaticAssert(TIPImageFetchDoNotResetExpiryOnAccess == TIPImageStoreDoNotResetExpiryOnAccess, DoNotResetExpiryOnAccessMissmatch);
TIPStaticAssert(TIPImageFetchTreatAsPlaceholder == TIPImageStoreTreatAsPlaceholder, TreatAsPlaceholderMissmatch);

NS_ASSUME_NONNULL_BEGIN

@interface TIPImageStoreOperation ()
@property (tip_nonatomic_direct, readonly) id<TIPImageStoreRequest> request;
@property (tip_nonatomic_direct, readonly) TIPImagePipeline *pipeline;
@property (tip_nonatomic_direct, copy, readonly, nullable) TIPImagePipelineOperationCompletionBlock storeCompletionBlock;
@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageStoreOperation (Private)
- (nullable NSData *)_getImageData;
- (nullable NSString *)_getImageFilePath;
- (nullable TIPImageContainer *)_getImageContainer;
- (TIPCompleteImageEntryContext *)_getEntryContextWithImageURL:(NSURL *)imageURL
                                                imageContainer:(nullable TIPImageContainer *)imageContainer
                                                 imageFilePath:(nullable NSString *)imageFilePath
                                                     imageData:(nullable NSData *)imageData;
@end

@implementation TIPDisabledExternalMutabilityOperation

- (void)_tip_addDependency:(NSOperation *)op
{
    [super addDependency:op];
}

- (void)makeDependencyOfTargetOperation:(NSOperation *)op
{
    [op addDependency:self];
}

- (void)cancel
{
    [super doesNotRecognizeSelector:_cmd];
}

- (void)addDependency:(NSOperation *)op
{
    [super doesNotRecognizeSelector:_cmd];
}

- (void)removeDependency:(NSOperation *)op
{
    [super doesNotRecognizeSelector:_cmd];
}

- (void)setQueuePriority:(NSOperationQueuePriority)queuePriority
{
    [super doesNotRecognizeSelector:_cmd];
}

- (void)setCompletionBlock:(nullable void (^)(void))completionBlock
{
    [super doesNotRecognizeSelector:_cmd];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (void)setThreadPriority:(double)threadPriority
#pragma clang diagnostic pop
{
    [super doesNotRecognizeSelector:_cmd];
}

- (void)setQualityOfService:(NSQualityOfService)qualityOfService
{
    [super doesNotRecognizeSelector:_cmd];
}

@end

@implementation TIPImageStoreOperation
{
    TIPImageStoreHydrationOperation *_hydrationOperation;
}

- (instancetype)initWithRequest:(id<TIPImageStoreRequest>)request
                       pipeline:(TIPImagePipeline *)pipeline
                     completion:(nullable TIPImagePipelineOperationCompletionBlock)completion
{
    if (self = [super init]) {
        _request = request;
        _pipeline = pipeline;
        _storeCompletionBlock = [completion copy];
    }
    return self;
}

- (void)setHydrationDependency:(TIPImageStoreHydrationOperation *)dependency
{
    if (_hydrationOperation) {
        return;
    }

    _hydrationOperation = dependency;
    [super _tip_addDependency:dependency];
}

- (void)main
{
    @autoreleasepool {
        void (^completion)(TIPImageCacheEntry * __nullable, NSError * __nullable);
        completion = ^(TIPImageCacheEntry * __nullable completedEntry,
                       NSError * __nullable completedError) {
            TIPAssert((completedEntry != nil) ^ (completedError != nil));

            if (completedEntry) {
                [self.pipeline postCompletedEntry:completedEntry manual:YES];
            }

            TIPImagePipelineOperationCompletionBlock block = self.storeCompletionBlock;
            if (block) {
                const BOOL success = completedEntry != nil;
                tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
                    block(self, success, completedError);
                });
            }
        };

        // Check hydration
        if (_hydrationOperation) {
            NSError *hydrationError = _hydrationOperation.error;
            if (hydrationError) {
                completion(nil, hydrationError);
                return;
            } else if (_hydrationOperation.hydratedRequest) {
                _request = _hydrationOperation.hydratedRequest;
            }
        }

        // Confirm Caches
        if (!_pipeline.diskCache && !_pipeline.memoryCache) {
            completion(nil, [NSError errorWithDomain:TIPImageStoreErrorDomain
                                                code:TIPImageStoreErrorCodeNoCacheForStoring
                                            userInfo:nil]);
            return;
        }

        // Pull out image info
        NSData *imageData = [self _getImageData];
        NSString *imageFilePath = [self _getImageFilePath];
        TIPImageContainer *imageContainer = [self _getImageContainer];

        // Validate image info
        TIPAssertMessage(imageContainer != nil || imageData != nil || imageFilePath != nil, @"%@ didn't have any image info", NSStringFromClass([_request class]));
        if (!imageContainer && !imageData && !imageFilePath) {
            completion(nil, [NSError errorWithDomain:TIPImageStoreErrorDomain
                                                code:TIPImageStoreErrorCodeImageNotProvided
                                            userInfo:nil]);
            return;
        }

        // Pull out and validate URL
        NSURL *imageURL = _request.imageURL;
        TIPAssert(imageURL != nil);
        if (!imageURL) {
            completion(nil, [NSError errorWithDomain:TIPImageStoreErrorDomain
                                                code:TIPImageStoreErrorCodeImageURLNotProvided
                                            userInfo:nil]);
            return;
        }

        // Pull out the identifier
        NSString *identifier = TIPImageStoreRequestGetImageIdentifier(_request);

        // Create context
        TIPCompleteImageEntryContext *context = [self _getEntryContextWithImageURL:imageURL
                                                                    imageContainer:imageContainer
                                                                     imageFilePath:imageFilePath
                                                                         imageData:imageData];

        // Create Memory Entry
        TIPImageCacheEntry *memoryEntry = nil;
        if (_pipeline.memoryCache && imageData) {
            memoryEntry = [[TIPImageCacheEntry alloc] init];
            memoryEntry.completeImageData = imageData;
            memoryEntry.completeImageContext = [context copy];
            memoryEntry.identifier = identifier;
        }

        // Create Disk Entry
        TIPImageCacheEntry *diskEntry = nil;
        if (_pipeline.diskCache) {
            diskEntry = [[TIPImageCacheEntry alloc] init];
            if (imageFilePath && ([[NSFileManager defaultManager] fileExistsAtPath:imageFilePath] || (!imageData && !imageContainer))) {
                diskEntry.completeImageFilePath = imageFilePath;
            } else if (imageData) {
                diskEntry.completeImageData = imageData;
            } else {
                TIPAssert(imageContainer);
                diskEntry.completeImage = imageContainer;
                TIPAssert(diskEntry.completeImage);
            }
            diskEntry.completeImageContext = [context copy];
            diskEntry.identifier = identifier;
        }

        // Update caches
        [_pipeline.renderedCache clearImageWithIdentifier:identifier];

        if (diskEntry) {
            [_pipeline.diskCache updateImageEntry:diskEntry
                          forciblyReplaceExisting:!context.treatAsPlaceholder];
        } else {
            // we always have a disk entry when there's a disk cache
            TIPAssert(_pipeline.diskCache == nil);
        }

        if (memoryEntry) {
            [_pipeline.memoryCache updateImageEntry:memoryEntry
                            forciblyReplaceExisting:!context.treatAsPlaceholder];
        } else {
            // no memory entry, clear it so it can load from disk instead
            [_pipeline.memoryCache clearImageWithIdentifier:identifier];
        }

        completion(memoryEntry ?: diskEntry, nil);
    }
}

@end

@implementation TIPImageStoreOperation (Private)

- (nullable NSData *)_getImageData
{
    return [_request respondsToSelector:@selector(imageData)] ? _request.imageData : nil;
}


- (nullable NSString *)_getImageFilePath
{
    return [_request respondsToSelector:@selector(imageFilePath)] ? _request.imageFilePath : nil;
}

- (nullable TIPImageContainer *)_getImageContainer
{
    TIPImageContainer *imageContainer = nil;
    if ([_request respondsToSelector:@selector(image)]) {
        UIImage *image = _request.image;
        if (image.CIImage) {
            image = [image tip_CGImageBackedImageAndReturnError:NULL];
        }

        if (image) {
            if (image.images.count > 0) {
                NSUInteger loopCount = [_request respondsToSelector:@selector(animationLoopCount)] ? _request.animationLoopCount : 0;
                NSArray<NSNumber *> *durations = [_request respondsToSelector:@selector(animationFrameDurations)] ? _request.animationFrameDurations : nil;
                imageContainer = [[TIPImageContainer alloc] initWithAnimatedImage:image
                                                                        loopCount:loopCount
                                                                   frameDurations:durations];
            } else {
                imageContainer = [[TIPImageContainer alloc] initWithImage:image];
            }
            TIPAssert(imageContainer != nil);
        }
    }
    return imageContainer;
}

- (TIPCompleteImageEntryContext *)_getEntryContextWithImageURL:(NSURL *)imageURL
                                                imageContainer:(nullable TIPImageContainer *)imageContainer
                                                 imageFilePath:(nullable NSString *)imageFilePath
                                                     imageData:(nullable NSData *)imageData
{
    TIPCompleteImageEntryContext *context = [[TIPCompleteImageEntryContext alloc] init];
    const TIPImageStoreOptions options = [_request respondsToSelector:@selector(options)] ?
                                            [_request options] :
                                            TIPImageStoreNoOptions;
    context.updateExpiryOnAccess = TIP_BITMASK_EXCLUDES_FLAGS(options, TIPImageStoreDoNotResetExpiryOnAccess);
    context.treatAsPlaceholder = TIP_BITMASK_HAS_SUBSET_FLAGS(options, TIPImageStoreTreatAsPlaceholder);
    context.TTL = [_request respondsToSelector:@selector(timeToLive)] ? [_request timeToLive] : -1.0;
    if (context.TTL <= 0.0) {
        context.TTL = TIPTimeToLiveDefault;
    }
    context.URL = imageURL;
    if (imageContainer) {
        context.dimensions = imageContainer.dimensions;
    } else if ([_request respondsToSelector:@selector(imageDimensions)]) {
        context.dimensions = _request.imageDimensions;
    } else if (imageData) {
        context.dimensions = TIPDetectImageDataDimensions(imageData);
    } else if (imageFilePath) {
        context.dimensions = TIPDetectImageFileDimensions(imageFilePath);
    }
    if ([_request respondsToSelector:@selector(imageType)]) {
        context.imageType = [_request imageType];
    }
    if (imageContainer) {
        context.animated = imageContainer.isAnimated;
    } else {
        if ([context.imageType isEqualToString:TIPImageTypeGIF]) {
            context.animated = YES;
        }
    }
    return context;
}

@end

@implementation TIPImageStoreHydrationOperation
{
    id<TIPImageStoreRequest> _request;
    TIPImagePipeline *_pipeline;
    id<TIPImageStoreRequestHydrater> _hydrater;

    volatile atomic_bool _isFinished;
    volatile atomic_bool _isExecuting;
    volatile atomic_bool _didStart;
}

- (instancetype)initWithRequest:(id<TIPImageStoreRequest>)request
                       pipeline:(TIPImagePipeline *)pipeline
                       hydrater:(id<TIPImageStoreRequestHydrater>)hydrater
{
    TIPAssert(request);
    TIPAssert(pipeline);
    TIPAssert(hydrater);

    if (!request || !pipeline || !hydrater) {
        return nil;
    }

    if (self = [super init]) {
        _request = request;
        _pipeline = pipeline;
        _hydrater = hydrater;
        atomic_init(&_isFinished, false);
        atomic_init(&_isExecuting, false);
        atomic_init(&_didStart, false);
    }
    return self;
}

- (BOOL)isAsynchronous
{
    return YES;
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isExecuting
{
    return atomic_load(&_isExecuting);
}

- (BOOL)isFinished
{
    return atomic_load(&_isFinished);
}

- (void)start
{
    tip_defer(^{
        atomic_store(&(self->_didStart), true);
    });

    [self willChangeValueForKey:@"isExecuting"];
    atomic_store(&_isExecuting, true);
    [self didChangeValueForKey:@"isExecuting"];

    [_hydrater tip_hydrateImageStoreRequest:_request
                              imagePipeline:_pipeline
                                 completion:^(id<TIPImageStoreRequest> newRequest, NSError *error) {
        [self _completeHydrationWithNewRequest:newRequest error:error];
    }];
}

- (void)_completeHydrationWithNewRequest:(nullable id<TIPImageStoreRequest>)request
                                   error:(nullable NSError *)error TIP_OBJC_DIRECT
{
    if (false == atomic_load(&_didStart)) {
        // Completed synchronously, don't want to mess up "isAsynchronous" behavior
        [[TIPGlobalConfiguration sharedInstance] enqueueImagePipelineOperation:[NSBlockOperation blockOperationWithBlock:^{
            [self _completeHydrationWithNewRequest:request error:error];
        }]];
        return;
    }

    if (error) {
        _error = error;
    } else {
        _hydratedRequest = request ?: _request;
    }

    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    atomic_store(&_isExecuting, false);
    atomic_store(&_isFinished, true);
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

@end

@implementation TIPImageMoveOperation
{
    TIPImagePipelineOperationCompletionBlock _completion;
}

- (instancetype)initWithPipeline:(TIPImagePipeline *)pipeline
              originalIdentifier:(NSString *)oldIdentifier
               updatedIdentifier:(NSString *)newIdentifier
                      completion:(nullable TIPImagePipelineOperationCompletionBlock)completion
{
    TIPAssert(pipeline != nil);
    if (self = [super init]) {
        _pipeline = pipeline;
        _originalIdentifier = [oldIdentifier copy];
        _updatedIdentifier = [newIdentifier copy];
        _completion = [completion copy];
    }
    return self;
}

- (void)main
{
    NSError *error = nil;
    TIPImageDiskCache *cache = _pipeline.diskCache;
    if (!cache) {
        error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                    code:EINVAL
                                userInfo:nil];
    } else {
        const BOOL success = [cache renameImageEntryWithIdentifier:_originalIdentifier
                                                      toIdentifier:_updatedIdentifier error:&error];
        TIPAssert(!success ^ !error);
        if (success) {
            [_pipeline clearImageWithIdentifier:_originalIdentifier];
        }
    }

    TIPImagePipelineOperationCompletionBlock completion = _completion;
    if (completion) {
        tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            completion(self, !error, error);
        });
    }
}

@end

NS_ASSUME_NONNULL_END
