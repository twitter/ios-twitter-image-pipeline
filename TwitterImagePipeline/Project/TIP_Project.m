//
//  TIP_Project.m
//  TwitterImagePipeline
//
//  Created on 3/5/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>
#include <objc/runtime.h>

#import "NSData+TIPAdditions.h"
#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPURLStringCoding.h"

NS_ASSUME_NONNULL_BEGIN

const NSTimeInterval TIPTimeToLiveDefault = 30 * 24 * 60 * 60;

#pragma mark Problem Names

TIPProblem TIPProblemDiskCacheUpdateImageEntryCouldNotGenerateFileName = @"TIPProblemDiskCacheUpdateImageEntryCouldNotGenerateFileName";
TIPProblem TIPProblemImageFailedToScale = @"TIPProblemImageFailedToScale";
TIPProblem TIPProblemImageContainerHasNilImage = @"TIPProblemImageContainerHasNilImage";
TIPProblem TIPProblemImageFetchHasInvalidTargetDimensions = @"TIPProblemImageFetchHasInvalidTargetDimensions";
TIPProblem TIPProblemImageDownloadedHasGPSInfo = @"TIPProblemImageDownloadedHasGPSInfo";
TIPProblem TIPProblemImageDownloadedCouldNotBeDecoded = @"TIPProblemImageDownloadedCouldNotBeDecoded";
TIPProblem TIPProblemImageTooLargeToStoreInDiskCache = @"TIPProblemImageTooLargeToStoreInDiskCache";
TIPProblem TIPProblemImageDownloadedWithUnnecessaryError = @"TIPProblemImageDownloadedWithUnnecessaryError";

#pragma mark Problem User Info Keys

TIPProblemInfoKey TIPProblemInfoKeyImageIdentifier = @"imageIdentifier";
TIPProblemInfoKey TIPProblemInfoKeySafeImageIdentifier = @"safeImageIdentifier";
TIPProblemInfoKey TIPProblemInfoKeyImageURL = @"imageURL";
TIPProblemInfoKey TIPProblemInfoKeyTargetDimensions = @"targetDimensions";
TIPProblemInfoKey TIPProblemInfoKeyTargetContentMode = @"targetContentMode";
TIPProblemInfoKey TIPProblemInfoKeyScaledDimensions = @"scaledDimensions";
TIPProblemInfoKey TIPProblemInfoKeyFetchRequest = @"fetchRequest";
TIPProblemInfoKey TIPProblemInfoKeyImageDimensions = @"dimensions";
TIPProblemInfoKey TIPProblemInfoKeyImageIsAnimated = @"animated";

NSString *TIPVersion()
{
    TIPStaticAssert(TIP_PROJECT_VERSION >= 1.0 && TIP_PROJECT_VERSION <= 10.0, INVALID_TIP_VERSION);

#define __TIP_VERSION(version) @"" #version
#define _TIP_VERSION(version) __TIP_VERSION( version )
#define TIP_VERSION()  _TIP_VERSION( TIP_PROJECT_VERSION )

    return TIP_VERSION();
}

void TIPSwizzle(Class cls, SEL originalSelector, SEL swizzledSelector)
{
    const Method originalMethod = class_getInstanceMethod(cls, originalSelector);
    const Method swizzledMethod = class_getInstanceMethod(cls, swizzledSelector);
    const BOOL didAddMethod = class_addMethod(cls, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
    if (didAddMethod) {
        class_replaceMethod(cls, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

void TIPClassSwizzle(Class cls, SEL originalSelector, SEL swizzledSelector)
{
    cls = object_getClass((id)cls);
    const Method originalMethod = class_getClassMethod(cls, originalSelector);
    const Method swizzledMethod = class_getClassMethod(cls, swizzledSelector);
    const BOOL didAddMethod = class_addMethod(cls, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
    if (didAddMethod) {
        class_replaceMethod(cls, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

static volatile BOOL sShouldAssertDuringPipelineRegistration = YES;

BOOL TIPShouldAssertDuringPipelineRegistation()
{
    return sShouldAssertDuringPipelineRegistration;
}

void TIPSetShouldAssertDuringPipelineRegistation(BOOL shouldAssertDuringPipelineRegistration)
{
    sShouldAssertDuringPipelineRegistration = shouldAssertDuringPipelineRegistration;
}

CGSize TIPScaleToFillKeepingAspectRatio(CGSize sourceSize, CGSize targetSize, CGFloat scale)
{
    const CGSize scaledTargetSize = CGSizeMake(__tg_ceil(targetSize.width * scale), __tg_ceil(targetSize.height * scale));
    const CGSize scaledSourceSize = CGSizeMake(__tg_ceil(sourceSize.width * scale), __tg_ceil(sourceSize.height * scale));
    const CGFloat rx = scaledTargetSize.width / scaledSourceSize.width;
    const CGFloat ry = scaledTargetSize.height / scaledSourceSize.height;

    CGSize size;
    if (rx > ry) {
        // Width will be the scaled target width
        const CGFloat targetWidth = scaledTargetSize.width;

        // get the height from the width preserving aspect-ratio of source
        const CGFloat ar = scaledSourceSize.height / scaledSourceSize.width;
        const CGFloat aspectHeight = targetWidth * ar;
        const CGFloat targetHeight = round(aspectHeight);

        size = CGSizeMake(targetWidth / scale, targetHeight / scale);
    } else {
        // Height will be the scaled target height
        const CGFloat targetHeight = scaledTargetSize.height;

        // get the width from the height preserving aspect-ratio of source
        const CGFloat ar = scaledSourceSize.width / scaledSourceSize.height;
        const CGFloat aspectWidth = targetHeight * ar;
        const CGFloat targetWidth = round(aspectWidth);

        size = CGSizeMake(targetWidth / scale, targetHeight / scale);
    }

    return size;
}

CGSize TIPScaleToFitKeepingAspectRatio(CGSize sourceSize, CGSize targetSize, CGFloat scale)
{
    const CGSize scaledTargetSize = CGSizeMake(__tg_ceil(targetSize.width * scale), __tg_ceil(targetSize.height * scale));
    const CGSize scaledSourceSize = CGSizeMake(__tg_ceil(sourceSize.width * scale), __tg_ceil(sourceSize.height * scale));
    const CGFloat rx = scaledTargetSize.width / scaledSourceSize.width;
    const CGFloat ry = scaledTargetSize.height / scaledSourceSize.height;

    CGSize size;
    if (rx < ry) {
        // Width will be the scaled target width
        const CGFloat targetWidth = scaledTargetSize.width;

        // get the height from the width preserving aspect-ratio of source
        const CGFloat ar = scaledSourceSize.height / scaledSourceSize.width;
        const CGFloat aspectHeight = targetWidth * ar;
        const CGFloat targetHeight = round(aspectHeight);

        size = CGSizeMake(targetWidth / scale, targetHeight / scale);
    } else {
        // Height will be the scaled target height
        const CGFloat targetHeight = scaledTargetSize.height;

        // get the width from the height preserving aspect-ratio of source
        const CGFloat ar = scaledSourceSize.width / scaledSourceSize.height;
        const CGFloat aspectWidth = targetHeight * ar;
        const CGFloat targetWidth = round(aspectWidth);

        size = CGSizeMake(targetWidth / scale, targetHeight / scale);
    }

    return size;
}

NSString *TIPHash(NSString *string)
{
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    (void)CC_SHA1(data.bytes, (CC_LONG)data.length, hash);
    data = [[NSData alloc] initWithBytesNoCopy:hash length:CC_SHA1_DIGEST_LENGTH freeWhenDone:NO];
    NSString *hashedString = [data tip_hexStringValue];
    TIPAssert(hashedString);
    return hashedString;
}

NSString *TIPSafeFromRaw(NSString *raw)
{
    NSString *safe = TIPURLEncodeString(raw);
    if (safe.length > (NAME_MAX - 4 /* 4 = 3 characters for extension "tmp" + 1 character for '.' */)) {
        safe = TIPHash(safe);
    }
    TIPAssert(safe.length != 0);
    return safe;
}

NSString *TIPRawFromSafe(NSString *safe)
{
    TIPAssert(safe != 0);
    NSString *raw = TIPURLDecodeString(safe, NO);
    TIPAssert(raw != 0);
    return (NSString * _Nonnull)raw; // TIPAssert() performed 1 line above
}

dispatch_block_t __nullable TIPStartBackgroundTask(NSString * __nullable name)
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
        taskId = [[UIApplicationClass sharedApplication] beginBackgroundTaskWithName:name
                                                                   expirationHandler:clearTaskBlock];
    }
    return clearTaskBlock;
}

NS_ASSUME_NONNULL_END
