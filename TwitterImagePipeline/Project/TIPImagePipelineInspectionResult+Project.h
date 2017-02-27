//
//  TIPImagePipelineInspectionResult+Project.h
//  TwitterImagePipeline
//
//  Created on 6/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIPImagePipelineInspectionResult.h"

@class TIPImageCacheEntry;

@interface TIPImagePipelineInspectionResult (Project)

- (nullable instancetype)initWithImagePipeline:(nonnull TIPImagePipeline *)imagePipeline;

- (void)addEntries:(nonnull NSArray<id<TIPImagePipelineInspectionResultEntry>> *)entries;
- (void)addEntry:(nonnull id<TIPImagePipelineInspectionResultEntry>)entry;

@end

@interface TIPImagePipelineInspectionResultEntry : NSObject <TIPImagePipelineInspectionResultEntry>

// Protocol properties
@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, nullable) NSURL *URL;
@property (nonatomic) CGSize dimensions;
@property (nonatomic) unsigned long long bytesUsed;
@property (nonatomic) float progress;
@property (nonatomic, nullable) UIImage *image;

+ (nullable instancetype)entryWithCacheEntry:(nonnull TIPImageCacheEntry *)cacheEntry class:(nonnull Class)class;

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
