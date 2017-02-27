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

#import "TIP_Project.h"
#import "TIPURLStringCoding.h"

const NSTimeInterval TIPTimeToLiveDefault = 30 * 24 * 60 * 60;

#pragma mark Problem Names

NSString * const TIPProblemDiskCacheUpdateImageEntryCouldNotGenerateFileName = @"TIPProblemDiskCacheUpdateImageEntryCouldNotGenerateFileName";
NSString * const TIPProblemImageFailedToScale = @"TIPProblemImageFailedToScale";
NSString * const TIPProblemImageContainerHasNilImage = @"TIPProblemImageContainerHasNilImage";
NSString * const TIPProblemImageFetchHasInvalidTargetDimensions = @"TIPProblemImageFetchHasInvalidTargetDimensions";
NSString * const TIPProblemImageDownloadedHasGPSInfo = @"TIPProblemImageDownloadedHasGPSInfo";

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
    return @"2.2";
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

NS_INLINE NSString *TIPDataToHexString(NSData *data)
{
    NSUInteger length = data.length;
    unichar* hexChars = (unichar*)malloc(sizeof(unichar) * (length*2));
    unsigned char* bytes = (unsigned char*)data.bytes;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = bytes[i] / 16;
        if (c < 10) {
            c += '0';
        } else {
            c += 'a' - 10;
        }
        hexChars[i*2] = c;
        c = bytes[i] % 16;
        if (c < 10) {
            c += '0';
        } else {
            c += 'a' - 10;
        }
        hexChars[i*2+1] = c;
    }
    NSString* retVal = [[NSString alloc] initWithCharactersNoCopy:hexChars length:length*2 freeWhenDone:YES];
    return retVal;
}

NSString *TIPHash(NSString *string)
{
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    (void)CC_SHA1(data.bytes, (CC_LONG)data.length, hash);
    data = [[NSData alloc] initWithBytesNoCopy:hash length:CC_SHA1_DIGEST_LENGTH freeWhenDone:NO];
    NSString *hashedString = TIPDataToHexString(data);
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
