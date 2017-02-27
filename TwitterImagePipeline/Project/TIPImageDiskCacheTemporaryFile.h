//
//  TIPImageDiskCacheTemporaryFile.h
//  TwitterImagePipeline
//
//  Created on 3/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TIPImageCacheEntry.h"

@class TIPImageDiskCache;

@interface TIPImageDiskCacheTemporaryFile : NSObject

@property (nonatomic, readonly, copy, nonnull) NSString *imageIdentifier;

- (NSUInteger)appendData:(nullable NSData *)data;
- (void)finalizeWithContext:(nonnull TIPImageCacheEntryContext *)context;

+ (nonnull instancetype)new NS_UNAVAILABLE;
- (nonnull instancetype)init NS_UNAVAILABLE;

@end

#pragma mark - Private

@interface TIPImageDiskCacheTemporaryFile (DiskCache)
@property (nonatomic, readonly, copy, nonnull) NSString *temporaryPath;
@property (nonatomic, readonly, copy, nonnull) NSString *finalPath;
- (nonnull instancetype)initWithIdentifier:(nonnull NSString *)identifier temporaryPath:(nonnull NSString *)tempPath finalPath:(nonnull NSString *)finalPath diskCache:(nullable TIPImageDiskCache *)diskCache;
@end
