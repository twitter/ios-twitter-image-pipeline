//
//  TIPTests.m
//  TwitterImagePipeline
//
//  Created on 8/31/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import "TIPTestImageFetchDownloadInternalWithStubbing.h"

#import "TIPTests.h"

Class TIPTestsImageFetchDownloadProviderOverrideClass()
{
    static Class sImageFetchDownloadProviderClass = Nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *imageFetchClassName = nil;
        for (NSBundle *innerBundle in [NSBundle allBundles]) {
            if ([innerBundle.bundlePath hasSuffix:@".xctest"]) {
                imageFetchClassName = [innerBundle objectForInfoDictionaryKey:kTIPTestsImageFetchDownloadProviderClassKey];
                if (imageFetchClassName) {
                    break;
                }
            }
        }
        if (imageFetchClassName) {
            sImageFetchDownloadProviderClass = NSClassFromString(imageFetchClassName);
        }
        if (!sImageFetchDownloadProviderClass) {
            sImageFetchDownloadProviderClass = [TIPTestImageFetchDownloadProviderInternalWithStubbing class];
        }
    });
    return sImageFetchDownloadProviderClass;
}

NSBundle *TIPTestsResourceBundle(void)
{
    static NSBundle *sBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.twitter.TIPTestsResources"];
        if (!bundle) {
            for (NSBundle *innerBundle in [NSBundle allBundles]) {
                if ([innerBundle.bundlePath hasSuffix:@".xctest"]) {
                    bundle = [NSBundle bundleWithPath:[innerBundle.bundlePath stringByAppendingPathComponent:@"TIPTestsResources.bundle"]];
                    if (bundle) {
                        break;
                    }
                }
            }
        }
        sBundle = bundle;
    });

    if (!sBundle) {
        @throw [NSException exceptionWithName:NSGenericException reason:@"Missing TIPTests.framework bundle!" userInfo:nil];
    }
    return sBundle;
}
