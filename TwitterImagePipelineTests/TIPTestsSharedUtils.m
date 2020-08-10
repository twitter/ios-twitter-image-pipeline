//
//  TIPTestsSharedUtils.m
//  TwitterImagePipeline
//
//  Created on 8/30/18.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPImageDiskCache.h"
#import "TIPImageFetchOperation+Project.h"
#import "TIPImageMemoryCache.h"
#import "TIPImagePipeline+Project.h"
#import "TIPImageRenderedCache.h"
#import "TIPTestImageFetchDownloadInternalWithStubbing.h"
#import "TIPTests.h"
#import "TIPTestsSharedUtils.h"

@import MobileCoreServices;

@implementation TIPImagePipelineTestFetchRequest

- (instancetype)init
{
    self = [super init];
    if (self) {
        _options = TIPImageFetchNoOptions;
        _targetContentMode = UIViewContentModeCenter;
        _targetDimensions = CGSizeZero;
        _loadingSources = TIPImageFetchLoadingSourcesAll;
    }
    return self;
}

- (NSString *)cannedImageFilePath
{
    return _cannedImageFilePath ?: [TIPImagePipelineBaseTests pathForImageOfType:self.imageType progressive:self.progressiveSource];
}

- (NSDictionary *)progressiveLoadingPolicies
{
    NSMutableDictionary *policies = [NSMutableDictionary dictionaryWithCapacity:2];
    if (self.jp2ProgressiveLoadingPolicy) {
        policies[TIPImageTypeJPEG2000] = self.jp2ProgressiveLoadingPolicy;
    }
    if (self.jpegProgressiveLoadingPolicy) {
        policies[TIPImageTypeJPEG] = self.jpegProgressiveLoadingPolicy;
    }
    return policies;
}

+ (void)stubRequest:(TIPImagePipelineTestFetchRequest *)request
            bitrate:(uint64_t)bitrate
          resumable:(BOOL)resumable
{
    NSData *data = [NSData dataWithContentsOfFile:request.cannedImageFilePath options:NSDataReadingMappedIfSafe error:NULL];
    NSString *MIMEType = (NSString *)CFBridgingRelease(UTTypeIsDeclared((__bridge CFStringRef)request.imageType) ? UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)request.imageType, kUTTagClassMIMEType) : nil);
    id<TIPImageFetchDownloadProviderWithStubbingSupport> provider = (id<TIPImageFetchDownloadProviderWithStubbingSupport>)[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider;
    [provider addDownloadStubForRequestURL:request.imageURL
                              responseData:data
                          responseMIMEType:MIMEType
                     shouldSupportResuming:resumable
                          suggestedBitrate:bitrate];
}

@end

@implementation TIPImagePipelineTestContext

- (instancetype)init
{
    if (self = [super init]) {
        _cancelPoint = 2.0f;
    }
    return self;
}

- (NSUInteger)expectedFrameCount
{
    if (_expectedFrameCount) {
        return _expectedFrameCount;
    }

    return self.shouldSupportAnimatedLoading ? kFireworksFrameCount : 1;
}

@end

@implementation TIPImagePipeline (Undeprecated)

- (nonnull TIPImageFetchOperation *)undeprecatedFetchImageWithRequest:(nonnull id<TIPImageFetchRequest>)request context:(nullable id)context delegate:(nullable id<TIPImageFetchDelegate>)delegate
{
    TIPImageFetchOperation *op = [self operationWithRequest:request context:context delegate:delegate];
    [self fetchImageWithOperation:op];
    return op;
}

- (nonnull TIPImageFetchOperation *)undeprecatedFetchImageWithRequest:(nonnull id<TIPImageFetchRequest>)request context:(nullable id)context completion:(nullable TIPImagePipelineFetchCompletionBlock)completion
{
    TIPImageFetchOperation *op = [self operationWithRequest:request context:context completion:completion];
    [self fetchImageWithOperation:op];
    return op;
}

@end

static TIPImagePipeline *sPipeline = nil;

@implementation TIPImagePipelineBaseTests

+ (TIPImagePipeline *)sharedPipeline
{
    return sPipeline;
}

+ (NSString *)pathForImageOfType:(NSString *)type progressive:(BOOL)progressive
{
    NSString *imagePath = nil;
    NSBundle *thisBundle = TIPTestsResourceBundle();

    if ([type isEqualToString:TIPImageTypeGIF]) {
        imagePath = [thisBundle pathForResource:@"fireworks" ofType:@"gif"];
    } else {
        NSString *extension = nil;

        if ([type isEqualToString:TIPImageTypeJPEG]) {
            extension = (progressive) ? @"pjpg" : @"jpg";
        } else if ([type isEqualToString:TIPImageTypeJPEG2000]) {
            extension = @"jp2";
        } else if ([type isEqualToString:TIPImageTypePNG]) {
            extension = @"png";
        }

        if (extension) {
            imagePath = [thisBundle pathForResource:@"carnival" ofType:extension];
        }
    }

    return imagePath;
}

+ (NSURL *)dummyURLWithPath:(NSString *)path
{
    if (!path) {
        path = @"";
    }
    if (![path hasPrefix:@"/"]) {
        path = [@"/" stringByAppendingString:path];
    }
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://www.dummy.com%@", path]];
}

+ (void)setUp
{
    TIPGlobalConfiguration *globalConfig = [TIPGlobalConfiguration sharedInstance];
    TIPSetDebugSTOPOnAssertEnabled(NO);
    TIPSetShouldAssertDuringPipelineRegistation(NO);
    sPipeline = [[TIPImagePipeline alloc] initWithIdentifier:NSStringFromClass(self)];
    globalConfig.imageFetchDownloadProvider = [[TIPTestsImageFetchDownloadProviderOverrideClass() alloc] init];
    globalConfig.maxConcurrentImagePipelineDownloadCount = 4;
    globalConfig.maxBytesForAllRenderedCaches = 12 * 1024 * 1024;
    globalConfig.maxBytesForAllMemoryCaches = 12 * 1024 * 1024;
    globalConfig.maxBytesForAllDiskCaches = 16 * 1024 * 1024;
    globalConfig.maxRatioSizeOfCacheEntry = 0;
}

+ (void)tearDown
{
    TIPGlobalConfiguration *globalConfig = [TIPGlobalConfiguration sharedInstance];
    TIPSetDebugSTOPOnAssertEnabled(YES);
    TIPSetShouldAssertDuringPipelineRegistation(YES);
    [sPipeline clearMemoryCaches];
    [sPipeline clearDiskCache];
    globalConfig.imageFetchDownloadProvider = nil;
    globalConfig.maxBytesForAllRenderedCaches = -1;
    globalConfig.maxBytesForAllMemoryCaches = -1;
    globalConfig.maxBytesForAllDiskCaches = -1;
    globalConfig.maxConcurrentImagePipelineDownloadCount = TIPMaxConcurrentImagePipelineDownloadCountDefault;
    globalConfig.maxRatioSizeOfCacheEntry = -1;

    sPipeline = nil;
}

- (void)tearDown
{
    [sPipeline clearMemoryCaches];
    [sPipeline clearDiskCache];

    id<TIPImageFetchDownloadProviderWithStubbingSupport> provider = (id<TIPImageFetchDownloadProviderWithStubbingSupport>)[TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider;
    [provider removeAllDownloadStubs];

    // Flush ALL pipelines
    __block BOOL didInspect = NO;
    [[TIPGlobalConfiguration sharedInstance] inspect:^(NSDictionary *results) {
        didInspect = YES;
    }];
    while (!didInspect) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    [super tearDown];
}

#pragma mark Delegate

- (void)tip_imageFetchOperationDidStart:(TIPImageFetchOperation *)op
{
    TIPImagePipelineTestContext *context = op.context;
    context.didStart = YES;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op willAttemptToLoadFromSource:(TIPImageLoadSource)source
{
    TIPImagePipelineTestContext *context = op.context;
    NSArray *existing = context.hitLoadSources ?: @[];
    context.hitLoadSources = [existing arrayByAddingObject:@(source)];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadPreviewImage:(id<TIPImageFetchResult>)previewResult completion:(TIPImageFetchDidLoadPreviewCallback)completion
{
    TIPImagePipelineTestContext *context = op.context;
    context.didProvidePreviewCheck = YES;

    completion(context.shouldCancelOnPreview ? TIPImageFetchPreviewLoadedBehaviorStopLoading : TIPImageFetchPreviewLoadedBehaviorContinueLoading);
}

- (BOOL)tip_imageFetchOperation:(TIPImageFetchOperation *)op shouldLoadProgressivelyWithIdentifier:(NSString *)identifier URL:(NSURL *)URL imageType:(NSString *)imageType originalDimensions:(CGSize)originalDimensions
{
    TIPImagePipelineTestContext *context = op.context;
    context.didMakeProgressiveCheck = YES;
    return context.shouldSupportProgressiveLoading;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didUpdateProgressiveImage:(id<TIPImageFetchResult>)progressiveResult progress:(float)progress
{
    TIPImagePipelineTestContext *context = op.context;
    context.progressiveProgressCount++;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFirstAnimatedImageFrame:(id<TIPImageFetchResult>)progressiveResult progress:(float)progress
{
    TIPImagePipelineTestContext *context = op.context;
    context.firstAnimatedFrameProgress = progress;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didUpdateProgress:(float)progress
{
    TIPImagePipelineTestContext *context = op.context;
    context.normalProgressCount++;
    if (context.firstProgress == 0.0f) {
        context.firstProgress = progress;
    }
    if (context.firstProgress > 0.0f && progress == 0.0f) {
        context.progressWasReset = YES;
    }
    if (!context.associatedDownloadContext) {
        context.associatedDownloadContext = [op associatedDownloadContext];
    }
    if (progress > context.cancelPoint) {
        [op cancel];
    }
    if (context.shouldCancelOnOtherContextFirstProgress && context.otherContext.firstProgress > 0.0f) {
        [op cancel];
    }
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFinalImage:(id<TIPImageFetchResult>)finalResult
{
    TIPImagePipelineTestContext *context = op.context;
    context.finalImageContainer = finalResult.imageContainer;
    context.finalSource = finalResult.imageSource;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didFailToLoadFinalImage:(NSError *)error
{
    TIPImagePipelineTestContext *context = op.context;
    context.finalError = error;
}

@end
