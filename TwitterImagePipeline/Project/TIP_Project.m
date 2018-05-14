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
#import "TIPURLStringCoding.h"

NS_ASSUME_NONNULL_BEGIN

const NSTimeInterval TIPTimeToLiveDefault = 30 * 24 * 60 * 60;

#pragma mark Problem Names

NSString * const TIPProblemDiskCacheUpdateImageEntryCouldNotGenerateFileName = @"TIPProblemDiskCacheUpdateImageEntryCouldNotGenerateFileName";
NSString * const TIPProblemImageFailedToScale = @"TIPProblemImageFailedToScale";
NSString * const TIPProblemImageContainerHasNilImage = @"TIPProblemImageContainerHasNilImage";
NSString * const TIPProblemImageFetchHasInvalidTargetDimensions = @"TIPProblemImageFetchHasInvalidTargetDimensions";
NSString * const TIPProblemImageDownloadedHasGPSInfo = @"TIPProblemImageDownloadedHasGPSInfo";
NSString * const TIPProblemImageDownloadedCouldNotBeDecoded = @"TIPProblemImageDownloadedCouldNotBeDecoded";
NSString * const TIPProblemImageTooLargeToStoreInDiskCache = @"TIPProblemImageTooLargeToStoreInDiskCache";

#pragma mark Problem User Info Keys

NSString * const TIPProblemInfoKeyImageIdentifier = @"imageIdentifier";
NSString * const TIPProblemInfoKeySafeImageIdentifier = @"safeImageIdentifier";
NSString * const TIPProblemInfoKeyImageURL = @"imageURL";
NSString * const TIPProblemInfoKeyTargetDimensions = @"targetDimensions";
NSString * const TIPProblemInfoKeyTargetContentMode = @"targetContentMode";
NSString * const TIPProblemInfoKeyScaledDimensions = @"scaledDimensions";
NSString * const TIPProblemInfoKeyFetchRequest = @"fetchRequest";
NSString * const TIPProblemInfoKeyImageDimensions = @"dimensions";
NSString * const TIPProblemInfoKeyImageIsAnimated = @"animated";

NSString *TIPVersion()
{
    return @"2.9";
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

CGSize TIPScaleToFitKeepingAspectRatio(CGSize sourceSize, CGSize targetSize, CGFloat scale)
{
    const CGSize scaledTargetSize = CGSizeMake(__tg_ceil(targetSize.width * scale), __tg_ceil(targetSize.height * scale));
    const CGSize scaledSourceSize = CGSizeMake(__tg_ceil(sourceSize.width * scale), __tg_ceil(sourceSize.height * scale));
    const CGFloat rx = scaledTargetSize.width / scaledSourceSize.width;
    const CGFloat ry = scaledTargetSize.height / scaledSourceSize.height;
    const CGFloat ratio = MIN(rx, ry);
    const CGSize size = CGSizeMake((MIN(__tg_ceil(scaledSourceSize.width * ratio), scaledTargetSize.width) / scale), (MIN(__tg_ceil(scaledSourceSize.height * ratio), scaledTargetSize.height) / scale));
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
    NSString *raw = TIPURLDecodeString(safe, NO);
    TIPAssert(raw);
    return raw;
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
