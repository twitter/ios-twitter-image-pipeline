//
//  TIPImagePipelineInspectionResult.h
//  TwitterImagePipeline
//
//  Created on 6/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class TIPImagePipeline;
@protocol TIPImagePipelineInspectionResultEntry;

NS_ASSUME_NONNULL_BEGIN

/**
 Results for the inspection of a `TIPImagePipeline`
 */
@interface TIPImagePipelineInspectionResult : NSObject

/** The inspected `TIPImagePipeline` */
@property (nonatomic, readonly) TIPImagePipeline *imagePipeline;

/** The rendered cache entries that are complete */
@property (nonatomic, readonly) NSArray<id<TIPImagePipelineInspectionResultEntry>> *completeRenderedEntries;
/** The memory cache entries that are complete */
@property (nonatomic, readonly) NSArray<id<TIPImagePipelineInspectionResultEntry>> *completeMemoryEntries;
/** The disk cache entries that are complete */
@property (nonatomic, readonly) NSArray<id<TIPImagePipelineInspectionResultEntry>> *completeDiskEntries;

/** The memory cache entries that are partial (incomplete) */
@property (nonatomic, readonly) NSArray<id<TIPImagePipelineInspectionResultEntry>> *partialMemoryEntries;
/** The disk cache entries that are partial (incomplete) */
@property (nonatomic, readonly) NSArray<id<TIPImagePipelineInspectionResultEntry>> *partialDiskEntries;

/** number of bytes used in memory caches */
@property (nonatomic, readonly) unsigned long long inMemoryBytesUsed;
/** number of bytes used on disk */
@property (nonatomic, readonly) unsigned long long onDiskBytesUsed;

/** `NS_UNAVAILABLE` */
- (instancetype)init NS_UNAVAILABLE;
/** `NS_UNAVAILABLE` */
+ (instancetype)new NS_UNAVAILABLE;

@end

/**
 An entry for a particular cache that was inspected
 */
@protocol TIPImagePipelineInspectionResultEntry <NSObject>

@required

/** the image identifier */
@property (nonatomic, readonly, copy, nullable) NSString *identifier;
/** the image URL */
@property (nonatomic, readonly, nullable) NSURL *URL;
/** the image dimensions (in pixels) */
@property (nonatomic, readonly) CGSize dimensions;
/** the bytes used by the image (on disk size is encoded bytes, in memory is decoded bytes) */
@property (nonatomic, readonly) unsigned long long bytesUsed;

/** progress (less than `1.f` for partial/incomplete entries) */
@property (nonatomic, readonly) float progress;
/** the image itself */
@property (nonatomic, readonly, nullable) UIImage *image;

@end

NS_ASSUME_NONNULL_END
