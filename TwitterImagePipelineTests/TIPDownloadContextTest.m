//
//  TIPDownloadContextTest.m
//  TwitterImagePipeline
//
//  Created on 10/14/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "TIPGlobalConfiguration.h"
#import "TIPImageDownloadInternalContext.h"

#import "TIPTests.h"

@interface TestTIPImageDownloadInternalContext : TIPImageDownloadInternalContext
@property (nonatomic) int64_t latestBytesPerSecond;
@end

@interface TestTIPPartialImage : TIPPartialImage
@end

@interface TIPDownloadContextTest : XCTestCase
@end

@implementation TIPDownloadContextTest

- (void)tearDown
{
    [TIPGlobalConfiguration sharedInstance].maxEstimatedTimeRemainingForDetachedHTTPDownloads = TIPMaxEstimatedTimeRemainingForDetachedHTTPDownloadsDefault;
    [TIPGlobalConfiguration sharedInstance].estimatedBitrateProviderBlock = NULL;
    [super tearDown];
}

+ (NSDictionary *)contextInfoWithStatusCode:(NSInteger)statusCode maxTime:(NSTimeInterval)maxTime contentLength:(NSUInteger)contentLength supportsCancel:(BOOL)supportsCancel bytesPerSecond:(int64_t)bps externalBpsBlockWasUsed:(BOOL)useExternalBps byteCount:(NSUInteger)byteCount
{
    return @{
             @"maxTime" : @(maxTime),
             @"statusCode" : @(statusCode),
             @"contentLength" : @(contentLength),
             @"supportsCancel" : @(supportsCancel),
             @"Bps" : @(bps),
             @"BpsBlock" : @(useExternalBps),
             @"byteCount" : @(byteCount),
             };
}

- (void)testDownloadContext
{
    TIPGlobalConfiguration *config = [TIPGlobalConfiguration sharedInstance];
    TestTIPImageDownloadInternalContext *context = [[TestTIPImageDownloadInternalContext alloc] init];

    config.maxEstimatedTimeRemainingForDetachedHTTPDownloads = 0;
    config.estimatedBitrateProviderBlock = NULL;

#define KILOBYTES(x) ((x) * 1024)
#define ARRAY_SIZE(x) (sizeof(x) / sizeof(x[0]))

    static const NSInteger sCodes[] = { 0, 200, 206, 404 };
    static const NSUInteger sContentLengths[] = { 0, 63000, 128000 };
    static const BOOL sProtocolSupportsCancelValues[] = { YES, NO };
    static const int64_t sBytesPerSecondValues[] = { 0, 200, 2000, 20000, 200000 };
    static const NSTimeInterval sMaxTimes[] = { -1.0, 0.0, 0.1, 1.0, 3.0, 10.0 };
    static const BOOL sUseExternalBytesPerSecondBlockValues[] = { NO, YES };
    static const NSUInteger sBytesReadValues[] = {
        0,
        KILOBYTES(3),
        KILOBYTES(8),
        KILOBYTES(32),
        61500,
        62000,
        63000,
        64000,
        65500,
        126500,
        127000,
        128000,
        129000,
        130500,
        KILOBYTES(256)
    };
    NSData * const largeImageData = [NSData dataWithContentsOfFile: [TIPTestsResourceBundle() pathForResource:@"carnival" ofType:@"png"]];

    NSMutableSet *canDetachContextInfos = [NSMutableSet set];
#define ADD_SUCCESS(length, bps, time, bytes) \
    for (size_t codeI = 0; codeI < ARRAY_SIZE(sCodes); codeI++) { \
        NSInteger code = sCodes[codeI]; \
        for (NSUInteger useExternalBpsBlock = 0; useExternalBpsBlock <= 1; useExternalBpsBlock++) { \
            [canDetachContextInfos addObject:[[self class] contextInfoWithStatusCode:code \
                                                                             maxTime:(time) \
                                                                       contentLength:(NSUInteger)(length) \
                                                                      supportsCancel:NO \
                                                                      bytesPerSecond:(int64_t)(bps) \
                                                             externalBpsBlockWasUsed:(BOOL)useExternalBpsBlock \
                                                                           byteCount:(NSUInteger)(bytes)]]; \
        } \
    }

    // 63000 - 0.1

    ADD_SUCCESS(63000,  0,      0.1,    62000);
    ADD_SUCCESS(63000,  0,      0.1,    63000);
    ADD_SUCCESS(63000,  0,      0.1,    64000);
    ADD_SUCCESS(63000,  200,    0.1,    62000);
    ADD_SUCCESS(63000,  200,    0.1,    63000);
    ADD_SUCCESS(63000,  200,    0.1,    64000);
    ADD_SUCCESS(63000,  2000,   0.1,    62000);
    ADD_SUCCESS(63000,  2000,   0.1,    63000);
    ADD_SUCCESS(63000,  2000,   0.1,    64000);
    ADD_SUCCESS(63000,  20000,  0.1,    61500);
    ADD_SUCCESS(63000,  20000,  0.1,    62000);
    ADD_SUCCESS(63000,  20000,  0.1,    63000);
    ADD_SUCCESS(63000,  20000,  0.1,    64000);
    ADD_SUCCESS(63000,  200000, 0.1,    61500);
    ADD_SUCCESS(63000,  200000, 0.1,    62000);
    ADD_SUCCESS(63000,  200000, 0.1,    63000);
    ADD_SUCCESS(63000,  200000, 0.1,    64000);
    ADD_SUCCESS(63000,  200000, 0.1,    65500);

    // 63000 - 1.0

    ADD_SUCCESS(63000,  0,      1.0,    62000);
    ADD_SUCCESS(63000,  0,      1.0,    63000);
    ADD_SUCCESS(63000,  0,      1.0,    64000);
    ADD_SUCCESS(63000,  200,    1.0,    62000);
    ADD_SUCCESS(63000,  200,    1.0,    63000);
    ADD_SUCCESS(63000,  200,    1.0,    64000);
    ADD_SUCCESS(63000,  2000,   1.0,    61500);
    ADD_SUCCESS(63000,  2000,   1.0,    62000);
    ADD_SUCCESS(63000,  2000,   1.0,    63000);
    ADD_SUCCESS(63000,  2000,   1.0,    64000);
    ADD_SUCCESS(63000,  20000,  1.0,    61500);
    ADD_SUCCESS(63000,  20000,  1.0,    62000);
    ADD_SUCCESS(63000,  20000,  1.0,    63000);
    ADD_SUCCESS(63000,  20000,  1.0,    64000);
    ADD_SUCCESS(63000,  20000,  1.0,    65500);
    ADD_SUCCESS(63000,  200000, 1.0,    61500);
    ADD_SUCCESS(63000,  200000, 1.0,    62000);
    ADD_SUCCESS(63000,  200000, 1.0,    63000);
    ADD_SUCCESS(63000,  200000, 1.0,    64000);
    ADD_SUCCESS(63000,  200000, 1.0,    65500);
    ADD_SUCCESS(63000,  200000, 1.0,    0);
    ADD_SUCCESS(63000,  200000, 1.0,    KILOBYTES(3));
    ADD_SUCCESS(63000,  200000, 1.0,    KILOBYTES(8));
    ADD_SUCCESS(63000,  200000, 1.0,    KILOBYTES(32));

    // 63000 - 3.0

    ADD_SUCCESS(63000,  0,      3.0,    62000);
    ADD_SUCCESS(63000,  0,      3.0,    63000);
    ADD_SUCCESS(63000,  0,      3.0,    64000);
    ADD_SUCCESS(63000,  200,    3.0,    62000);
    ADD_SUCCESS(63000,  200,    3.0,    63000);
    ADD_SUCCESS(63000,  200,    3.0,    64000);
    ADD_SUCCESS(63000,  2000,   3.0,    61500);
    ADD_SUCCESS(63000,  2000,   3.0,    62000);
    ADD_SUCCESS(63000,  2000,   3.0,    63000);
    ADD_SUCCESS(63000,  2000,   3.0,    64000);
    ADD_SUCCESS(63000,  2000,   3.0,    65500);
    ADD_SUCCESS(63000,  20000,  3.0,    61500);
    ADD_SUCCESS(63000,  20000,  3.0,    62000);
    ADD_SUCCESS(63000,  20000,  3.0,    63000);
    ADD_SUCCESS(63000,  20000,  3.0,    64000);
    ADD_SUCCESS(63000,  20000,  3.0,    65500);
    ADD_SUCCESS(63000,  20000,  3.0,    KILOBYTES(3));
    ADD_SUCCESS(63000,  20000,  3.0,    KILOBYTES(8));
    ADD_SUCCESS(63000,  20000,  3.0,    KILOBYTES(32));
    ADD_SUCCESS(63000,  200000, 3.0,    61500);
    ADD_SUCCESS(63000,  200000, 3.0,    62000);
    ADD_SUCCESS(63000,  200000, 3.0,    63000);
    ADD_SUCCESS(63000,  200000, 3.0,    64000);
    ADD_SUCCESS(63000,  200000, 3.0,    65500);
    ADD_SUCCESS(63000,  200000, 3.0,    0);
    ADD_SUCCESS(63000,  200000, 3.0,    KILOBYTES(3));
    ADD_SUCCESS(63000,  200000, 3.0,    KILOBYTES(8));
    ADD_SUCCESS(63000,  200000, 3.0,    KILOBYTES(32));

    // 63000 - 10.0

    ADD_SUCCESS(63000,  0,      10.0,   62000);
    ADD_SUCCESS(63000,  0,      10.0,   63000);
    ADD_SUCCESS(63000,  0,      10.0,   64000);
    ADD_SUCCESS(63000,  200,    10.0,   61500);
    ADD_SUCCESS(63000,  200,    10.0,   62000);
    ADD_SUCCESS(63000,  200,    10.0,   63000);
    ADD_SUCCESS(63000,  200,    10.0,   64000);
    ADD_SUCCESS(63000,  2000,   10.0,   61500);
    ADD_SUCCESS(63000,  2000,   10.0,   62000);
    ADD_SUCCESS(63000,  2000,   10.0,   63000);
    ADD_SUCCESS(63000,  2000,   10.0,   64000);
    ADD_SUCCESS(63000,  2000,   10.0,   65500);
    ADD_SUCCESS(63000,  20000,  10.0,   61500);
    ADD_SUCCESS(63000,  20000,  10.0,   62000);
    ADD_SUCCESS(63000,  20000,  10.0,   63000);
    ADD_SUCCESS(63000,  20000,  10.0,   64000);
    ADD_SUCCESS(63000,  20000,  10.0,   65500);
    ADD_SUCCESS(63000,  20000,  10.0,   0);
    ADD_SUCCESS(63000,  20000,  10.0,   KILOBYTES(3));
    ADD_SUCCESS(63000,  20000,  10.0,   KILOBYTES(8));
    ADD_SUCCESS(63000,  20000,  10.0,   KILOBYTES(32));
    ADD_SUCCESS(63000,  200000, 10.0,   61500);
    ADD_SUCCESS(63000,  200000, 10.0,   62000);
    ADD_SUCCESS(63000,  200000, 10.0,   63000);
    ADD_SUCCESS(63000,  200000, 10.0,   64000);
    ADD_SUCCESS(63000,  200000, 10.0,   65500);
    ADD_SUCCESS(63000,  200000, 10.0,   0);
    ADD_SUCCESS(63000,  200000, 10.0,   KILOBYTES(3));
    ADD_SUCCESS(63000,  200000, 10.0,   KILOBYTES(8));
    ADD_SUCCESS(63000,  200000, 10.0,   KILOBYTES(32));

    // 128000 - 0.1

    ADD_SUCCESS(128000, 0,      0.1,    127000);
    ADD_SUCCESS(128000, 0,      0.1,    128000);
    ADD_SUCCESS(128000, 0,      0.1,    129000);
    ADD_SUCCESS(128000, 200,    0.1,    127000);
    ADD_SUCCESS(128000, 200,    0.1,    128000);
    ADD_SUCCESS(128000, 200,    0.1,    129000);
    ADD_SUCCESS(128000, 2000,   0.1,    127000);
    ADD_SUCCESS(128000, 2000,   0.1,    128000);
    ADD_SUCCESS(128000, 2000,   0.1,    129000);
    ADD_SUCCESS(128000, 20000,  0.1,    126500);
    ADD_SUCCESS(128000, 20000,  0.1,    127000);
    ADD_SUCCESS(128000, 20000,  0.1,    128000);
    ADD_SUCCESS(128000, 20000,  0.1,    129000);
    ADD_SUCCESS(128000, 200000, 0.1,    126500);
    ADD_SUCCESS(128000, 200000, 0.1,    127000);
    ADD_SUCCESS(128000, 200000, 0.1,    128000);
    ADD_SUCCESS(128000, 200000, 0.1,    129000);
    ADD_SUCCESS(128000, 200000, 0.1,    130500);

    // 128000 - 1.0

    ADD_SUCCESS(128000, 0,      1.0,    127000);
    ADD_SUCCESS(128000, 0,      1.0,    128000);
    ADD_SUCCESS(128000, 0,      1.0,    129000);
    ADD_SUCCESS(128000, 200,    1.0,    127000);
    ADD_SUCCESS(128000, 200,    1.0,    128000);
    ADD_SUCCESS(128000, 200,    1.0,    129000);
    ADD_SUCCESS(128000, 2000,   1.0,    126500);
    ADD_SUCCESS(128000, 2000,   1.0,    127000);
    ADD_SUCCESS(128000, 2000,   1.0,    128000);
    ADD_SUCCESS(128000, 2000,   1.0,    129000);
    ADD_SUCCESS(128000, 20000,  1.0,    126500);
    ADD_SUCCESS(128000, 20000,  1.0,    127000);
    ADD_SUCCESS(128000, 20000,  1.0,    128000);
    ADD_SUCCESS(128000, 20000,  1.0,    129000);
    ADD_SUCCESS(128000, 20000,  1.0,    130500);
    ADD_SUCCESS(128000, 200000, 1.0,    126500);
    ADD_SUCCESS(128000, 200000, 1.0,    127000);
    ADD_SUCCESS(128000, 200000, 1.0,    128000);
    ADD_SUCCESS(128000, 200000, 1.0,    129000);
    ADD_SUCCESS(128000, 200000, 1.0,    130500);
    ADD_SUCCESS(128000, 200000, 1.0,    0);
    ADD_SUCCESS(128000, 200000, 1.0,    KILOBYTES(3));
    ADD_SUCCESS(128000, 200000, 1.0,    KILOBYTES(8));
    ADD_SUCCESS(128000, 200000, 1.0,    KILOBYTES(32));
    ADD_SUCCESS(128000, 200000, 1.0,    61500);
    ADD_SUCCESS(128000, 200000, 1.0,    62000);
    ADD_SUCCESS(128000, 200000, 1.0,    63000);
    ADD_SUCCESS(128000, 200000, 1.0,    64000);
    ADD_SUCCESS(128000, 200000, 1.0,    65500);

    // 128000 - 3.0

    ADD_SUCCESS(128000, 0,      3.0,    127000);
    ADD_SUCCESS(128000, 0,      3.0,    128000);
    ADD_SUCCESS(128000, 0,      3.0,    129000);
    ADD_SUCCESS(128000, 200,    3.0,    127000);
    ADD_SUCCESS(128000, 200,    3.0,    128000);
    ADD_SUCCESS(128000, 200,    3.0,    129000);
    ADD_SUCCESS(128000, 2000,   3.0,    126500);
    ADD_SUCCESS(128000, 2000,   3.0,    127000);
    ADD_SUCCESS(128000, 2000,   3.0,    128000);
    ADD_SUCCESS(128000, 2000,   3.0,    129000);
    ADD_SUCCESS(128000, 2000,   3.0,    130500);
    ADD_SUCCESS(128000, 20000,  3.0,    126500);
    ADD_SUCCESS(128000, 20000,  3.0,    127000);
    ADD_SUCCESS(128000, 20000,  3.0,    128000);
    ADD_SUCCESS(128000, 20000,  3.0,    129000);
    ADD_SUCCESS(128000, 20000,  3.0,    130500);
    ADD_SUCCESS(128000, 200000, 3.0,    126500);
    ADD_SUCCESS(128000, 200000, 3.0,    127000);
    ADD_SUCCESS(128000, 200000, 3.0,    128000);
    ADD_SUCCESS(128000, 200000, 3.0,    129000);
    ADD_SUCCESS(128000, 200000, 3.0,    130500);
    ADD_SUCCESS(128000, 200000, 3.0,    0);
    ADD_SUCCESS(128000, 200000, 3.0,    KILOBYTES(3));
    ADD_SUCCESS(128000, 200000, 3.0,    KILOBYTES(8));
    ADD_SUCCESS(128000, 200000, 3.0,    KILOBYTES(32));
    ADD_SUCCESS(128000, 200000, 3.0,    61500);
    ADD_SUCCESS(128000, 200000, 3.0,    62000);
    ADD_SUCCESS(128000, 200000, 3.0,    63000);
    ADD_SUCCESS(128000, 200000, 3.0,    64000);
    ADD_SUCCESS(128000, 200000, 3.0,    65500);

    // 128000 - 10.0

    ADD_SUCCESS(128000, 0,      10.0,   127000);
    ADD_SUCCESS(128000, 0,      10.0,   128000);
    ADD_SUCCESS(128000, 0,      10.0,   129000);
    ADD_SUCCESS(128000, 200,    10.0,   126500);
    ADD_SUCCESS(128000, 200,    10.0,   127000);
    ADD_SUCCESS(128000, 200,    10.0,   128000);
    ADD_SUCCESS(128000, 200,    10.0,   129000);
    ADD_SUCCESS(128000, 2000,   10.0,   126500);
    ADD_SUCCESS(128000, 2000,   10.0,   127000);
    ADD_SUCCESS(128000, 2000,   10.0,   128000);
    ADD_SUCCESS(128000, 2000,   10.0,   129000);
    ADD_SUCCESS(128000, 2000,   10.0,   130500);
    ADD_SUCCESS(128000, 20000,  10.0,   126500);
    ADD_SUCCESS(128000, 20000,  10.0,   127000);
    ADD_SUCCESS(128000, 20000,  10.0,   128000);
    ADD_SUCCESS(128000, 20000,  10.0,   129000);
    ADD_SUCCESS(128000, 20000,  10.0,   130500);
    ADD_SUCCESS(128000, 20000,  10.0,   0);
    ADD_SUCCESS(128000, 20000,  10.0,   KILOBYTES(3));
    ADD_SUCCESS(128000, 20000,  10.0,   KILOBYTES(8));
    ADD_SUCCESS(128000, 20000,  10.0,   KILOBYTES(32));
    ADD_SUCCESS(128000, 20000,  10.0,   61500);
    ADD_SUCCESS(128000, 20000,  10.0,   62000);
    ADD_SUCCESS(128000, 20000,  10.0,   63000);
    ADD_SUCCESS(128000, 20000,  10.0,   64000);
    ADD_SUCCESS(128000, 20000,  10.0,   65500);
    ADD_SUCCESS(128000, 200000, 10.0,   126500);
    ADD_SUCCESS(128000, 200000, 10.0,   127000);
    ADD_SUCCESS(128000, 200000, 10.0,   128000);
    ADD_SUCCESS(128000, 200000, 10.0,   129000);
    ADD_SUCCESS(128000, 200000, 10.0,   130500);
    ADD_SUCCESS(128000, 200000, 10.0,   0);
    ADD_SUCCESS(128000, 200000, 10.0,   KILOBYTES(3));
    ADD_SUCCESS(128000, 200000, 10.0,   KILOBYTES(8));
    ADD_SUCCESS(128000, 200000, 10.0,   KILOBYTES(32));
    ADD_SUCCESS(128000, 200000, 10.0,   61500);
    ADD_SUCCESS(128000, 200000, 10.0,   62000);
    ADD_SUCCESS(128000, 200000, 10.0,   63000);
    ADD_SUCCESS(128000, 200000, 10.0,   64000);
    ADD_SUCCESS(128000, 200000, 10.0,   65500);

    // 0 - 10.0

    for (NSUInteger extenalBlock = 0; extenalBlock <= 1; extenalBlock++) {
        for (size_t bytesI = 0; bytesI < ARRAY_SIZE(sBytesReadValues); bytesI++) {
            NSUInteger bytes = sBytesReadValues[bytesI];
            [canDetachContextInfos addObject:[[self class] contextInfoWithStatusCode:0
                                                                             maxTime:10.0
                                                                       contentLength:0
                                                                      supportsCancel:NO
                                                                      bytesPerSecond:200000
                                                             externalBpsBlockWasUsed:(BOOL)extenalBlock
                                                                           byteCount:bytes]];
        }
    }

    for (size_t useExternalBpsI = 0; useExternalBpsI < ARRAY_SIZE(sUseExternalBytesPerSecondBlockValues); useExternalBpsI++) {
        const BOOL useExternalBps = sUseExternalBytesPerSecondBlockValues[useExternalBpsI];
        for (size_t maxTimeI = 0; maxTimeI < ARRAY_SIZE(sMaxTimes); maxTimeI++) {
            config.maxEstimatedTimeRemainingForDetachedHTTPDownloads = sMaxTimes[maxTimeI];
            for (size_t codeI = 0; codeI < ARRAY_SIZE(sCodes); codeI++) {
                context.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://www.dummy.com/image"] statusCode:sCodes[codeI] HTTPVersion:@"HTTP/1.1"  headerFields:nil];
                for (size_t contentLengthI = 0; contentLengthI < ARRAY_SIZE(sContentLengths); contentLengthI++) {
                    context.contentLength = sContentLengths[contentLengthI];
                    for (size_t supportsCancelI = 0; supportsCancelI < ARRAY_SIZE(sProtocolSupportsCancelValues); supportsCancelI++) {
                        context.doesProtocolSupportCancel = sProtocolSupportsCancelValues[supportsCancelI];
                        for (size_t bpsI = 0; bpsI < ARRAY_SIZE(sBytesPerSecondValues); bpsI++) {
                            int64_t bps = sBytesPerSecondValues[bpsI];
                            if (useExternalBps) {
                                context.latestBytesPerSecond = 0;
                                config.estimatedBitrateProviderBlock = ^int64_t(NSString *domain) {
                                    return bps * 8;
                                };
                            } else {
                                context.latestBytesPerSecond = bps;
                                config.estimatedBitrateProviderBlock = NULL;
                            }
                            for (size_t bytesReadI = 0; bytesReadI < ARRAY_SIZE(sBytesReadValues); bytesReadI++) {
                                @autoreleasepool {
                                    NSData *data = [largeImageData subdataWithRange:NSMakeRange(0, sBytesReadValues[bytesReadI])];
                                    context.partialImage = [[TestTIPPartialImage alloc] initWithExpectedContentLength:context.contentLength];
                                    [context.partialImage appendData:data final:NO];

                                    NSDictionary *contextInfo = [[self class] contextInfoWithStatusCode:context.response.statusCode
                                                                                                maxTime:config.maxEstimatedTimeRemainingForDetachedHTTPDownloads
                                                                                          contentLength:context.contentLength
                                                                                         supportsCancel:context.doesProtocolSupportCancel
                                                                                         bytesPerSecond:bps
                                                                                externalBpsBlockWasUsed:useExternalBps
                                                                                              byteCount:context.partialImage.byteCount];

                                    BOOL canDetachExpected = [canDetachContextInfos containsObject:contextInfo];
                                    BOOL canDetachActual = [context canContinueAsDetachedDownload];
                                    XCTAssertEqual(canDetachExpected, canDetachActual, @"Failed with context: %@", contextInfo);
                                    if (canDetachExpected != canDetachActual) {
                                        NSLog(@"Ending test run early as a failure was encountered");
                                        return;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@end

@implementation TestTIPImageDownloadInternalContext
@end

@implementation TestTIPPartialImage
{
    NSUInteger _byteCount;
}

- (NSUInteger)byteCount
{
    return _byteCount;
}

- (TIPImageDecoderAppendResult)appendData:(NSData *)data final:(BOOL)final
{
    _byteCount += data.length;
    return TIPImageDecoderAppendResultDidProgress;
}

@end
