//
//  TIPImageFetchMetrics.h
//  TwitterImagePipeline
//
//  Created on 6/19/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <TIPDefinitions.h>
#import <TIPImageFetchOperation.h>

@class TIPImageFetchMetricInfo;

NS_ASSUME_NONNULL_BEGIN

/**
 Class that encapsulates all the metric information related to the `TIPImageFetchOperation`
 */
@interface TIPImageFetchMetrics : NSObject

/** The duration it took for the entire `TIPImageFetchOperation` to complete (or fail) */
@property (nonatomic, readonly) NSTimeInterval totalDuration;
/**
 The duration it took for the first presentable image to be loaded.
 This could be a preview image, a progressive frame or the final image.
 */
@property (nonatomic, readonly) NSTimeInterval firstImageLoadDuration;
/** Whether the operation was cancelled */
@property (nonatomic, readonly) BOOL wasCancelled;

/**
 Retrieve the breakdown of metric info for a given `TIPImageLoadSource`.
 @param source The source of interest.
 @return the metric info for the given _source_.  If the _source_ was never accessed, `nil` will be
 returned.
 */
- (nullable TIPImageFetchMetricInfo *)metricInfoForSource:(TIPImageLoadSource)source;

/** `NS_UNAVAILABLE` */
- (instancetype)init NS_UNAVAILABLE;
/** `NS_UNAVAILABLE` */
- (instancetype)new NS_UNAVAILABLE;

@end

/**
 The result of a `TIPImageLoadSource`'s fetch
 */
typedef NS_ENUM(NSInteger, TIPImageFetchLoadResult){
    /** The source never finished its fetch */
    TIPImageFetchLoadResultNeverCompleted = -1,
    /** The source did not yield an image */
    TIPImageFetchLoadResultMiss = 0,
    /** The source yielded a preview image */
    TIPImageFetchLoadResultHitPreview,
    /** The source yielded a progress frame */
    TIPImageFetchLoadResultHitProgressFrame,
    /** The source yielded the final image */
    TIPImageFetchLoadResultHitFinal,
};

/** Class that encapsulates the metric info for a specific `TIPImageLoadSource` */
@interface TIPImageFetchMetricInfo : NSObject

/** The source for the metric info */
@property (nonatomic, readonly) TIPImageLoadSource source;
/** The result of the fetch on this source */
@property (nonatomic, readonly) TIPImageFetchLoadResult result;
/** Whether the operation cancelled while investigating this source */
@property (nonatomic, readonly) BOOL wasCancelled;

/** The duration for this source to miss, hit or get interrupted */
@property (nonatomic, readonly) NSTimeInterval loadDuration;
/** The fetch was synchronous (`TIPImageLoadSourceMemoryCache` == `source` only) */
@property (nonatomic, readonly) BOOL wasLoadedSynchronously;

/** `NS_UNAVAILABLE` */
- (instancetype)init NS_UNAVAILABLE;
/** `NS_UNAVAILABLE` */
- (instancetype)new NS_UNAVAILABLE;

@end

/**
 Info specifically for a `TIPImageFetchMetricInfo` that has a `[TIPImageFetchMetricInfo source]`
 equal to `TIPImageLoadSourceNetwork` or `TIPImageLoadSourceNetworkResumed`.
 */
@interface TIPImageFetchMetricInfo (NetworkSourceInfo)

/** Opaque "metrics" object provided by the `TIPImageFetchDownload`. */
@property (nonatomic, readonly, nullable) id networkMetrics;
/** The `NSURLRequest` for the network download */
@property (nonatomic, readonly, nullable) NSURLRequest *networkRequest;

/** Time for the network load */
@property (nonatomic, readonly) NSTimeInterval totalNetworkLoadDuration;
/** Time for the first progressive frame to load over the network */
@property (nonatomic, readonly) NSTimeInterval firstProgressiveFrameNetworkLoadDuration;
/** Size of the image file (not necessarily bytes downloaded since resumed would be smaller) */
@property (nonatomic, readonly) NSUInteger networkImageSizeInBytes;
/** Image type downloaded */
@property (nonatomic, copy, readonly, nullable) NSString *networkImageType;
/** Image dimensions (in pixels) */
@property (nonatomic, readonly) CGSize networkImageDimensions;
/** The pixels per byte ratio (larger indicates more compressed encoding) */
@property (nonatomic, readonly) float networkImagePixelsPerByte;

@end

NS_ASSUME_NONNULL_END
