//
//  TIPImagePipelineTests.m
//  TwitterImagePipeline
//
//  Created on 4/27/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageDiskCache.h"
#import "TIPImageMemoryCache.h"
#import "TIPImagePipeline+Project.h"
#import "TIPImageRenderedCache.h"
#import "TIPTests.h"
#import "TIPTestsSharedUtils.h"

@interface TestImageStoreRequest : NSObject <TIPImageStoreRequest>
@property (nonatomic) NSURL *imageURL;
@property (nonatomic, copy) NSString *imageFilePath;
@end

@implementation TestImageStoreRequest
@end

@interface TIPImagePipelineTests_Base : TIPImagePipelineBaseTests
- (void)runFillingTheCaches:(TIPImagePipeline *)pipeline bps:(uint64_t)bps testCacheHits:(BOOL)testCacheHits;
@end

@interface TIPImagePipelineTests_One : TIPImagePipelineTests_Base
@end

@interface TIPImagePipelineTests_Two : TIPImagePipelineTests_Base
@end

@interface TIPImagePipelineTests_Three : TIPImagePipelineTests_Base
@end

@implementation TIPImagePipelineTests_Base

- (void)runFillingTheCaches:(TIPImagePipeline *)pipeline bps:(uint64_t)bps testCacheHits:(BOOL)testCacheHits
{
    id<TIPImageFetchDownloadProviderWithStubbingSupport> provider = (id<TIPImageFetchDownloadProviderWithStubbingSupport>)[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider;

    NSMutableArray *URLs = [NSMutableArray array];
    for (NSUInteger i = 0; i < 10; i++) {
        [URLs addObject:[TIPImagePipelineBaseTests dummyURLWithPath:[NSUUID UUID].UUIDString]];
    }

    // First pass, load em up
    // Second pass (if testCacheHits), reload since older version will have been purged by full cache
    const NSUInteger numberOfRuns = (testCacheHits) ? 2 : 1;
    for (NSUInteger i = 0; i < numberOfRuns; i++) {
        for (NSURL *URL in URLs) {
            @autoreleasepool {
                TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
                request.imageType = TIPImageTypeJPEG;
                request.progressiveSource = YES;
                request.imageURL = URL;
                request.targetDimensions = kCarnivalImageDimensions;
                request.targetContentMode = UIViewContentModeScaleToFill;
                TIPImagePipelineTestContext *context = [[TIPImagePipelineTestContext alloc] init];
                [TIPImagePipelineTestFetchRequest stubRequest:request bitrate:bps resumable:YES];
                TIPImageFetchOperation *op = [pipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
                [op waitUntilFinishedWithoutBlockingRunLoop];
                [provider removeDownloadStubForRequestURL:request.imageURL];
                XCTAssertEqual(op.state, TIPImageFetchOperationStateSucceeded);
                XCTAssertEqual(context.finalSource, TIPImageLoadSourceNetwork);
            }
        }
    }

    // visit in reverse order
    NSUInteger memMatches = 0;
    NSUInteger diskMatches = 0;
    for (NSURL *URL in URLs.reverseObjectEnumerator) {
        TIPImageLoadSource source = TIPImageLoadSourceUnknown;
        @autoreleasepool {
            TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
            request.imageType = TIPImageTypeJPEG;
            request.progressiveSource = YES;
            request.imageURL = URL;
            request.targetDimensions = kCarnivalImageDimensions;
            request.targetContentMode = UIViewContentModeScaleToFill;
            TIPImagePipelineTestContext *context = [[TIPImagePipelineTestContext alloc] init];
            [TIPImagePipelineTestFetchRequest stubRequest:request bitrate:bps resumable:YES];
            TIPImageFetchOperation *op = [pipeline undeprecatedFetchImageWithRequest:request context:context delegate:self];
            [op waitUntilFinishedWithoutBlockingRunLoop];
            [provider removeDownloadStubForRequestURL:request.imageURL];
            XCTAssertEqual(op.state, TIPImageFetchOperationStateSucceeded);
            source = op.finalResult.imageSource;
            if (source == TIPImageLoadSourceMemoryCache) {
                memMatches++;
            } else if (source == TIPImageLoadSourceDiskCache) {
                diskMatches++;
            } else {
                break;
            }
        }
    }

    if (testCacheHits) {
        XCTAssertGreaterThan(memMatches, (NSUInteger)0);
        XCTAssertGreaterThan(diskMatches, (NSUInteger)0);
    }
}

- (void)checkFileAttributes:(TIPImagePipeline *)pipeline
{
    // Check the file attributes
    XCTestExpectation *expectation = [self expectationWithDescription:@"wait for inspection to complete expectation"];
    __block NSDictionary<NSString *, id> *attributes = nil;
    __block NSArray<NSString *> *attributeNames = nil;
    NSDictionary<NSString *, Class> *attributeKeyKindMap = @{
                                                             @"ANI" : [NSNumber class] /*BOOL*/,
                                                             @"LAD" : [NSDate class],
                                                             @"LMD" : [NSString class],
                                                             @"TTL" : [NSNumber class],
                                                             @"URL" : [NSURL class],
                                                             @"clen" : [NSNumber class],
                                                             @"dX" : [NSNumber class],
                                                             @"dY" : [NSNumber class],
                                                             @"uTTL" : [NSNumber class] /*BOOL*/,
                                                             // @"pl" : [NSNumber class] /*BOOL*/,
                                                             };
    NSArray<NSString *> *expectedAttributeNames = [attributeKeyKindMap.allKeys sortedArrayUsingSelector:@selector(compare:)];

    [pipeline inspect:^(TIPImagePipelineInspectionResult * _Nullable result) {
        if (!result.completeDiskEntries.count) {
            [expectation fulfill];
            return;
        }

        [pipeline copyDiskCacheFileWithIdentifier:result.completeDiskEntries.firstObject.identifier
                                       completion:^(NSString * _Nullable temporaryFilePath, NSError * _Nullable error) {
                                           XCTAssertNil(error);
                                           XCTAssertNotNil(temporaryFilePath);

                                           attributeNames = [TIPListXAttributesForFile(temporaryFilePath) sortedArrayUsingSelector:@selector(compare:)];
                                           attributes = TIPGetXAttributesForFile(temporaryFilePath, attributeKeyKindMap);

                                           // Fulfill async after 1 second.
                                           // If anything allocated in the attributes lookups deallocs we
                                           // want to fail rather than have a race condition that might succeed.
                                           dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                               [expectation fulfill];
                                           });
                                       }];
    }];

    [self waitForExpectations:@[expectation] timeout:10];

    XCTAssertNotNil(attributeNames);
    XCTAssertEqualObjects(attributeNames, expectedAttributeNames);
    NSArray<NSString *> *parsedAttributeNames = [attributes.allKeys sortedArrayUsingSelector:@selector(compare:)];
    XCTAssertNotNil(parsedAttributeNames);
    XCTAssertEqualObjects(parsedAttributeNames, expectedAttributeNames);
}

@end

@implementation TIPImagePipelineTests_One

- (void)testImagePipelineConstruction
{
    NSString *identifier = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ.abcdefghijklmnopqrstuvwxyz_0123456789-";
    TIPImagePipeline *pipeline = nil;

    @autoreleasepool {
        pipeline = [[TIPImagePipeline alloc] initWithIdentifier:identifier];
        XCTAssertNotNil(pipeline);
        pipeline = nil;
    }

    @autoreleasepool {
        pipeline = [[TIPImagePipeline alloc] initWithIdentifier:identifier];
        XCTAssertNotNil(pipeline);
    }

    @autoreleasepool {
        TIPImagePipeline *pipeline2 = [[TIPImagePipeline alloc] initWithIdentifier:identifier];
        XCTAssertNil(pipeline2);
        pipeline = nil;
    }

    @autoreleasepool {
        pipeline = [[TIPImagePipeline alloc] initWithIdentifier:[identifier stringByReplacingOccurrencesOfString:@"." withString:@" "]];
        XCTAssertNil(pipeline);
        pipeline = nil;
    }

    @autoreleasepool {
        pipeline = [[TIPImagePipeline alloc] initWithIdentifier:[TIPImagePipelineBaseTests sharedPipeline].identifier];
        XCTAssertNil(pipeline);
        pipeline = nil;
    }
}

- (void)testConcurrentManifestLoad
{
    NSArray *(^buildComparablesFromPipeline)(TIPImagePipeline *) = ^(TIPImagePipeline *pipeline) {
        __block NSArray *comparables = nil;
        XCTestExpectation *builtComparables = [self expectationWithDescription:@"built comparables"];

        [pipeline inspect:^(TIPImagePipelineInspectionResult * _Nullable result) {
            NSArray *entries = [result.completeDiskEntries arrayByAddingObjectsFromArray:result.partialDiskEntries];

            NSMutableArray *comparablesMutable = [NSMutableArray arrayWithCapacity:entries.count];
            for (id<TIPImagePipelineInspectionResultEntry> entry in entries) {
                [comparablesMutable addObject:@[[entry identifier], [entry URL], [NSValue valueWithCGSize:[entry dimensions]], @([entry bytesUsed]), @([entry progress])]];
            };

            comparables = comparablesMutable;
            [builtComparables fulfill];
        }];

        [self waitForExpectationsWithTimeout:20 handler:nil];
        builtComparables = nil;
        return comparables;
    };

    NSString *identifier = @"concurrentManifestLoadTest";

    [self _safelyOpenPipelineWithIdentifier:identifier executingBlock:^(TIPImagePipeline *initialPipeline) {

        TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
        request.cannedImageFilePath = [TIPTestsResourceBundle() pathForResource:@"twitterfied" ofType:@"pjpg"];

        id<TIPImageFetchDownloadProviderWithStubbingSupport> provider = (id<TIPImageFetchDownloadProviderWithStubbingSupport>)[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider;

        NSMutableArray<NSURL *> *stubbedRequestURLs = [NSMutableArray array];
        NSOperation *blockOp = [NSBlockOperation blockOperationWithBlock:^{}];
        for (NSUInteger i = 0; i < 150; i++) {
            request.imageURL = [TIPImagePipelineBaseTests dummyURLWithPath:[NSUUID UUID].UUIDString];
            [TIPImagePipelineTestFetchRequest stubRequest:request bitrate:UINT64_MAX resumable:YES];
            [stubbedRequestURLs addObject:request.imageURL];
            TIPImageFetchOperation *op = [initialPipeline undeprecatedFetchImageWithRequest:request context:nil delegate:nil];
            [blockOp addDependency:op];
        }

        NSOperationQueue *opQ = [[NSOperationQueue alloc] init];
        opQ.maxConcurrentOperationCount = 1;
        [opQ addOperation:blockOp];
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        while (!blockOp.isFinished) {
            [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.250]];
        }

        for (NSURL *URL in stubbedRequestURLs) {
            [provider removeDownloadStubForRequestURL:URL];
        }

    }];

    __block NSArray *concurrentComparables1 = nil;
    [self _safelyOpenPipelineWithIdentifier:identifier executingBlock:^(TIPImagePipeline *concurrentlyLoadedPipeline) {
        concurrentComparables1 = buildComparablesFromPipeline(concurrentlyLoadedPipeline);
    }];
    XCTAssertNotNil(concurrentComparables1);

    __block NSArray *concurrentComparables2 = nil;
    [self _safelyOpenPipelineWithIdentifier:identifier executingBlock:^(TIPImagePipeline *concurrentlyLoadedPipeline) {
        concurrentComparables2 = buildComparablesFromPipeline(concurrentlyLoadedPipeline);
    }];
    XCTAssertNotNil(concurrentComparables2);

    XCTAssertEqualObjects([NSSet setWithArray:concurrentComparables1], [NSSet setWithArray:concurrentComparables2]);

    TIPImagePipeline *pipeline = [[TIPImagePipeline alloc] initWithIdentifier:identifier];
    [pipeline clearDiskCache];
    [pipeline inspect:^(TIPImagePipelineInspectionResult * _Nullable result) {}];
    XCTestExpectation *expectation = [self expectationForNotification:TIPImagePipelineDidTearDownImagePipelineNotification object:nil handler:^BOOL(NSNotification *note) {
        return [identifier isEqualToString:note.userInfo[TIPImagePipelineImagePipelineIdentifierNotificationKey]];
    }];
    pipeline = nil;
    [self waitForExpectationsWithTimeout:20 handler:NULL];
    expectation = nil;
}

- (void)_safelyOpenPipelineWithIdentifier:(NSString *)identifier executingBlock:(void (^)(TIPImagePipeline *pipeline))executingBlock
{
    @autoreleasepool {
        TIPImagePipeline *pipeline = [[TIPImagePipeline alloc] initWithIdentifier:identifier];
        XCTAssertNotNil(pipeline);

        executingBlock(pipeline);

        [self expectationForNotification:TIPImagePipelineDidTearDownImagePipelineNotification object:nil handler:^BOOL(NSNotification *note) {
            return [identifier isEqualToString:note.userInfo[TIPImagePipelineImagePipelineIdentifierNotificationKey]];
        }];
        [pipeline inspect:^(TIPImagePipelineInspectionResult * _Nullable result) {}];
        pipeline = nil;
    }
    [self waitForExpectationsWithTimeout:20 handler:nil];
}

- (void)testMergingFetches
{
    TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
    request.imageType = TIPImageTypeJPEG;
    request.progressiveSource = YES;
    request.imageURL = [TIPImagePipelineBaseTests dummyURLWithPath:[NSUUID UUID].UUIDString];
    request.targetDimensions = kCarnivalImageDimensions;
    request.targetContentMode = UIViewContentModeScaleAspectFit;

    [TIPImagePipelineTestFetchRequest stubRequest:request bitrate:2 * kMegaBits resumable:YES];

    TIPImageFetchOperation *op1 = nil;
    TIPImageFetchOperation *op2 = nil;
    TIPImagePipelineTestContext *context1 = nil;
    TIPImagePipelineTestContext *context2 = nil;

    [[TIPImagePipelineBaseTests sharedPipeline] clearMemoryCaches];
    [[TIPImagePipelineBaseTests sharedPipeline] clearDiskCache];
    context1 = [[TIPImagePipelineTestContext alloc] init];
    context2 = [[TIPImagePipelineTestContext alloc] init];
    context1.otherContext = context2;
    op1 = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context1 delegate:self];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    op2 = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context2 delegate:self];
    [op1 waitUntilFinishedWithoutBlockingRunLoop];
    [op2 waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertEqual(context1.didStart, YES);
    XCTAssertNotNil(context1.finalImageContainer);
    XCTAssertNil(context1.finalError);
    XCTAssertEqual(context1.finalSource, TIPImageLoadSourceNetwork);
    XCTAssertEqualObjects(context1.finalImageContainer, op1.finalResult.imageContainer);
    XCTAssertEqual(context1.finalSource, op1.finalResult.imageSource);
    XCTAssertEqual(op1.state, TIPImageFetchOperationStateSucceeded);
    XCTAssertNotNil(context1.associatedDownloadContext);

    XCTAssertEqual(context2.didStart, YES);
    XCTAssertNotNil(context2.finalImageContainer);
    XCTAssertNil(context2.finalError);
    XCTAssertEqual(context2.finalSource, TIPImageLoadSourceNetwork);
    XCTAssertEqualObjects(context2.finalImageContainer, op2.finalResult.imageContainer);
    XCTAssertEqual(context2.finalSource, op2.finalResult.imageSource);
    XCTAssertEqual(op2.state, TIPImageFetchOperationStateSucceeded);
    XCTAssertNotNil(context2.associatedDownloadContext);

    XCTAssertEqual((__bridge void *)context1.associatedDownloadContext, (__bridge void *)context2.associatedDownloadContext);

    // Cancel original

    [[TIPImagePipelineBaseTests sharedPipeline] clearMemoryCaches];
    [[TIPImagePipelineBaseTests sharedPipeline] clearDiskCache];
    context1 = [[TIPImagePipelineTestContext alloc] init];
    context1.shouldCancelOnOtherContextFirstProgress = YES;
    context2 = [[TIPImagePipelineTestContext alloc] init];
    context1.otherContext = context2;
    op1 = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context1 delegate:self];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    op2 = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context2 delegate:self];
    [op1 waitUntilFinishedWithoutBlockingRunLoop];
    [op2 waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertEqual(context1.didStart, YES);
    XCTAssertNil(context1.finalImageContainer);
    XCTAssertNotNil(context1.finalError);
    XCTAssertEqual(op1.state, TIPImageFetchOperationStateCancelled);
    XCTAssertNotNil(context1.associatedDownloadContext);

    XCTAssertEqual(context2.didStart, YES);
    XCTAssertNotNil(context2.finalImageContainer);
    XCTAssertNil(context2.finalError);
    XCTAssertEqual(context2.finalSource, TIPImageLoadSourceNetwork);
    XCTAssertEqualObjects(context2.finalImageContainer, op2.finalResult.imageContainer);
    XCTAssertEqual(context2.finalSource, op2.finalResult.imageSource);
    XCTAssertEqual(op2.state, TIPImageFetchOperationStateSucceeded);
    XCTAssertNotNil(context2.associatedDownloadContext);

    XCTAssertEqual((__bridge void *)context1.associatedDownloadContext, (__bridge void *)context2.associatedDownloadContext);
}

- (void)testCopyingDiskEntry
{
    [[TIPImagePipelineBaseTests sharedPipeline] clearDiskCache];
    [[TIPImagePipelineBaseTests sharedPipeline] clearMemoryCaches];

    NSString *copyFinishedNotificationName = @"copy_finished";

    TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
    request.imageURL = [TIPImagePipelineBaseTests dummyURLWithPath:[NSUUID UUID].UUIDString];
    request.imageType = TIPImageTypeJPEG;
    request.progressiveSource = NO;

    __block NSString *tempFile = nil;
    __block NSError *copyError = nil;
    XCTestExpectation *finisedCopyExpectation = nil;
    TIPImagePipelineCopyFileCompletionBlock completion = ^(NSString *temporaryFilePath, NSError *error) {
        tempFile = temporaryFilePath;
        copyError = error;

        NSTimeInterval delay = (tempFile != nil) ? 0.5 : 0.1;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:copyFinishedNotificationName object:request];
        });
    };

    [TIPImagePipelineTestFetchRequest stubRequest:request bitrate:1024 * kMegaBits resumable:YES];

    // Attempt with empty caches

    tempFile = nil;
    copyError = nil;
    finisedCopyExpectation = [self expectationForNotification:copyFinishedNotificationName object:nil handler:NULL];
    [[TIPImagePipelineBaseTests sharedPipeline] copyDiskCacheFileWithIdentifier:request.imageURL.absoluteString completion:completion];
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];
    XCTAssertNil(tempFile);
    XCTAssertNotNil(copyError);

    // Fill cache with item

    TIPImageFetchOperation *op = [[TIPImagePipelineBaseTests sharedPipeline] operationWithRequest:request context:nil completion:NULL];
    [[TIPImagePipelineBaseTests sharedPipeline] fetchImageWithOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertNotNil(op.finalResult.imageContainer);

    // Attempt with cache entries

    tempFile = nil;
    copyError = nil;
    finisedCopyExpectation = [self expectationForNotification:copyFinishedNotificationName object:nil handler:NULL];
    [[TIPImagePipelineBaseTests sharedPipeline] copyDiskCacheFileWithIdentifier:request.imageURL.absoluteString completion:completion];
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];
    XCTAssertNotNil(tempFile);
    XCTAssertNil(copyError);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:tempFile]);

    // Attempt with no disk cache entry

    tempFile = nil;
    copyError = nil;
    [[TIPImagePipelineBaseTests sharedPipeline] clearDiskCache];
    finisedCopyExpectation = [self expectationForNotification:copyFinishedNotificationName object:nil handler:NULL];
    [[TIPImagePipelineBaseTests sharedPipeline] copyDiskCacheFileWithIdentifier:request.imageURL.absoluteString completion:completion];
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];
    XCTAssertNil(tempFile);
    XCTAssertNotNil(copyError);
}

- (void)testGettingKnownPipelines
{
    TestImageStoreRequest *storeRequest = [[TestImageStoreRequest alloc] init];
    storeRequest.imageFilePath = [[self class] pathForImageOfType:TIPImageTypeJPEG progressive:NO];
    XCTAssertNotNil(storeRequest.imageFilePath);

    storeRequest.imageURL = [[self class] dummyURLWithPath:@"dummy.image.jpg"];
    NSString *signalIdentifier = [NSString stringWithFormat:@"%@", @(time(NULL))];
    __block XCTestExpectation *expectation = nil;
    __block NSSet *knownIds = nil;
    __block BOOL didStore = NO;
    void (^getKnownImagePiplineIdentifiers)(void) = ^ {
        expectation = [self expectationWithDescription:@"Waiting for known image pipeline identifiers"];
        [TIPImagePipeline getKnownImagePipelineIdentifiers:^(NSSet *identifiers) {
            knownIds = [identifiers copy];
            /*NSLog(@"Known Image Pipeline Identifiers: %@", knownIds.allObjects);*/
            [expectation fulfill];
        }];
        [self waitForExpectationsWithTimeout:20.0 handler:NULL];
    };

    // 1) Assert the pipeline we are looking for doesn't exist

    getKnownImagePiplineIdentifiers();
    XCTAssertFalse([knownIds containsObject:signalIdentifier]);

    // 2) Create a pipeline and store an image, assert it does now exist

    expectation = [self expectationWithDescription:@"Storing Image"];
    TIPImagePipeline *pipeline = [[TIPImagePipeline alloc] initWithIdentifier:signalIdentifier];
    [pipeline storeImageWithRequest:storeRequest completion:^(NSObject<TIPDependencyOperation> *storeOp, BOOL succeeded, NSError *error) {
        didStore = succeeded;
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:20.0 handler:NULL];
    getKnownImagePiplineIdentifiers();
    XCTAssertTrue([knownIds containsObject:signalIdentifier]);

    // 3) Clear the pipeline and dealloc, assert it no longer exists

    [pipeline clearDiskCache];
    pipeline = nil;
    getKnownImagePiplineIdentifiers();
    XCTAssertFalse([knownIds containsObject:signalIdentifier]);
}

- (void)testCrossPipelineLoad
{
    NSString *pipelineIdentifier1 = @"cross.pipeline.1";
    NSString *pipelineIdentifier2 = @"cross.pipeline.2";
    TIPImagePipeline *pipeline1 = [[TIPImagePipeline alloc] initWithIdentifier:pipelineIdentifier1];
    TIPImagePipeline *pipeline2 = [[TIPImagePipeline alloc] initWithIdentifier:pipelineIdentifier2];
    [pipeline1 clearDiskCache];
    [pipeline2 clearDiskCache];

    __block TIPImageLoadSource loadSource;
    XCTestExpectation *expectation;
    TIPImageFetchOperation *op;
    NSURL *URL = [NSURL URLWithString:@"http://cross.pipeline.com/image.jpg"];

    NSString *imagePath = [[self class] pathForImageOfType:TIPImageTypeJPEG progressive:NO];
    XCTAssertNotNil(imagePath);

    TestImageStoreRequest *storeRequest = [[TestImageStoreRequest alloc] init];
    storeRequest.imageURL = URL;
    storeRequest.imageFilePath = imagePath;
    TIPImagePipelineTestFetchRequest *fetchRequest = [[TIPImagePipelineTestFetchRequest alloc] init];
    fetchRequest.imageURL = URL;
    fetchRequest.imageType = TIPImageTypeJPEG;
    fetchRequest.progressiveSource = NO;

    [TIPImagePipelineTestFetchRequest stubRequest:fetchRequest bitrate:0 resumable:YES];

    expectation = [self expectationWithDescription:@"Cross Pipeline Fetch Image 1"];
    op = [pipeline2 operationWithRequest:fetchRequest context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        [expectation fulfill];
    }];
    [pipeline2 fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceNetwork, loadSource);

    [pipeline2 clearDiskCache];
    [pipeline2 clearMemoryCaches];
    expectation = [self expectationWithDescription:@"Clear Caches"];
    [pipeline2 inspect:^(TIPImagePipelineInspectionResult *result) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];

    expectation = [self expectationWithDescription:@"Cross Pipeline Store Image"];
    [pipeline1 storeImageWithRequest:storeRequest completion:^(NSObject<TIPDependencyOperation> *storeOp, BOOL succeeded, NSError *error) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];

    expectation = [self expectationWithDescription:@"Cross Pipeline Fetch Image 2"];
    op = [pipeline2 operationWithRequest:fetchRequest context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        [expectation fulfill];
    }];
    [pipeline2 fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceDiskCache, loadSource);

    [pipeline1 clearDiskCache];
    [pipeline2 clearDiskCache];
    pipeline1 = nil;
    pipeline2 = nil;
}

- (void)testRenamedEntry
{
    NSString *pipelineIdentifier = @"dummy.pipeline";
    TIPImagePipeline *pipeline = [[TIPImagePipeline alloc] initWithIdentifier:pipelineIdentifier];
    [pipeline clearDiskCache];

    __block TIPImageLoadSource loadSource;
    __block NSError *loadError;
    XCTestExpectation *expectation;
    TIPImageFetchOperation *op;
    NSURL *URL1 = [NSURL URLWithString:@"http://dummy.pipeline.com/image.jpg"];
    NSURL *URL2 = [NSURL URLWithString:@"fake://fake.pipeline.com/fake.jpg"];

    TIPImagePipelineTestFetchRequest *fetchRequest1 = [[TIPImagePipelineTestFetchRequest alloc] init];
    fetchRequest1.imageURL = URL1;
    fetchRequest1.imageType = TIPImageTypeJPEG;
    fetchRequest1.progressiveSource = NO;

    TIPImagePipelineTestFetchRequest *fetchRequest2 = [[TIPImagePipelineTestFetchRequest alloc] init];
    fetchRequest2.imageURL = URL1;
    fetchRequest2.imageIdentifier = [URL2 absoluteString];
    fetchRequest2.imageType = TIPImageTypeJPEG;
    fetchRequest2.progressiveSource = NO;
    fetchRequest2.loadingSources = TIPImageFetchLoadingSourcesAll & ~(TIPImageFetchLoadingSourceNetwork | TIPImageFetchLoadingSourceNetworkResumed); // no network!

    [TIPImagePipelineTestFetchRequest stubRequest:fetchRequest1 bitrate:0 resumable:YES];
    [TIPImagePipelineTestFetchRequest stubRequest:fetchRequest2 bitrate:0 resumable:NO]; // just to ensure we don't hit the network

    expectation = [self expectationWithDescription:@"Pipeline Fetch Image 1"];
    op = [pipeline operationWithRequest:fetchRequest1 context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        loadError = error;
        [expectation fulfill];
    }];
    [pipeline fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceNetwork, loadSource);
    XCTAssertNil(loadError);

    expectation = [self expectationWithDescription:@"Pipeline Fetch Image 2"];
    op = [pipeline operationWithRequest:fetchRequest2 context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        loadError = error;
        [expectation fulfill];
    }];
    [pipeline fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceUnknown, loadSource);
    XCTAssertNotNil(loadError);

    expectation = [self expectationWithDescription:@"Move Image"];
    [pipeline changeIdentifierForImageWithIdentifier:[URL1 absoluteString] toIdentifier:[URL2 absoluteString] completion:^(NSObject<TIPDependencyOperation> *moveOp, BOOL succeeded, NSError *error) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];

    expectation = [self expectationWithDescription:@"Pipeline Fetch Image 2"];
    op = [pipeline operationWithRequest:fetchRequest2 context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        loadError = error;
        [expectation fulfill];
    }];
    [pipeline fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceDiskCache, loadSource);
    XCTAssertNil(loadError);

    expectation = [self expectationWithDescription:@"Pipeline Fetch Image 1"];
    op = [pipeline operationWithRequest:fetchRequest1 context:nil completion:^(id<TIPImageFetchResult> result, NSError *error) {
        loadSource = result.imageSource;
        loadError = error;
        [expectation fulfill];
    }];
    [pipeline fetchImageWithOperation:op];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    XCTAssertEqual(TIPImageLoadSourceNetwork, loadSource); // Not cache!
    XCTAssertNil(loadError);

    [pipeline clearDiskCache];
    [pipeline clearMemoryCaches];
    expectation = [self expectationWithDescription:@"Clear Caches"];
    [pipeline inspect:^(TIPImagePipelineInspectionResult *result) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10.0 handler:NULL];
    pipeline = nil;
}

- (void)testInvalidPseudoFilePathFetch
{
    TIPImagePipelineTestFetchRequest *request = [[TIPImagePipelineTestFetchRequest alloc] init];
    request.imageType = TIPImageTypeJPEG;
    request.progressiveSource = YES;
    request.imageURL = [TIPImagePipelineBaseTests dummyURLWithPath:[NSUUID UUID].UUIDString];
    request.targetDimensions = kCarnivalImageDimensions;
    request.targetContentMode = UIViewContentModeScaleAspectFit;
    request.cannedImageFilePath = [request.cannedImageFilePath stringByAppendingPathExtension:@"dne"];

    [TIPImagePipelineTestFetchRequest stubRequest:request bitrate:1 * kMegaBits resumable:YES];

    TIPImageFetchOperation *op = nil;
    TIPImagePipelineTestContext *context = nil;

    [[TIPImagePipelineBaseTests sharedPipeline] clearMemoryCaches];
    [[TIPImagePipelineBaseTests sharedPipeline] clearDiskCache];
    context = [[TIPImagePipelineTestContext alloc] init];
    op = [[TIPImagePipelineBaseTests sharedPipeline] undeprecatedFetchImageWithRequest:request context:context delegate:self];
    [op waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertNil(op.finalResult.imageContainer);
    XCTAssertNotNil(op.error);

    TIPImageFetchMetricInfo *metricInfo = [op.metrics metricInfoForSource:TIPImageLoadSourceNetwork];
    (void)metricInfo;
}

@end

@implementation TIPImagePipelineTests_Two

- (void)testFillingMultipleCaches
{
    TIPGlobalConfiguration *config = [TIPGlobalConfiguration sharedInstance];

    __block SInt64 preDeallocDiskSize;
    __block SInt64 preDeallocMemSize;
    __block SInt64 preDeallocRendSize;

    __block SInt64 preDeallocPipelineDiskSize;
    __block SInt64 preDeallocPipelineMemSize;
    __block SInt64 preDeallocPipelineRendSize;

    NSString *tmpPipelineIdentifier = @"temp.pipeline.identifier";
    XCTestExpectation *expectation = [self expectationForNotification:TIPImagePipelineDidTearDownImagePipelineNotification object:nil handler:^BOOL(NSNotification *note) {
        return [tmpPipelineIdentifier isEqualToString:note.userInfo[TIPImagePipelineImagePipelineIdentifierNotificationKey]];
    }];

    @autoreleasepool {
        [[TIPImagePipelineBaseTests sharedPipeline] clearMemoryCaches];
        [[TIPImagePipelineBaseTests sharedPipeline] clearDiskCache];
        TIPImagePipeline *temporaryPipeline = [[TIPImagePipeline alloc] initWithIdentifier:tmpPipelineIdentifier];

        [self runFillingTheCaches:[TIPImagePipelineBaseTests sharedPipeline] bps:1024 * kMegaBits testCacheHits:NO];

        TIPGlobalConfiguration *globalConfig = [TIPGlobalConfiguration sharedInstance];

        XCTAssertGreaterThan([[TIPImagePipelineBaseTests sharedPipeline] cacheOfType:TIPImageCacheTypeRendered].manifest.numberOfEntries, (NSUInteger)0);
        dispatch_sync(globalConfig.queueForMemoryCaches, ^{
            XCTAssertGreaterThan([[TIPImagePipelineBaseTests sharedPipeline] cacheOfType:TIPImageCacheTypeMemory].manifest.numberOfEntries, (NSUInteger)0);
        });
        dispatch_sync(globalConfig.queueForDiskCaches, ^{
            XCTAssertGreaterThan([[TIPImagePipelineBaseTests sharedPipeline] cacheOfType:TIPImageCacheTypeDisk].manifest.numberOfEntries, (NSUInteger)0);
        });

        [self runFillingTheCaches:temporaryPipeline bps:1024 * kMegaBits testCacheHits:NO];
        XCTAssertGreaterThan([temporaryPipeline cacheOfType:TIPImageCacheTypeRendered].manifest.numberOfEntries, (NSUInteger)0);
        XCTAssertEqual([[TIPImagePipelineBaseTests sharedPipeline] cacheOfType:TIPImageCacheTypeRendered].manifest.numberOfEntries, (NSUInteger)0);
        dispatch_sync(globalConfig.queueForMemoryCaches, ^{
            XCTAssertGreaterThan([temporaryPipeline cacheOfType:TIPImageCacheTypeMemory].manifest.numberOfEntries, (NSUInteger)0);
            XCTAssertEqual([[TIPImagePipelineBaseTests sharedPipeline] cacheOfType:TIPImageCacheTypeMemory].manifest.numberOfEntries, (NSUInteger)0);
        });
        dispatch_sync(globalConfig.queueForMemoryCaches, ^{
            XCTAssertGreaterThan([temporaryPipeline cacheOfType:TIPImageCacheTypeDisk].manifest.numberOfEntries, (NSUInteger)0);
            XCTAssertEqual([[TIPImagePipelineBaseTests sharedPipeline] cacheOfType:TIPImageCacheTypeDisk].manifest.numberOfEntries, (NSUInteger)0);
        });

        dispatch_sync(globalConfig.queueForDiskCaches, ^{
            preDeallocDiskSize = [config internalTotalBytesForAllCachesOfType:TIPImageCacheTypeDisk];
        });
        dispatch_sync(globalConfig.queueForMemoryCaches, ^{
            preDeallocMemSize = [config internalTotalBytesForAllCachesOfType:TIPImageCacheTypeMemory];
        });
        preDeallocRendSize = [config internalTotalBytesForAllCachesOfType:TIPImageCacheTypeRendered];

        preDeallocPipelineDiskSize = (SInt64)[temporaryPipeline cacheOfType:TIPImageCacheTypeDisk].totalCost;
        preDeallocPipelineMemSize = (SInt64)[temporaryPipeline cacheOfType:TIPImageCacheTypeMemory].totalCost;
        preDeallocPipelineRendSize = (SInt64)[temporaryPipeline cacheOfType:TIPImageCacheTypeRendered].totalCost;

        temporaryPipeline = nil;
    }

    NSLog(@"Waiting for %@", TIPImagePipelineDidTearDownImagePipelineNotification);

    // Wait for the pipeline to release
    [self waitForExpectationsWithTimeout:120.0 handler:^(NSError *error) {
        if (error) {
            NSLog(@"%@", error);
        } else {
            NSLog(@"Received %@", TIPImagePipelineDidTearDownImagePipelineNotification);
        }
    }];
    expectation = nil;

    __block SInt64 postDeallocDiskSize;
    __block SInt64 postDeallocMemSize;
    __block SInt64 postDeallocRendSize;

    const NSUInteger cacheSizeCheckMax = 30;
    NSUInteger cacheSizeCheck;
    for (cacheSizeCheck = 1; cacheSizeCheck <= cacheSizeCheckMax; cacheSizeCheck++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

        dispatch_sync([TIPGlobalConfiguration sharedInstance].queueForDiskCaches, ^{
            postDeallocDiskSize = [config internalTotalBytesForAllCachesOfType:TIPImageCacheTypeDisk];
        });
        dispatch_sync([TIPGlobalConfiguration sharedInstance].queueForMemoryCaches, ^{
            postDeallocMemSize = [config internalTotalBytesForAllCachesOfType:TIPImageCacheTypeMemory];
        });
        postDeallocRendSize = [config internalTotalBytesForAllCachesOfType:TIPImageCacheTypeRendered];

        if (postDeallocDiskSize == 0 && postDeallocMemSize == 0 && postDeallocRendSize == 0) {
            break;
        }
    }

    if (cacheSizeCheck <= cacheSizeCheckMax) {
        NSLog(@"Caches were relieved after %tu seconds", cacheSizeCheck);
    } else {
        NSLog(@"ERR: Caches were not relieved after %tu seconds", cacheSizeCheck - 1);
    }

    XCTAssertEqual(postDeallocDiskSize, preDeallocDiskSize - preDeallocPipelineDiskSize);
    XCTAssertEqual(postDeallocMemSize, preDeallocMemSize - preDeallocPipelineMemSize);
    XCTAssertEqual(postDeallocRendSize, preDeallocRendSize - preDeallocPipelineRendSize);
}

@end

@implementation TIPImagePipelineTests_Three

- (void)testFillingTheCaches
{
    TIPImagePipeline *pipeline = [TIPImagePipelineBaseTests sharedPipeline];
    [self runFillingTheCaches:pipeline bps:1024 * kMegaBits testCacheHits:YES];
    [self checkFileAttributes:pipeline];
}

@end

