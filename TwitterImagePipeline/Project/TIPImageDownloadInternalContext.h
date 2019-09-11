//
//  TIPImageDownloadInternalContext.h
//  TwitterImagePipeline
//
//  Created on 10/14/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import "TIPImageDiskCacheTemporaryFile.h"
#import "TIPImageDownloader.h"
#import "TIPImageFetchDownload.h"
#import "TIPImageFetchOperation+Project.h"

NS_ASSUME_NONNULL_BEGIN

@interface TIPImageDownloadInternalContext : NSObject <TIPImageFetchOperationUnderlyingContext, TIPImageFetchDownloadContext>
{
@public

    // owner
    __unsafe_unretained id<TIPImageFetchDownload> __nullable _download;

    // request source state
    TIPImageDiskCacheTemporaryFile * __nullable _temporaryFile;
    TIPPartialImage * __nullable _partialImage;
    NSString * __nullable _lastModified;
    NSDictionary<NSString *, id> * __nullable _decoderConfigMap;

    // internal progress state
    NSError * __nullable _progressStateError;
    NSHTTPURLResponse * __nullable _response;
    NSUInteger _contentLength;

    // internal progress state flags
    struct {
        BOOL didRequestHydration:1;
        BOOL didRequestAuthorization:1;
        BOOL didStart:1;
        BOOL didReceiveResponse:1;
        BOOL responseStatusCodeIsFailure:1;
        BOOL didReceiveData:1;
        BOOL didComplete:1;
    } _flags;

@private

    NSMutableArray<id<TIPImageDownloadDelegate>> * __nonnull _delegates;
}

@property (nonatomic, copy, nullable) NSURLRequest *originalRequest;
@property (nonatomic, copy, nullable) NSURLRequest *hydratedRequest;
@property (nonatomic, copy, nullable) NSString *authorization;
@property (nonatomic, nullable) id<TIPImageFetchDownloadClient> client;
@property (nonatomic, nullable) dispatch_queue_t downloadQueue;

@property (nonatomic, readonly) NSUInteger delegateCount; // computed property

- (void)reset; // called when retrying a download and resetting state

- (NSOperationQueuePriority)downloadPriority;
- (nullable id<TIPImageDownloadDelegate>)firstDelegate;
- (BOOL)containsDelegate:(id<TIPImageDownloadDelegate>)delegate;
- (void)addDelegate:(id<TIPImageDownloadDelegate>)delegate;
- (void)removeDelegate:(id<TIPImageDownloadDelegate>)delegate;
- (void)executePerDelegateSuspendingQueue:(nullable dispatch_queue_t)queue
                                    block:(void(^)(id<TIPImageDownloadDelegate>))block;
+ (void)executeDelegate:(id<TIPImageDownloadDelegate>)delegate
        suspendingQueue:(nullable dispatch_queue_t)queue
                  block:(void (^)(id<TIPImageDownloadDelegate>))block;

@end

NS_ASSUME_NONNULL_END
