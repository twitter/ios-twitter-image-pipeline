//
//  TIPTests.m
//  TwitterImagePipeline
//
//  Created on 8/31/16.
//  Copyright © 2020 Twitter. All rights reserved.
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
            if (!sImageFetchDownloadProviderClass) {
                NSLog(@"\n\n********************\n\nFailed to load %@ class!\nNo %@ found!\n\n********************\n", kTIPTestsImageFetchDownloadProviderClassKey, imageFetchClassName);
            }
        }
        if (!sImageFetchDownloadProviderClass) {
            sImageFetchDownloadProviderClass = [TIPTestImageFetchDownloadProviderInternalWithStubbing class];
        }
    });
    return sImageFetchDownloadProviderClass;
}

NSBundle *TIPTestsResourceBundle(void)
{
    return SWIFTPM_MODULE_BUNDLE;
}
