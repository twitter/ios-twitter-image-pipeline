//
//  TIPImageDiskCacheTemporaryFile.m
//  TwitterImagePipeline
//
//  Created on 3/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPImageDiskCache.h"
#import "TIPImageDiskCacheTemporaryFile.h"

@interface TIPImageDiskCacheTemporaryFile ()

@property (nonatomic, readonly, copy, nonnull) NSString *temporaryPath;
@property (nonatomic, readonly, copy, nonnull) NSString *finalPath;
@property (nonatomic, weak) TIPImageDiskCache *diskCache;

- (nonnull instancetype)initWithIdentifier:(nonnull NSString *)identifier temporaryPath:(nonnull NSString *)tempPath finalPath:(nonnull NSString *)finalPath diskCache:(nullable TIPImageDiskCache *)diskCache;

- (void)cleanupOpenFile;

@end

@implementation TIPImageDiskCacheTemporaryFile
{
    FILE *_openFile;
}

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (instancetype)initWithIdentifier:(NSString *)identifier temporaryPath:(NSString *)tempPath finalPath:(NSString *)finalPath diskCache:(TIPImageDiskCache *)diskCache
{
    TIPAssert(identifier != nil);
    TIPAssert(tempPath != nil);
    TIPAssert(finalPath != nil);

    if (self = [super init]) {
        _imageIdentifier = [identifier copy];
        _temporaryPath = [tempPath copy];
        _finalPath = [finalPath copy];
        _diskCache = diskCache;

        _openFile = fopen(tempPath.UTF8String, "a");
    }
    return self;
}

- (void)dealloc
{
    [self cleanupOpenFile];
    [_diskCache clearTemporaryFilePath:_temporaryPath];
}

- (NSUInteger)appendData:(NSData *)data
{
    if (!_openFile) {
        return 0;
    }
    return fwrite(data.bytes, 1, data.length, _openFile);
}

- (void)finalizeWithContext:(TIPImageCacheEntryContext *)context
{
    if (!_openFile) {
        return;
    }

    TIPAssert([context isKindOfClass:[TIPPartialImageEntryContext class]] || [context isKindOfClass:[TIPCompleteImageEntryContext class]]);

    [self cleanupOpenFile];
    TIPImageDiskCache *diskCache = _diskCache;

    if ([context isKindOfClass:[TIPPartialImageEntryContext class]]) {
        TIPPartialImageEntryContext *partialContext = (id)context;
        if (!partialContext.lastModified) {
            // Can't resume without a Last-Modified date
            [diskCache clearTemporaryFilePath:_temporaryPath];
            return;
        }
    }

    [diskCache finalizeTemporaryFile:self withContext:context];
}

- (void)cleanupOpenFile
{
    if (_openFile) {
        fflush(_openFile);
        fclose(_openFile);
        _openFile = NULL;
    }
}

@end
