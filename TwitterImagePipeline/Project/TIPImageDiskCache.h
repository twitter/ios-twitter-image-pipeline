//
//  TIPImageDiskCache.h
//  TwitterImagePipeline
//
//  Created on 3/3/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import "TIPImageCacheEntry.h"
#import "TIPInspectableCache.h"

@class TIPImageDiskCacheTemporaryFile;

typedef NS_OPTIONS(NSInteger, TIPImageDiskCacheFetchOptions) {
    TIPImageDiskCacheFetchOptionsNone = 0, // effectively a touch
    TIPImageDiskCacheFetchOptionCompleteImage = (1 << 0),
    TIPImageDiskCacheFetchOptionPartialImage = (1 << 1),
    TIPImageDiskCacheFetchOptionTemporaryFile = (1 << 2),

    TIPImageDiskCacheFetchOptionPartialImageIfNoCompleteImage = (1 << 3),
    TIPImageDiskCacheFetchOptionTemporaryFileIfNoCompleteImage = (1 << 4),
};

@interface TIPImageDiskCache : NSObject <TIPImageCache, TIPInspectableCache>

@property (nonatomic, readonly, copy, nonnull) NSString *cachePath;

- (nonnull instancetype)initWithPath:(nonnull NSString *)cachePath;

- (nullable TIPImageDiskCacheEntry *)imageEntryForIdentifier:(nonnull NSString *)identifier options:(TIPImageDiskCacheFetchOptions)options;
- (void)updateImageEntry:(nonnull TIPImageCacheEntry *)entry forciblyReplaceExisting:(BOOL)force;
- (void)touchImageWithIdentifier:(nonnull NSString *)imageIdentifier orSaveImageEntry:(nullable TIPImageDiskCacheEntry *)entry;
- (void)clearImageWithIdentifier:(nonnull NSString *)identifier;
- (void)clearAllImages:(void (^ __nullable)(void))completion;
- (void)prune;
- (nonnull TIPImageDiskCacheTemporaryFile *)openTemporaryFileForImageIdentifier:(nonnull NSString *)imageIdentifier;
- (nullable NSString *)copyImageEntryFileForIdentifier:(nonnull NSString *)identifier error:(out NSError * __nullable * __nullable)error;

@end

@interface TIPImageDiskCache (TempFile)

- (void)finalizeTemporaryFile:(nonnull TIPImageDiskCacheTemporaryFile *)tempFile withContext:(nonnull TIPImageCacheEntryContext *)context;
- (void)clearTemporaryFilePath:(nonnull NSString *)filePath;

@end

@interface TIPImageDiskCache (PrivateExposed)
- (nonnull TIPLRUCache *)diskCache_syncAccessManifest;
- (nullable NSString *)diskCache_imageEntryFilePathForIdentifier:(nonnull NSString *)identifier hitShouldMoveEntryToHead:(BOOL)hitToHead context:(out TIPImageCacheEntryContext * __nullable * __nullable)context;
- (void)diskCache_updateImageEntry:(nonnull TIPImageCacheEntry *)entry forciblyReplaceExisting:(BOOL)force;
- (nullable TIPImageDiskCacheEntry *)diskCache_imageEntryForIdentifier:(nonnull NSString *)identifier options:(TIPImageDiskCacheFetchOptions)options;
@end
