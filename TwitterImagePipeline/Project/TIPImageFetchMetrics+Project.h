//
//  TIPImageFetchMetrics+Project.h
//  TwitterImagePipeline
//
//  Created on 6/19/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPImageFetchMetrics.h"

@class TIPPartialImage;

NS_ASSUME_NONNULL_BEGIN

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageFetchMetrics ()

- (instancetype)initProject;

- (void)startWithSource:(TIPImageLoadSource)source;
- (void)endSource;
- (void)cancelSource;

- (void)convertNetworkMetricsToResumedNetworkMetrics;
- (void)addNetworkMetrics:(nullable id)metrics
               forRequest:(NSURLRequest *)request
                imageType:(nullable NSString *)imageType
         imageSizeInBytes:(NSUInteger)sizeInBytes
          imageDimensions:(CGSize)dimensions;

- (void)previewWasHit:(NSTimeInterval)renderLatency;
- (void)progressiveFrameWasHit:(NSTimeInterval)renderLatency;
- (void)finalWasHit:(NSTimeInterval)renderLatency synchronously:(BOOL)sync;

@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageFetchMetricInfo ()

- (instancetype)initWithSource:(TIPImageLoadSource)source startTime:(uint64_t)startMachTime;

- (void)end;
- (void)cancel;
- (void)hit:(TIPImageFetchLoadResult)result
        renderLatency:(NSTimeInterval)renderLatency
        synchronously:(BOOL)sync;
- (void)addNetworkMetrics:(nullable id)metrics
               forRequest:(NSURLRequest *)request
                imageType:(nullable NSString *)imageType
         imageSizeInBytes:(NSUInteger)sizeInBytes
          imageDimensions:(CGSize)dimensions;
- (void)flipLoadSourceFromNetworkToNetworkResumed;

@end

NS_ASSUME_NONNULL_END
