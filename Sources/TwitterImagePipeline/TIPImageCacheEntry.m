//
//  TIPImageCacheEntry.m
//  TwitterImagePipeline
//
//  Created on 3/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPImageCacheEntry.h"
#import "TIPImageUtils.h"
#import "TIPPartialImage.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Private Declarations

@interface TIPImageCacheEntryContext ()
- (instancetype)initWithCacheEntryContext:(TIPImageCacheEntryContext *)context;
@end

@interface TIPImageCacheEntry ()
@property (nonatomic, nullable) NSData *completeImageData;
@property (nonatomic, nullable, copy) NSString *completeImageFilePath;
- (instancetype)initWithCacheEntry:(TIPImageCacheEntry *)cacheEntry;
@end

@interface TIPImageMemoryCacheEntry ()
@property (nonatomic, readonly) NSUInteger memoryCost;
@end

@interface TIPImageDiskCacheEntry ()
@property (nonatomic, readonly, copy, nullable) NSString *safeIdentifier;
@property (nonatomic) NSUInteger completeFileSize;
@property (nonatomic) NSUInteger partialFileSize;
@end

#pragma mark - Implementations

@implementation TIPImageCacheEntryContext

- (instancetype)initWithCacheEntryContext:(TIPImageCacheEntryContext *)context
{
    if (self = [super init]) {
        _updateExpiryOnAccess = context.updateExpiryOnAccess;
        _treatAsPlaceholder = context.treatAsPlaceholder;
        _TTL = context.TTL;
        _URL = context.URL;
        _lastAccess = context.lastAccess;
        _dimensions = context.dimensions;
        _animated = context.animated;
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TIPImageCacheEntryContext *context = [[[self class] allocWithZone:zone] initWithCacheEntryContext:self];
    return context;
}

@end

@implementation TIPCompleteImageEntryContext

- (instancetype)initWithCacheEntryContext:(TIPImageCacheEntryContext *)context
{
    if (self = [super initWithCacheEntryContext:context]) {
        if ([context respondsToSelector:@selector(imageType)]) {
            _imageType = [(TIPCompleteImageEntryContext *)context imageType];
        }
    }
    return self;
}

@end

@implementation TIPPartialImageEntryContext

- (instancetype)initWithCacheEntryContext:(TIPImageCacheEntryContext *)context
{
    if (self = [super initWithCacheEntryContext:context]) {
        if ([context respondsToSelector:@selector(expectedContentLength)]) {
            _expectedContentLength = [(TIPPartialImageEntryContext *)context expectedContentLength];
        }
        if ([context respondsToSelector:@selector(lastModified)]) {
            _lastModified = [[(TIPPartialImageEntryContext *)context lastModified] copy];
        }
    }
    return self;
}

@end

@implementation TIPImageCacheEntry

- (instancetype)initWithCacheEntry:(TIPImageCacheEntry *)cacheEntry
{
    if (self = [super init]) {
        _identifier = [cacheEntry.identifier copy];
        _partialImage = cacheEntry.partialImage;
        _partialImageContext = [cacheEntry.partialImageContext copy];
        _completeImage = cacheEntry.completeImage;
        _completeImageContext = [cacheEntry.completeImageContext copy];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TIPImageCacheEntry *copy = [[[self class] allocWithZone:zone] initWithCacheEntry:self];
    return copy;
}

- (BOOL)isValid:(BOOL)mustHaveSomeImage
{
    if (!_identifier) {
        return NO;
    }

    if (!_partialImage ^ !_partialImageContext) {
        return NO;
    }

    if (!_completeImage ^ !_completeImageContext) {
        return NO;
    }

    return !mustHaveSomeImage || (_partialImage || _completeImage);
}

- (BOOL)shouldAccessMoveLRUEntryToHead
{
    return self.completeImageContext.updateExpiryOnAccess || self.partialImageContext.updateExpiryOnAccess;
}

- (NSString *)LRUEntryIdentifier
{
    return self.identifier;
}

@end

@implementation TIPImageCacheEntry (Access)

- (nullable NSDate *)mostRecentAccess
{
    NSDate *completeDate = _completeImageContext.lastAccess;
    NSDate *partialDate = _partialImageContext.lastAccess;

    if (!completeDate) {
        return partialDate;
    } else if (!partialDate) {
        return completeDate;
    }

    return [completeDate laterDate:partialDate];
}

@end

@implementation TIPImageMemoryCacheEntry
{
    NSUInteger _memoryCost;
}

@synthesize memoryCost = _memoryCost;

- (void)setCompleteImage:(nullable TIPImageContainer *)completeImage
{
    super.completeImage = completeImage;
    _memoryCost = 0;
}

- (void)setCompleteImageFilePath:(nullable NSString *)completeImageFilePath
{
    TIPAssert(NO && "Should not be used!");
}

- (void)setCompleteImageContext:(nullable TIPCompleteImageEntryContext *)completeImageContext
{
    super.completeImageContext = completeImageContext;
    _memoryCost = 0;
}

- (void)setPartialImage:(nullable TIPPartialImage *)partialImage
{
    super.partialImage = partialImage;
    _memoryCost = 0;
}

- (void)setPartialImageContext:(nullable TIPPartialImageEntryContext *)partialImageContext
{
    super.partialImageContext = partialImageContext;
    _memoryCost = 0;
}

- (NSUInteger)memoryCost
{
    if (!_memoryCost) {
        _memoryCost += self.completeImageData.length;
        _memoryCost += self.partialImage.byteCount;
    }
    return _memoryCost;
}

@end

@implementation TIPImageDiskCacheEntry

@synthesize safeIdentifier = _safeIdentifier;

- (void)setIdentifier:(nullable NSString *)identifier
{
    super.identifier = identifier;
    _safeIdentifier = nil;
}

- (nullable NSString *)safeIdentifier
{
    if (!_safeIdentifier) {
        _safeIdentifier = TIPSafeFromRaw(self.identifier);
    }
    return _safeIdentifier;
}

- (NSString *)LRUEntryIdentifier
{
    return self.safeIdentifier;
}

- (instancetype)initWithCacheEntry:(TIPImageCacheEntry *)cacheEntry
{
    if (self = [super initWithCacheEntry:cacheEntry]) {
        if ([cacheEntry isKindOfClass:[TIPImageDiskCacheEntry class]]) {
            _completeFileSize = [(TIPImageDiskCacheEntry *)cacheEntry completeFileSize];
            _partialFileSize = [(TIPImageDiskCacheEntry *)cacheEntry partialFileSize];
        }
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
