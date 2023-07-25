//
//  TIPTestImageFetchDownloadInternalWithStubbing.m
//  TwitterImagePipeline
//
//  Created on 8/28/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIPTestImageFetchDownloadInternalWithStubbing.h"
#import "TIPTestURLProtocol.h"

static NSURLSession *sTIPTestImageFetchDownloadInternalURLSessionWithPseudo = nil;

@interface TIPTestURLProtocol (TIPConvenience)

+ (void)tip_registerResponseData:(nullable NSData *)responseData responseMIMEType:(nullable NSString *)MIMEType shouldSupportResuming:(BOOL)shouldSupportResume suggestedBitrate:(uint64_t)suggestedBitrate withEndpoint:(nonnull NSURL *)endpointURL;

@end

@implementation TIPTestImageFetchDownloadProviderInternalWithStubbing

- (id<TIPImageFetchDownload>)imageFetchDownloadWithContext:(id<TIPImageFetchDownloadContext>)context
{
    return [[TIPTestImageFetchDownloadInternalWithStubbing alloc] initWithContext:context stub:self.downloadStubbingEnabled];
}

- (void)addDownloadStubForRequestURL:(NSURL *)requestURL responseData:(NSData *)responseData responseMIMEType:(NSString *)MIMEType shouldSupportResuming:(BOOL)shouldSupportResume suggestedBitrate:(uint64_t)suggestedBitrate
{
    [TIPTestURLProtocol tip_registerResponseData:responseData responseMIMEType:MIMEType shouldSupportResuming:shouldSupportResume suggestedBitrate:suggestedBitrate withEndpoint:requestURL];
}

- (void)removeDownloadStubForRequestURL:(NSURL *)requestURL
{
    [TIPTestURLProtocol unregisterEndpoint:requestURL];
}

- (void)removeAllDownloadStubs
{
    [TIPTestURLProtocol unregisterAllEndpoints];
}

@end

@implementation TIPTestImageFetchDownloadInternalWithStubbing
{
    BOOL _stub;
}

- (instancetype)initWithContext:(id<TIPImageFetchDownloadContext>)context stub:(BOOL)stub
{
    if (self = [super initWithContext:context]) {
        _stub = stub;
    }
    return self;
}

- (NSURLSession *)URLSession
{
    if (!_stub) {
        return [super URLSession];
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSession *session = [super URLSession];
        NSURLSessionConfiguration *config = [session.configuration copy];
        id<NSURLSessionDelegate> delegate = session.delegate;
        NSOperationQueue *queue = session.delegateQueue;

        NSMutableArray *protocols = [config.protocolClasses mutableCopy];
        [protocols insertObject:[TIPTestURLProtocol class] atIndex:0];
        config.protocolClasses = protocols;

        sTIPTestImageFetchDownloadInternalURLSessionWithPseudo = [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:queue];
    });

    return sTIPTestImageFetchDownloadInternalURLSessionWithPseudo;
}

@end

@implementation TIPTestURLProtocol (TIPConvenience)

+ (void)tip_registerResponseData:(NSData *)responseData responseMIMEType:(NSString *)MIMEType shouldSupportResuming:(BOOL)shouldSupportResume suggestedBitrate:(uint64_t)suggestedBitrate withEndpoint:(NSURL *)endpointURL
{
    NSHTTPURLResponse *response = [NSHTTPURLResponse tip_responseWithRequestURL:endpointURL dataLength:responseData.length responseMIMEType:MIMEType];

    TIPTestURLProtocolResponseConfig *config = [[TIPTestURLProtocolResponseConfig alloc] init];
    config.bps = suggestedBitrate;
    config.canProvideRange = shouldSupportResume;

    [TIPTestURLProtocol registerURLResponse:response body:responseData config:config withEndpoint:endpointURL];
}

@end
