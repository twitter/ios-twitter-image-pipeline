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

NS_ASSUME_NONNULL_BEGIN

TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageDiskCacheTemporaryFile : NSObject

@property (nonatomic, readonly, copy) NSString *imageIdentifier;

- (NSUInteger)appendData:(nullable NSData *)data;
- (void)finalizeWithContext:(TIPImageCacheEntryContext *)context;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark - Private

@interface TIPImageDiskCacheTemporaryFile (DiskCache)
@property (nonatomic, readonly, copy) NSString *temporaryPath;
@property (nonatomic, readonly, copy) NSString *finalPath;
- (instancetype)initWithIdentifier:(NSString *)identifier
                     temporaryPath:(NSString *)tempPath
                         finalPath:(NSString *)finalPath
                         diskCache:(nullable TIPImageDiskCache *)diskCache;
@end

NS_ASSUME_NONNULL_END
