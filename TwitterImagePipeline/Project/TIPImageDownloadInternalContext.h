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

@property (nonatomic, assign, nullable) id<TIPImageFetchDownload> download;
@property (nonatomic, copy, nullable) NSURLRequest *hydratedRequest;
@property (nonatomic, nullable) id<TIPImageFetchDownloadClient> client;
@property (nonatomic, nullable) dispatch_queue_t downloadQueue;

@property (nonatomic, copy, nullable) NSURLRequest *originalRequest;
@property (nonatomic, nullable) TIPImageDiskCacheTemporaryFile *temporaryFile;
@property (nonatomic, nullable) TIPPartialImage *partialImage;
@property (nonatomic, copy, nullable) NSString *lastModified;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *decoderConfigMap;

@property (nonatomic, nullable) NSError *progressStateError;

@property (nonatomic) BOOL didRequestHydration;
@property (nonatomic) BOOL didStart;
@property (nonatomic) BOOL didReceiveResponse;
@property (nonatomic) BOOL didReceiveData;
@property (nonatomic) BOOL didComplete;

@property (nonatomic, nullable) NSHTTPURLResponse *response;
@property (nonatomic) NSUInteger contentLength;
@property (nonatomic, readonly) NSUInteger delegateCount;

- (NSOperationQueuePriority)downloadPriority;
- (nullable id<TIPImageDownloadDelegate>)firstDelegate;
- (BOOL)containsDelegate:(id<TIPImageDownloadDelegate>)delegate;
- (void)addDelegate:(id<TIPImageDownloadDelegate>)delegate;
- (void)removeDelegate:(id<TIPImageDownloadDelegate>)delegate;
- (void)executePerDelegateSuspendingQueue:(nullable dispatch_queue_t)queue block:(void(^)(id<TIPImageDownloadDelegate>))block;
+ (void)executeDelegate:(id<TIPImageDownloadDelegate>)delegate suspendingQueue:(nullable dispatch_queue_t)queue block:(void (^)(id<TIPImageDownloadDelegate>))block;

@end

NS_ASSUME_NONNULL_END
