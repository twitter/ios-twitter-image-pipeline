//
//  TIPTests.h
//  TwitterImagePipeline
//
//  Created on 8/31/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TIPTests/TIPTestURLProtocol.h>

#define kTIPTestsImageFetchDownloadProviderClassKey @"TIP_TESTS_IMAGE_FETCH_DOWNLOAD_PROVIDER_CLASS"

FOUNDATION_EXTERN Class TIPTestsImageFetchDownloadProviderOverrideClass(void);
FOUNDATION_EXTERN NSBundle *TIPTestsResourceBundle(void);

// Need something to be compiled into the unit tests bundle or else there's no binary to run!
// Put TIP_TESTS_IMPLEMENT_DUMMY in a code file for the consuming unit tests

#define TIP_TESTS_IMPLEMENT_DUMMY \
void TwitterImagePipelineTestsDummyFunction() \
{ \
    NSLog(@"TwitterImagePipelineTestsDummyFunction"); \
}
