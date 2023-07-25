//
//  TIP_Project.h
//  TwitterImagePipeline
//
//  Created on 3/5/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#include <mach/mach_time.h>
#include <tgmath.h>

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIApplication.h>

#import "TIP_ProjectCommon.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Version

FOUNDATION_EXTERN NSString *TIPVersion(void);

#pragma mark - Helpers

NS_INLINE BOOL tip_never(void)
{
    return NO;
}

FOUNDATION_EXTERN BOOL TIPImageTypeSupportsLossyQuality(NSString * __nullable type);
FOUNDATION_EXTERN BOOL TIPImageTypeSupportsIndexedPalette(NSString * __nullable type);

FOUNDATION_EXTERN void TIPSwizzle(Class cls, SEL originalSelector, SEL swizzledSelector);
FOUNDATION_EXTERN void TIPClassSwizzle(Class cls, SEL originalSelector, SEL swizzledSelector);

#define TIPSizeEqualToZero(targetSize) CGSizeEqualToSize((targetSize), CGSizeZero)
NS_INLINE BOOL TIPSizeGreaterThanZero(CGSize targetSize)
{
    return targetSize.width > 0 && targetSize.height > 0;
}

FOUNDATION_EXTERN NSString *TIPSafeFromRaw(NSString *raw); // URL encodes raw.  If that encoded string is > the max length of a file name (less 4 characters for supporting a 3 character extension), it will be hashed.
FOUNDATION_EXTERN NSString *TIPRawFromSafe(NSString *safe); // might not be the same as the input to "SafeFromRaw" since long "raw" strings will be hashed
FOUNDATION_EXTERN NSString *TIPHash(NSString *string);

FOUNDATION_EXTERN CGSize TIPScaleToFillKeepingAspectRatio(CGSize sourceSize, CGSize targetSize, CGFloat scale);

FOUNDATION_EXTERN CGSize TIPScaleToFitKeepingAspectRatio(CGSize sourceSize, CGSize targetSize, CGFloat scale);

#define TIP_UPDATE_BYTES(readWriteTotalVar, addValue, subValue, name) \
do { \
    const SInt64 oldSize = readWriteTotalVar; \
    const SInt64 newSize = oldSize + (SInt64)(addValue) - (SInt64)(subValue); \
    TIPAssertMessage(newSize >= 0, name @" - Old: %lli, Add: %llu, Sub: %llu, New: %lli", oldSize, bytesAdded, bytesRemoved, newSize); \
    readWriteTotalVar = newSize; \
} while (0)

#pragma mark - Debugging Tools

FOUNDATION_EXTERN BOOL TIPShouldAssertDuringPipelineRegistation(void);
FOUNDATION_EXTERN void TIPSetShouldAssertDuringPipelineRegistation(BOOL shouldAssertDuringPipelineRegistration);

#pragma mark - BG Task

FOUNDATION_EXTERN dispatch_block_t __nullable TIPStartBackgroundTask(NSString * __nullable name);

#pragma twitter startignorestylecheck

#define TIPStartMethodScopedBackgroundTask(name) \
dispatch_block_t tip_macro_concat(clearTaskBlock, __LINE__) = TIPStartBackgroundTask([NSString stringWithFormat:@"[%@ %@]", NSStringFromClass([self class]), @( #name )]); \
tip_defer(^{ if (tip_macro_concat(clearTaskBlock, __LINE__)) { tip_macro_concat(clearTaskBlock, __LINE__)(); } });

#pragma twitter endignorestylecheck

NS_ASSUME_NONNULL_END
