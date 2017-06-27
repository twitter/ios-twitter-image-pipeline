//
//  TIPImagePipelineInspectionResult+Project.h
//  TwitterImagePipeline
//
//  Created on 6/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIPImagePipelineInspectionResult.h"

@class TIPImageCacheEntry;

NS_ASSUME_NONNULL_BEGIN

@interface TIPImagePipelineInspectionResult (Project)

- (nullable instancetype)initWithImagePipeline:(TIPImagePipeline *)imagePipeline;

- (void)addEntries:(NSArray<id<TIPImagePipelineInspectionResultEntry>> *)entries;
- (void)addEntry:(id<TIPImagePipelineInspectionResultEntry>)entry;

@end

@interface TIPImagePipelineInspectionResultEntry : NSObject <TIPImagePipelineInspectionResultEntry>

// Protocol properties
@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, nullable) NSURL *URL;
@property (nonatomic) CGSize dimensions;
@property (nonatomic) unsigned long long bytesUsed;
@property (nonatomic) float progress;
@property (nonatomic, nullable) UIImage *image;

+ (nullable instancetype)entryWithCacheEntry:(TIPImageCacheEntry *)cacheEntry class:(Class)class;

@end

@interface TIPImagePipelineInspectionResultRenderedEntry : TIPImagePipelineInspectionResultEntry
@end

@interface TIPImagePipelineInspectionResultCompleteMemoryEntry : TIPImagePipelineInspectionResultEntry
@end

@interface TIPImagePipelineInspectionResultCompleteDiskEntry : TIPImagePipelineInspectionResultEntry
@end

@interface TIPImagePipelineInspectionResultPartialMemoryEntry : TIPImagePipelineInspectionResultEntry
@end

@interface TIPImagePipelineInspectionResultPartialDiskEntry : TIPImagePipelineInspectionResultEntry
@end

NS_ASSUME_NONNULL_END
