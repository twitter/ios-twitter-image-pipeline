//
//  TIPImageContext.m
//  TwitterImagePipeline
//
//  Created on 3/6/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPImageCacheEntry.h"
#import "TIPImageUtils.h"
#import "TIPPartialImage.h"

#pragma mark - Private Declarations

@interface TIPImageCacheEntryContext ()
- (instancetype)initWithCacheEntryContext:(nonnull TIPImageCacheEntryContext *)context;
@end

@interface TIPImageCacheEntry ()
@property (nonatomic) NSData *completeImageData;
@property (nonatomic, copy) NSString *completeImageFilePath;
- (instancetype)initWithCacheEntry:(nonnull TIPImageCacheEntry *)cacheEntry;
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

- (id)copyWithZone:(NSZone *)zone
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

- (id)copyWithZone:(NSZone *)zone
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

- (NSDate *)mostRecentAccess
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

- (NSString *)LRUEntryIdentifier
{
    return self.identifier;
}

@end

@implementation TIPImageMemoryCacheEntry
{
    NSUInteger _memoryCost;
}

@synthesize memoryCost = _memoryCost;

- (void)setCompleteImage:(TIPImageContainer *)completeImage
{
    super.completeImage = completeImage;
    _memoryCost = 0;
}

- (void)setCompleteImageData:(NSData *)completeImageData
{
    TIPAssert(NO && "Should not be used!");
}

- (void)setCompleteImageFilePath:(NSString *)completeImageFilePath
{
    TIPAssert(NO && "Should not be used!");
}

- (void)setCompleteImageContext:(TIPCompleteImageEntryContext *)completeImageContext
{
    super.completeImageContext = completeImageContext;
    _memoryCost = 0;
}

- (void)setPartialImage:(TIPPartialImage *)partialImage
{
    super.partialImage = partialImage;
    _memoryCost = 0;
}

- (void)setPartialImageContext:(TIPPartialImageEntryContext *)partialImageContext
{
    super.partialImageContext = partialImageContext;
    _memoryCost = 0;
}

- (NSUInteger)memoryCost
{
    if (!_memoryCost) {
        _memoryCost += self.completeImage.sizeInMemory;
        TIPPartialImage *partialImage = self.partialImage;
        if (partialImage && partialImage.state > TIPPartialImageStateLoadingHeaders) {
            _memoryCost += TIPEstimateMemorySizeOfImageWithSettings(partialImage.dimensions, 1.0, 4 /* presume 4 bytes per pixel */, (partialImage.isAnimated) ? partialImage.frameCount : 1);
        } else {
            _memoryCost += partialImage.byteCount;
        }
    }
    return _memoryCost;
}

@end

@implementation TIPImageDiskCacheEntry

@synthesize safeIdentifier = _safeIdentifier;

- (void)setIdentifier:(NSString *)identifier
{
    super.identifier = identifier;
    _safeIdentifier = nil;
}

- (NSString *)safeIdentifier
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

@end
