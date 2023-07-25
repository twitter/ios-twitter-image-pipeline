//
//  TIPImageCacheEntry.h
//  TwitterImagePipeline
//
//  Created on 3/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <UIKit/UIImage.h>

#import "TIPImageCache.h"
#import "TIPImageContainer.h"
#import "TIPImageUtils.h"
#import "TIPLRUCache.h"

#pragma mark - External Forward Declarations

@class TIPImageDiskCacheTemporaryFile;
@class TIPPartialImage;

#pragma mark - Forward Declarations for this Header

@class TIPImageCacheEntryContext; // Abstract base class
@class TIPCompleteImageEntryContext;
@class TIPPartialImageEntryContext;

@class TIPImageCacheEntry; // base class
@class TIPImageMemoryCacheEntry;
@class TIPImageDiskCacheEntry;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Context Declarations

// Abstract base class
@interface TIPImageCacheEntryContext : NSObject <NSCopying>

@property (tip_nonatomic_direct) BOOL updateExpiryOnAccess;
@property (tip_nonatomic_direct) BOOL treatAsPlaceholder;
@property (tip_nonatomic_direct) NSTimeInterval TTL;
@property (tip_nonatomic_direct, nullable) NSURL *URL;
@property (tip_nonatomic_direct, nullable) NSDate *lastAccess;
@property (tip_nonatomic_direct, getter=isAnimated) BOOL animated;

@property (tip_nonatomic_direct) CGSize dimensions; // pixel size, not point size

@end

@interface TIPCompleteImageEntryContext : TIPImageCacheEntryContext

@property (nonatomic, copy, nullable) NSString *imageType;

@end

@interface TIPPartialImageEntryContext : TIPImageCacheEntryContext

@property (nonatomic) NSUInteger expectedContentLength;
@property (nonatomic, copy, nullable) NSString *lastModified;

@end

#pragma mark - Cache Entry Declarations

// Base class
@interface TIPImageCacheEntry : NSObject <NSCopying, TIPLRUEntry>

@property (nonatomic, copy, nullable) NSString *identifier;

@property (nonatomic, nullable) TIPImageContainer *completeImage;
@property (nonatomic, nullable) TIPCompleteImageEntryContext *completeImageContext;

@property (nonatomic, nullable) TIPPartialImage *partialImage;
@property (nonatomic, nullable) TIPPartialImageEntryContext *partialImageContext;

- (BOOL)isValid:(BOOL)mustHaveSomeImage TIP_OBJC_DIRECT;

#pragma mark TIPLRUEntry

@property (nonatomic, nullable) TIPImageCacheEntry *nextLRUEntry;
@property (nonatomic, weak, nullable) TIPImageCacheEntry *previousLRUEntry;

@end

@interface TIPImageMemoryCacheEntry : TIPImageCacheEntry
@end

@interface TIPImageDiskCacheEntry : TIPImageCacheEntry
@property (tip_nonatomic_direct, nullable) TIPImageDiskCacheTemporaryFile *tempFile;
@end

#pragma mark - Private

@interface TIPImageCacheEntry (Access)
- (nullable NSDate *)mostRecentAccess TIP_OBJC_DIRECT;
@end

@interface TIPImageCacheEntry (Store)
@property (nonatomic, nullable) NSData *completeImageData; // only for storing
@property (nonatomic, nullable, copy) NSString *completeImageFilePath; // only for storing
@end

@interface TIPImageMemoryCacheEntry (MemoryCache)

// Used by Memory Cache
@property (nonatomic, readonly) NSUInteger memoryCost;

@end

@interface TIPImageDiskCacheEntry (DiskCache)

// Used by Disk Cache
@property (nonatomic, readonly, nullable, copy) NSString *safeIdentifier;
@property (nonatomic) NSUInteger completeFileSize;
@property (nonatomic) NSUInteger partialFileSize;

@end

NS_ASSUME_NONNULL_END
