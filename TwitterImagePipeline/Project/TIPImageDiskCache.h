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

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSInteger, TIPImageDiskCacheFetchOptions) {
    TIPImageDiskCacheFetchOptionsNone = 0, // effectively a touch
    TIPImageDiskCacheFetchOptionCompleteImage = (1 << 0),
    TIPImageDiskCacheFetchOptionPartialImage = (1 << 1),
    TIPImageDiskCacheFetchOptionTemporaryFile = (1 << 2),

    TIPImageDiskCacheFetchOptionPartialImageIfNoCompleteImage = (1 << 3),
    TIPImageDiskCacheFetchOptionTemporaryFileIfNoCompleteImage = (1 << 4),
};

@interface TIPImageDiskCache : NSObject <TIPImageCache, TIPInspectableCache>

@property (tip_nonatomic_direct, readonly, copy) NSString *cachePath;

- (instancetype)initWithPath:(NSString *)cachePath TIP_OBJC_DIRECT;

- (nullable TIPImageDiskCacheEntry *)imageEntryForIdentifier:(NSString *)identifier
                                                     options:(TIPImageDiskCacheFetchOptions)options
                                            targetDimensions:(CGSize)targetDimensions
                                           targetContentMode:(UIViewContentMode)targetContentMode
                                            decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap TIP_OBJC_DIRECT;
- (void)updateImageEntry:(TIPImageCacheEntry *)entry
 forciblyReplaceExisting:(BOOL)force TIP_OBJC_DIRECT;
- (void)touchImageWithIdentifier:(NSString *)imageIdentifier
                orSaveImageEntry:(nullable TIPImageDiskCacheEntry *)entry TIP_OBJC_DIRECT;
- (void)prune TIP_OBJC_DIRECT;
- (TIPImageDiskCacheTemporaryFile *)openTemporaryFileForImageIdentifier:(NSString *)imageIdentifier TIP_OBJC_DIRECT;
- (nullable NSString *)copyImageEntryFileForIdentifier:(NSString *)identifier
                                                 error:(out NSError * __nullable * __nullable)error TIP_OBJC_DIRECT;
- (BOOL)renameImageEntryWithIdentifier:(NSString *)oldIdentifier
                          toIdentifier:(NSString *)newIdentifier
                                 error:(NSError * __nullable * __nullable)error TIP_OBJC_DIRECT;

#pragma mark TempFile

- (void)finalizeTemporaryFile:(TIPImageDiskCacheTemporaryFile *)tempFile
                  withContext:(TIPImageCacheEntryContext *)context TIP_OBJC_DIRECT;
- (void)clearTemporaryFilePath:(NSString *)filePath TIP_OBJC_DIRECT;

@end

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageDiskCache (PrivateExposed)
- (TIPLRUCache *)diskCache_syncAccessManifest;
- (nullable NSString *)diskCache_imageEntryFilePathForIdentifier:(NSString *)identifier
                                        hitShouldMoveEntryToHead:(BOOL)hitToHead
                                                         context:(out TIPImageCacheEntryContext * __nullable * __nullable)context;
- (void)diskCache_updateImageEntry:(TIPImageCacheEntry *)entry
           forciblyReplaceExisting:(BOOL)force;
- (nullable TIPImageDiskCacheEntry *)diskCache_imageEntryForIdentifier:(NSString *)identifier
                                                               options:(TIPImageDiskCacheFetchOptions)options
                                                      targetDimensions:(CGSize)targetDimensions
                                                     targetContentMode:(UIViewContentMode)targetContentMode
                                                      decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap;
@end

NS_ASSUME_NONNULL_END
