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

#pragma mark - Constants

FOUNDATION_EXTERN const NSTimeInterval TIPTimeToLiveDefault; // 30 days

#pragma mark - Version

FOUNDATION_EXTERN NSString * __nonnull TIPVersion();

#pragma mark - Helpers

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN BOOL TIPImageTypeSupportsLossyQuality(NSString * __nullable type);

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

NS_INLINE CGSize TIPScaleToFillKeepingAspectRatio(CGSize sourceSize, CGSize targetSize, CGFloat scale)
{
    const CGSize scaledTargetSize = CGSizeMake(__tg_ceil(targetSize.width * scale), __tg_ceil(targetSize.height * scale));
    const CGSize scaledSourceSize = CGSizeMake(__tg_ceil(sourceSize.width * scale), __tg_ceil(sourceSize.height * scale));
    const CGFloat rx = scaledTargetSize.width / scaledSourceSize.width;
    const CGFloat ry = scaledTargetSize.height / scaledSourceSize.height;
    CGSize size;
    if (rx > ry) {
        // cap width to scaled target size's width
        // and floor the larger dimension (height)
        size = CGSizeMake((MIN(__tg_ceil(scaledSourceSize.width * rx), scaledTargetSize.width) / scale), (__tg_floor(scaledSourceSize.height * rx) / scale));
    } else {
        // cap width to scaled target size's width
        // and floor the larger dimension (height)
        size = CGSizeMake((__tg_floor(scaledSourceSize.width * ry) / scale), (MIN(__tg_ceil(scaledSourceSize.height * ry), scaledTargetSize.height) / scale));
    }
    return size;
}

NS_INLINE CGSize TIPScaleToFitKeepingAspectRatio(CGSize sourceSize, CGSize targetSize, CGFloat scale)
{
    const CGSize scaledTargetSize = CGSizeMake(__tg_ceil(targetSize.width * scale), __tg_ceil(targetSize.height * scale));
    const CGSize scaledSourceSize = CGSizeMake(__tg_ceil(sourceSize.width * scale), __tg_ceil(sourceSize.height * scale));
    const CGFloat rx = scaledTargetSize.width / scaledSourceSize.width;
    const CGFloat ry = scaledTargetSize.height / scaledSourceSize.height;
    const CGFloat ratio = MIN(rx, ry);
    const CGSize size = CGSizeMake((MIN(__tg_ceil(scaledSourceSize.width * ratio), scaledTargetSize.width) / scale), (MIN(__tg_ceil(scaledSourceSize.height * ratio), scaledTargetSize.height) / scale));
    return size;
}

#define TIP_UPDATE_BYTES(readWriteTotalVar, addValue, subValue, name) \
do { \
    const SInt64 oldSize = readWriteTotalVar; \
    const SInt64 newSize = oldSize + (SInt64)(addValue) - (SInt64)(subValue); \
    TIPAssertMessage(newSize >= 0, name @" - Old: %lli, Add: %llu, Sub: %llu, New: %lli", oldSize, bytesAdded, bytesRemoved, newSize); \
    readWriteTotalVar = newSize; \
} while (0)

NS_ASSUME_NONNULL_END

#pragma mark - Debugging Tools

FOUNDATION_EXTERN BOOL TIPShouldAssertDuringPipelineRegistation();
FOUNDATION_EXTERN void TIPSetShouldAssertDuringPipelineRegistation(BOOL shouldAssertDuringPipelineRegistration);

#pragma mark - BG Task

NS_INLINE dispatch_block_t __nullable TIPStartBackgroundTask(NSString * __nullable name)
{
    __block NSUInteger taskId = UIBackgroundTaskInvalid;
    dispatch_block_t clearTaskBlock = NULL;
    Class UIApplicationClass = [UIApplication class];
    if (!TIPIsExtension()) {
        clearTaskBlock = ^{
            if (taskId != UIBackgroundTaskInvalid) {
                [[UIApplicationClass sharedApplication] endBackgroundTask:taskId];
                taskId = UIBackgroundTaskInvalid;
            }
        };
        taskId = [[UIApplicationClass sharedApplication] beginBackgroundTaskWithName:name expirationHandler:clearTaskBlock];
    }
    return clearTaskBlock;
}

#pragma twitter startignorestylecheck

#define TIPStartMethodScopedBackgroundTask() \
dispatch_block_t clearTaskBlock##__LINE__ = TIPStartBackgroundTask([NSString stringWithFormat:@"[%@ %@]", NSStringFromClass([self class]), NSStringFromSelector(_cmd)]); \
tip_defer(^{ if (clearTaskBlock##__LINE__) { clearTaskBlock##__LINE__(); } });

#pragma twitter stopignorestylecheck
