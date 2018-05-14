//
//  TIPTestURLProtocol.m
//  TwitterImagePipeline
//
//  Created on 9/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import "NSData+TIPAdditions.h"
#import "NSDictionary+TIPAdditions.h"
#import "TIP_Project.h"
#import "TIPTestURLProtocol.h"

#define SELF_ARG PRIVATE_SELF(TIPTestURLProtocol)

NS_ASSUME_NONNULL_BEGIN

#define ABORT_IF_NECESSARY() \
do { \
    if (self.stopped) { \
        return; \
    } \
} while (0)

NSString * const TIPTestURLProtocolErrorDomain = @"TIPTestURLProtocolErrorDomain";

static NSMutableDictionary *sOriginToResponseDictionary;
static dispatch_queue_t sOriginQueue;

static NSString * __nullable _UnderlyingURLString(NSURL * __nullable url);
static NSHTTPURLResponse *_UpdateResponse(NSHTTPURLResponse *response,
                                          NSUInteger contentLength,
                                          NSInteger statusCode);
static NSRange _RangeForRequest(NSURLRequest *request,
                                NSUInteger dataLength,
                                NSString *stringForIfRange);

typedef void(^TIPTestURLProtocolClientBlock)(id<NSURLProtocolClient> client);

@interface TIPTestURLProtocol ()

@property (atomic) BOOL stopped;
@property (nonatomic, nullable) NSCachedURLResponse *responseToUse;
@property (nonatomic, nullable) dispatch_queue_t protocolQueue;
@property (nonatomic, nullable) CFRunLoopRef protocolRunLoop;

static void _executeClientBlock(SELF_ARG,
                                TIPTestURLProtocolClientBlock block);
@end

@implementation TIPTestURLProtocol

+ (void)registerURLResponse:(NSHTTPURLResponse *)response
                       body:(nullable NSData *)body
               withEndpoint:(NSURL *)endpoint
{
    [self registerURLResponse:response
                         body:body
                       config:nil
                 withEndpoint:endpoint];
}

+ (void)registerURLResponse:(NSHTTPURLResponse *)response
                       body:(nullable NSData *)body
                     config:(nullable TIPTestURLProtocolResponseConfig *)config
               withEndpoint:(NSURL *)endpoint
{
    NSCachedURLResponse *cachedResponse = [[NSCachedURLResponse alloc] initWithResponse:response
                                                                                   data:body
                                                                               userInfo:(config) ? @{ @"config" : [config copy] } : nil
                                                                          storagePolicy:NSURLCacheStorageAllowed];

    dispatch_barrier_async(sOriginQueue, ^{
        sOriginToResponseDictionary[_UnderlyingURLString(endpoint)] = cachedResponse;
    });
}

+ (void)unregisterEndpoint:(NSURL *)endpoint
{
    dispatch_barrier_async(sOriginQueue, ^{
        [sOriginToResponseDictionary removeObjectForKey:_UnderlyingURLString(endpoint)];
    });
}

+ (void)unregisterAllEndpoints
{
    dispatch_barrier_async(sOriginQueue, ^{
        [sOriginToResponseDictionary removeAllObjects];
    });
}

+ (BOOL)isEndpointRegistered:(NSURL *)endpoint
{
    __block BOOL isRegistered = NO;
    dispatch_sync(sOriginQueue, ^{
        isRegistered = (sOriginToResponseDictionary[_UnderlyingURLString(endpoint)] != nil);
    });
    return isRegistered;
}

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sOriginToResponseDictionary = [[NSMutableDictionary alloc] init];
        sOriginQueue = dispatch_queue_create("tip.test.url.protocol.origin.queue", DISPATCH_QUEUE_CONCURRENT);
    });
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *url = _UnderlyingURLString(request.URL);
    if (!url) {
        return NO;
    }

    __block BOOL originsMatch;
    dispatch_sync(sOriginQueue, ^{
        originsMatch = sOriginToResponseDictionary[url] != nil;
    });
    return originsMatch;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    NSMutableURLRequest *mRequest = [request mutableCopy];
    mRequest.URL = [NSURL URLWithString:request.URL.absoluteString.lowercaseString];
    NSDictionary *allFields = request.allHTTPHeaderFields;
    NSMutableDictionary *mDictionary = [[NSMutableDictionary alloc] init];
    for (NSString *key in allFields.allKeys) {
        [mDictionary tip_setObject:allFields[key]
             forCaseInsensitiveKey:key.lowercaseString];
    }
    mRequest.allHTTPHeaderFields = mDictionary;
    return mRequest;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b
{
    return [a isEqual:b];
}

- (void)startLoading
{
    self.protocolRunLoop = CFRunLoopGetCurrent();
    dispatch_async(_protocolQueue, ^{
        ABORT_IF_NECESSARY();

        NSURLRequest *request = self.request;
        NSString *url = _UnderlyingURLString(request.URL);
        TIPAssert(url);
        __block NSCachedURLResponse *response;
        dispatch_sync(sOriginQueue, ^{
            response = sOriginToResponseDictionary[url];
        });

        if (response) {
            if (self.cachedResponse) {
                dispatch_async(self->_protocolQueue, ^{
                    ABORT_IF_NECESSARY();
                    _executeClientBlock(self, ^(id<NSURLProtocolClient> client){
                        [client URLProtocol:self cachedResponseIsValid:self.cachedResponse];
                    });
                    dispatch_async(self->_protocolQueue, ^{
                        ABORT_IF_NECESSARY();
                        self.stopped = YES;
                        _executeClientBlock(self, ^(id<NSURLProtocolClient> client){
                            [client URLProtocolDidFinishLoading:self];
                        });
                    });
                });
            } else {

                TIPTestURLProtocolResponseConfig *config = response.userInfo[@"config"];

                if (config.extraRequestHeaders.count > 0) {
                    NSMutableDictionary *fullHeaders = [NSMutableDictionary dictionaryWithDictionary:config.extraRequestHeaders];
                    [fullHeaders addEntriesFromDictionary:request.allHTTPHeaderFields];
                    NSMutableURLRequest *mRequest = [request mutableCopy];
                    mRequest.allHTTPHeaderFields = fullHeaders;
                    request = mRequest;
                }

                NSTimeInterval delay, latency;
                delay = ((double)config.delay) / 1000.0;
                latency = ((double)config.latency) / 1000.0;

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((delay + latency) * NSEC_PER_SEC)), self->_protocolQueue, ^{
                    ABORT_IF_NECESSARY();

                    if (config.failureError) {
                        self.stopped = YES;
                        _executeClientBlock(self, ^(id<NSURLProtocolClient> client){
                            [client URLProtocol:self didFailWithError:config.failureError];
                        });
                        return;
                    }

                    NSHTTPURLResponse *httpResponse = (id)response.response;
                    NSData *data = response.data;
                    NSInteger statusCode = (config.statusCode > 0) ? config.statusCode : httpResponse.statusCode;
                    if (200 == statusCode && config.canProvideRange) {

                        const NSRange range = _RangeForRequest(request, data.length, config.stringForIfRange);
                        if (range.location != NSNotFound) {
                            // subrange requested, provide it
                            statusCode = 206;
                            data = [data subdataWithRange:range];
                        }

                    }

                    httpResponse = _UpdateResponse(httpResponse, data.length, statusCode);

                    dispatch_async(self->_protocolQueue, ^{
                        ABORT_IF_NECESSARY();
                        _executeClientBlock(self, ^(id<NSURLProtocolClient> client){
                            [client URLProtocol:self
                             didReceiveResponse:httpResponse
                             cacheStoragePolicy:response.storagePolicy];
                        });

                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(latency * NSEC_PER_SEC)), self->_protocolQueue, ^{
                            ABORT_IF_NECESSARY();

                            NSUInteger bps = NSUIntegerMax;
                            if (config.bps > 0) {
                                bps = (NSUInteger)MIN(config.bps / 8ULL, (uint64_t)NSUIntegerMax);
                            }

                            _chunkData(self,
                                       data,
                                       bps,
                                       0 /*bytesSent*/,
                                       MAX(latency, 0.25));
                        });
                    });
                });
            }
        } else {
            dispatch_async(self->_protocolQueue, ^{
                ABORT_IF_NECESSARY();
                self.stopped = YES;
                _executeClientBlock(self, ^(id<NSURLProtocolClient> client){
                    [client URLProtocol:self
                       didFailWithError:[NSError errorWithDomain:TIPTestURLProtocolErrorDomain
                                                            code:ENOENT
                                                        userInfo:nil]];
                });
            });
        }
    });
}

static void _chunkData(SELF_ARG,
                       NSData *data,
                       NSUInteger bps,
                       NSUInteger bytesSent,
                       NSTimeInterval latency)
{
    if (!self) {
        return;
    }

    NSUInteger bytesPerLatencyGap = (NSUInteger)MAX(bps * latency, 1UL);
    NSUInteger bytesToSend = 0;
    if (bytesSent < data.length) {
        bytesToSend = MIN(bytesPerLatencyGap, data.length - bytesSent);
    }

    if (bytesToSend > 0) {
        NSData *chunk = [data tip_safeSubdataNoCopyWithRange:NSMakeRange(bytesSent, bytesToSend)];
        _executeClientBlock(self, ^(id<NSURLProtocolClient> client){
            [client URLProtocol:self didLoadData:chunk];
        });
        bytesSent += bytesToSend;
    }

    if (bytesSent >= data.length) {
        dispatch_async(self->_protocolQueue, ^{
            ABORT_IF_NECESSARY();
            self.stopped = YES;
            _executeClientBlock(self, ^(id<NSURLProtocolClient> client){
                [client URLProtocolDidFinishLoading:self];
            });
        });
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(latency * NSEC_PER_SEC)), self->_protocolQueue, ^{
            ABORT_IF_NECESSARY();
            _chunkData(self, data, bps, bytesSent, latency);
        });
    }
}

- (void)stopLoading
{
    self.stopped = YES;
}

- (instancetype)initWithRequest:(NSURLRequest *)request
                 cachedResponse:(nullable NSCachedURLResponse *)cachedResponse
                         client:(nullable id<NSURLProtocolClient>)client
{
    self = [super initWithRequest:request
                   cachedResponse:cachedResponse
                           client:client];
    if (self) {
        _protocolQueue = dispatch_queue_create("TIPTestURLProtocol.queue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

static void _executeClientBlock(SELF_ARG,
                                TIPTestURLProtocolClientBlock block)
{
    if (!self) {
        return;
    }

    CFRunLoopPerformBlock(self->_protocolRunLoop, kCFRunLoopDefaultMode, ^{
        block(self.client);
    });
    CFRunLoopWakeUp(self->_protocolRunLoop);
}

@end

@implementation TIPTestURLProtocolResponseConfig

- (instancetype)init
{
    if (self = [super init]) {
        _canProvideRange = YES;
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TIPTestURLProtocolResponseConfig *config = [[[self class] allocWithZone:zone] init];

    config.bps = self.bps;
    config.latency = self.latency;
    config.delay = self.delay;
    config.failureError = self.failureError;
    config.statusCode = self.statusCode;
    config.canProvideRange = self.canProvideRange;
    config.stringForIfRange = self.stringForIfRange;
    config.extraRequestHeaders = self.extraRequestHeaders;

    return config;
}

@end

static NSString *_UnderlyingURLString(NSURL * __nullable url)
{
    return url.absoluteString.lowercaseString;
}

static NSHTTPURLResponse *_UpdateResponse(NSHTTPURLResponse *response, NSUInteger contentLength, NSInteger statusCode)
{
    NSMutableDictionary *responseHeaderFields = [response.allHeaderFields mutableCopy];
    [responseHeaderFields tip_setObject:[@(contentLength) stringValue] forCaseInsensitiveKey:@"Content-Length"];
    return [[NSHTTPURLResponse alloc] initWithURL:response.URL statusCode:statusCode HTTPVersion:@"HTTP/1.1" headerFields:responseHeaderFields];
}

static NSRange _RangeForRequest(NSURLRequest *request, NSUInteger dataLength, NSString *stringForIfRange)
{
    NSString *range = [request.allHTTPHeaderFields tip_objectsForCaseInsensitiveKey:@"Range"].firstObject;
    NSString *ifRange = [request.allHTTPHeaderFields tip_objectsForCaseInsensitiveKey:@"If-Range"].firstObject;
    if ((!ifRange || !stringForIfRange || [ifRange isEqualToString:stringForIfRange]) && [range hasPrefix:@"bytes="]) {
        range = [range substringFromIndex:[@"bytes=" length]];
        NSArray<NSString *> *ranges = [range componentsSeparatedByString:@","];
        if (ranges.count == 1) {
            range = ranges.firstObject;
            NSArray<NSString *> *indexes = [range componentsSeparatedByString:@"-"];
            if (indexes.count == 2) {
                const NSInteger startIndex = [indexes[0] integerValue];
                NSInteger endIndex = (NSInteger)dataLength - 1;
                if ([indexes[1] length] > 0) {
                    endIndex = [indexes[1] integerValue];
                }
                if (endIndex >= startIndex) {
                    return NSMakeRange((NSUInteger)startIndex, (NSUInteger)endIndex - (NSUInteger)startIndex);
                }
            }
        }
    }

    return NSMakeRange(NSNotFound, 0);
}

NS_ASSUME_NONNULL_END

