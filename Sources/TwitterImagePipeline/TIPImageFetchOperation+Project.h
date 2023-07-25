//
//  TIPImageFetchOperation+Project.h
//  TwitterImagePipeline
//
//  Created on 3/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIPImageDownloader.h"
#import "TIPImageFetchOperation.h"

@class TIPImagePipeline;
@class TIPImageCacheEntry;

NS_ASSUME_NONNULL_BEGIN

@interface TIPImageFetchOperation (Project) <TIPImageDownloadDelegate>

@property (nonatomic, readonly, nullable, copy) NSString *imageIdentifier;
@property (nonatomic, readonly, nullable) NSURL *imageURL;
@property (nonatomic, readonly, nullable, copy) NSString *transformerIdentifier;

- (instancetype)initWithImagePipeline:(TIPImagePipeline *)pipeline
                              request:(id<TIPImageFetchRequest>)request
                             delegate:(id<TIPImageFetchDelegate>)delegate;

- (void)completeOperationEarlyWithImageEntry:(TIPImageCacheEntry *)entry
                                 transformed:(BOOL)transformed
                       sourceImageDimensions:(CGSize)sourceDims;
- (void)handleEarlyLoadOfDirtyImageEntry:(TIPImageCacheEntry *)entry
                             transformed:(BOOL)transformed
                   sourceImageDimensions:(CGSize)sourceDims;

- (void)willEnqueue;
- (BOOL)supportsLoadingFromSource:(TIPImageLoadSource)source;
- (BOOL)supportsLoadingFromRenderedCache;

@end

@interface TIPImageFetchOperation (Testing)
- (id<TIPImageDownloadContext>)associatedDownloadContext;
@end

NS_ASSUME_NONNULL_END
