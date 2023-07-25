//
//  TIPImageFetchDelegateTests.m
//  TwitterImagePipeline
//
//  Created on 2/4/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "TIP_Project.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageFetchDownloadInternal.h"
#import "TIPImageFetchOperation+Project.h"

#import "TIPTests.h"

static TIPImagePipeline *sPipeline = nil;
static NSString *sImagePath = nil;

@interface TIPImageFetchDelegateTests : XCTestCase <TIPImageFetchRequest>
@end

@interface TIPImageFetchTestDelegate : NSObject <TIPImageFetchDelegate>
@property (nonatomic) BOOL discard;
@end

@implementation TIPImageFetchDelegateTests

+ (void)setUp
{
    TIPGlobalConfiguration *globalConfig = [TIPGlobalConfiguration sharedInstance];
    TIPSetDebugSTOPOnAssertEnabled(NO);
    TIPSetShouldAssertDuringPipelineRegistation(NO);

    sImagePath = [TIPTestsResourceBundle() pathForResource:@"twitterfied" ofType:@"png"];
    sPipeline = [[TIPImagePipeline alloc] initWithIdentifier:@"com.twitter.test.delegate.pipeline"];
    globalConfig.imageFetchDownloadProvider = [[TIPTestsImageFetchDownloadProviderOverrideClass() alloc] init];
    [globalConfig clearAllDiskCaches];
    [globalConfig clearAllMemoryCaches];
}

- (void)tearDown
{
    [sPipeline clearDiskCache];
    [sPipeline clearMemoryCaches];
    [super tearDown];
}

+ (void)tearDown
{
    TIPSetDebugSTOPOnAssertEnabled(YES);
    TIPSetShouldAssertDuringPipelineRegistation(YES);

    [sPipeline clearDiskCache];
    [sPipeline clearMemoryCaches];
    sPipeline = nil;
    sImagePath = nil;
    [TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider = nil;
}

- (TIPImageFetchOperation *)_fetchAndRunWithDelegateBeingStrong:(BOOL)strong discard:(BOOL)discard
{
    id<TIPImageFetchDownloadProviderWithStubbingSupport> provider = (id<TIPImageFetchDownloadProviderWithStubbingSupport>)[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider;
    [provider addDownloadStubForRequestURL:self.imageURL responseData:[NSData dataWithContentsOfFile:self.cannedImagePath options:NSDataReadingMappedIfSafe error:NULL] responseMIMEType:@"image/png" shouldSupportResuming:YES suggestedBitrate:2 * 1024 * 1024 * 8];
    tip_defer(^{
        [provider removeDownloadStubForRequestURL:self.imageURL];
    });

    @autoreleasepool {
        TIPImageFetchTestDelegate *delegate = [[TIPImageFetchTestDelegate alloc] init];
        delegate.discard = discard;

        TIPImageFetchOperation *op = [sPipeline operationWithRequest:self context:(strong) ? delegate : nil delegate:delegate];
        op.priority = NSOperationQueuePriorityHigh;
        [sPipeline fetchImageWithOperation:op];
        delegate = nil;

        [op waitUntilFinishedWithoutBlockingRunLoop];

        return op;
    }
}

- (void)test1_StrongDelegate
{
    TIPImageFetchOperation *op = [self _fetchAndRunWithDelegateBeingStrong:YES discard:NO];
    XCTAssertEqual(op.state, TIPImageFetchOperationStateSucceeded);
    XCTAssertNotNil(op.finalResult.imageContainer.image);
}

- (void)test2_WeakDelegate
{
    TIPImageFetchOperation *op = [self _fetchAndRunWithDelegateBeingStrong:NO discard:NO];
    XCTAssertEqual(op.state, TIPImageFetchOperationStateCancelled);
    XCTAssertNil(op.finalResult.imageContainer.image);
    XCTAssertEqual(NSOperationQueuePriorityHigh, op.priority);
}

- (void)test3_DiscardStrongDelegate
{
    TIPImageFetchOperation *op = [self _fetchAndRunWithDelegateBeingStrong:YES discard:YES];
    XCTAssertEqual(op.state, TIPImageFetchOperationStateSucceeded);
    XCTAssertNotNil(op.finalResult.imageContainer.image);
}

- (void)test4_DiscardWeakDelegate
{
    TIPImageFetchOperation *op = [self _fetchAndRunWithDelegateBeingStrong:NO discard:YES];
    XCTAssertEqual(op.state, TIPImageFetchOperationStateSucceeded);
    XCTAssertNotNil(op.finalResult.imageContainer.image);
}

#pragma mark TIPImageFetchPseudoRequest

- (NSURL *)imageURL
{
    return [NSURL URLWithString:@"https://dummy.twitter.com/media/GUID.png"];
}

- (NSString *)cannedImagePath
{
    return sImagePath;
}

@end

@implementation TIPImageFetchTestDelegate
{
    id _strongSelf;
}

- (instancetype)init
{
    if (self = [super init]) {
        _strongSelf = self;
    }
    return self;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op willAttemptToLoadFromSource:(TIPImageLoadSource)source
{
    if (TIPImageLoadSourceNetwork == source || TIPImageLoadSourceNetworkResumed == source) {
        if (self.discard) {
            [op discardDelegate];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_strongSelf = nil;
        });
    }
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFinalImage:(id<TIPImageFetchResult>)finalResult
{
    _strongSelf = nil;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didFailToLoadFinalImage:(NSError *)error
{
    _strongSelf = nil;
}

@end
