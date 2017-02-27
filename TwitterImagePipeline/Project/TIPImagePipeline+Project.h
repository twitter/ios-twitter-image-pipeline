//
//  TIPImagePipeline+Project.h
//  TwitterImagePipeline
//
//  Created on 3/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIPImageCacheEntry.h"
#import "TIPImageFetchDelegate.h"
#import "TIPImagePipeline.h"

@class TIPImageDiskCache;
@class TIPImageMemoryCache;
@class TIPImageRenderedCache;
@class TIPImageDownloader;
@class TIPImageStoreOperation;

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXTERN NSString * const TIPImagePipelineDidStandUpImagePipelineNotification;
FOUNDATION_EXTERN NSString * const TIPImagePipelineDidTearDownImagePipelineNotification; // object will be nil
NS_ASSUME_NONNULL_END

@interface TIPImagePipeline ()

@property (nonatomic, readonly, nullable) TIPImageRenderedCache *renderedCache;
@property (nonatomic, readonly, nullable) TIPImageMemoryCache *memoryCache;
@property (nonatomic, readonly, nullable) TIPImageDiskCache *diskCache;
@property (nonatomic, readonly, nullable) TIPImageDownloader *downloader;

- (nonnull TIPImageStoreOperation *)storeOperationWithRequest:(nonnull id<TIPImageStoreRequest>)request completion:(nullable TIPImagePipelineStoreCompletionBlock)completion;
- (void)postCompletedEntry:(nonnull TIPImageCacheEntry *)entry manual:(BOOL)manual;
- (nullable id<TIPImageCache>)cacheOfType:(TIPImageCacheType)type;

+ (nonnull NSDictionary<NSString *, TIPImagePipeline *> *)allRegisteredImagePipelines;

@end

@interface TIPSimpleImageFetchDelegate : NSObject <TIPImageFetchDelegate>
@end
