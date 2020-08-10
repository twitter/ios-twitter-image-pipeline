//
//  TIPImagePipelineInspectionResult.m
//  TwitterImagePipeline
//
//  Created on 6/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPImageCacheEntry.h"
#import "TIPImageCodecs.h"
#import "TIPImagePipelineInspectionResult+Project.h"
#import "TIPPartialImage.h"
#import "UIImage+TIPAdditions.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TIPImagePipelineInspectionResult
@end

@implementation TIPImagePipelineInspectionResult (Project)

- (nullable instancetype)initWithImagePipeline:(TIPImagePipeline *)imagePipeline
{
    if (self = [super init]) {
        _imagePipeline = imagePipeline;
        _completeDiskEntries = [[NSMutableArray alloc] init];
        _completeMemoryEntries = [[NSMutableArray alloc] init];
        _completeRenderedEntries = [[NSMutableArray alloc] init];
        _partialMemoryEntries = [[NSMutableArray alloc] init];
        _partialDiskEntries = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)addEntry:(id<TIPImagePipelineInspectionResultEntry>)entry
{
    BOOL onDisk = NO;
    NSMutableArray *entries = nil;
    if ([entry class] == [TIPImagePipelineInspectionResultRenderedEntry class]) {
        entries = (NSMutableArray *)self.completeRenderedEntries;
    } else if ([entry class] == [TIPImagePipelineInspectionResultCompleteMemoryEntry class]) {
        entries = (NSMutableArray *)self.completeMemoryEntries;
    } else if ([entry class] == [TIPImagePipelineInspectionResultCompleteDiskEntry class]) {
        entries = (NSMutableArray *)self.completeDiskEntries;
        onDisk = YES;
    } else if ([entry class] == [TIPImagePipelineInspectionResultPartialMemoryEntry class]) {
        entries = (NSMutableArray *)self.partialMemoryEntries;
    } else if ([entry class] == [TIPImagePipelineInspectionResultPartialDiskEntry class]) {
        entries = (NSMutableArray *)self.partialDiskEntries;
        onDisk = YES;
    } else {
        TIPAssertNever();
        return;
    }

    [entries addObject:entry];
    if (onDisk) {
        _onDiskBytesUsed += entry.bytesUsed;
    } else {
        _inMemoryBytesUsed += entry.bytesUsed;
    }
}

- (void)addEntries:(NSArray *)entries
{
    for (id<TIPImagePipelineInspectionResultEntry> entry in entries) {
        [self addEntry:entry];
    }
}

@end

@implementation TIPImagePipelineInspectionResultEntry

+ (nullable instancetype)entryWithCacheEntry:(TIPImageCacheEntry *)cacheEntry class:(Class)class
{
    BOOL partial = NO;
    if (class == [TIPImagePipelineInspectionResultRenderedEntry class]) {

    } else if (class == [TIPImagePipelineInspectionResultCompleteMemoryEntry class]) {

    } else if (class == [TIPImagePipelineInspectionResultCompleteDiskEntry class]) {

    } else if (class == [TIPImagePipelineInspectionResultPartialMemoryEntry class]) {
        partial = YES;
    } else if (class == [TIPImagePipelineInspectionResultPartialDiskEntry class]) {
        partial = YES;
    } else {
        TIPAssertNever();
        return nil;
    }

    if (partial && !cacheEntry.partialImageContext) {
            return nil;
    }
    if (!partial && !cacheEntry.completeImageContext) {
            return nil;
    }

    TIPImagePipelineInspectionResultEntry *entry = [[class alloc] init];
    if (partial) {
        entry.dimensions = cacheEntry.partialImageContext.dimensions;
        entry.URL = cacheEntry.partialImageContext.URL;

        if (cacheEntry.partialImage) {
            entry.image = [cacheEntry.partialImage renderImageWithMode:TIPImageDecoderRenderModeAnyProgress
                                                      targetDimensions:CGSizeZero
                                                     targetContentMode:UIViewContentModeCenter
                                                               decoded:NO].image;
            if (cacheEntry.partialImage.state > TIPPartialImageStateLoadingHeaders) {
                entry.bytesUsed = TIPEstimateMemorySizeOfImageWithSettings(cacheEntry.partialImage.dimensions, 1.0, 4 /* presume 4 bytes per pixel */, (cacheEntry.partialImage.isAnimated) ? cacheEntry.partialImage.frameCount : 1);
            } else {
                entry.bytesUsed = cacheEntry.partialImage.byteCount;
            }
            entry.progress = cacheEntry.partialImage.progress;
        } else if ([cacheEntry isKindOfClass:[TIPImageDiskCacheEntry class]]) {
            TIPImageDiskCacheEntry *diskEntry = (id)cacheEntry;
            entry.bytesUsed = diskEntry.partialFileSize;
            entry.progress = MIN((float)((double)diskEntry.partialFileSize / (double)diskEntry.partialImageContext.expectedContentLength), 0.999f);
        }
    } else {
        if (cacheEntry.completeImage) {
            entry.image = cacheEntry.completeImage.image;
            entry.bytesUsed = [entry.image tip_estimatedSizeInBytes];
        } else if ([cacheEntry isKindOfClass:[TIPImageDiskCacheEntry class]]) {
            TIPImageDiskCacheEntry *diskEntry = (id)cacheEntry;
            entry.bytesUsed = diskEntry.completeFileSize;
        } else if ([cacheEntry isKindOfClass:[TIPImageMemoryCacheEntry class]]) {
            entry.image = [TIPImageContainer imageContainerWithData:cacheEntry.completeImageData
                                                   decoderConfigMap:nil
                                                     codecCatalogue:nil].image;
            entry.bytesUsed = [(TIPImageMemoryCacheEntry*)cacheEntry memoryCost];
        }

        entry.dimensions = cacheEntry.completeImageContext.dimensions;
        entry.URL = cacheEntry.completeImageContext.URL;
        entry.progress = 1.0f;
    }
    entry.identifier = cacheEntry.identifier;
    return entry;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p, progress=%.3f, bytes=%llu, dim=%@, URL=%@>", NSStringFromClass([self class]), self, self.progress, self.bytesUsed, NSStringFromCGSize(self.dimensions), self.URL];
}

@end

@implementation TIPImagePipelineInspectionResultRenderedEntry
@end

@implementation TIPImagePipelineInspectionResultCompleteMemoryEntry
@end

@implementation TIPImagePipelineInspectionResultCompleteDiskEntry
@end

@implementation TIPImagePipelineInspectionResultPartialMemoryEntry
@end

@implementation TIPImagePipelineInspectionResultPartialDiskEntry
@end

NS_ASSUME_NONNULL_END
