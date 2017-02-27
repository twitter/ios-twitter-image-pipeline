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

@interface TIPImageDownloadInternalContext : NSObject <TIPImageFetchOperationUnderlyingContext, TIPImageFetchDownloadContext>

@property (nonatomic, assign, nullable) id<TIPImageFetchDownload> download;
@property (nonatomic, copy, nullable) NSURLRequest *hydratedRequest;
@property (nonatomic, nullable) id<TIPImageFetchDownloadClient> client;
@property (nonatomic, nullable) dispatch_queue_t downloadQueue;

@property (nonatomic, copy, nullable) NSURLRequest *originalRequest;
@property (nonatomic, nullable) TIPImageDiskCacheTemporaryFile *temporaryFile;
@property (nonatomic, nullable) TIPPartialImage *partialImage;
@property (nonatomic, copy, nullable) NSString *lastModified;

@property (nonatomic, nullable) NSError *progressStateError;

@property (nonatomic) BOOL doesProtocolSupportCancel;
@property (nonatomic) BOOL didRequestHydration;
@property (nonatomic) BOOL didStart;
@property (nonatomic) BOOL didReceiveResponse;
@property (nonatomic) BOOL didReceiveData;
@property (nonatomic) BOOL didComplete;

@property (nonatomic, nullable) NSHTTPURLResponse *response;
@property (nonatomic) NSUInteger contentLength;
@property (nonatomic, readonly) NSUInteger delegateCount;
@property (nonatomic) NSUInteger totalBytesReceived;
@property (nonatomic) uint64_t firstBytesReceivedMachTime;
@property (nonatomic) uint64_t latestBytesReceivedMachTime;
- (int64_t)latestBytesPerSecond;
- (BOOL)canContinueAsDetachedDownload;

- (NSOperationQueuePriority)downloadPriority;
- (nullable id<TIPImageDownloadDelegate>)firstDelegate;
- (BOOL)containsDelegate:(nonnull id<TIPImageDownloadDelegate>)delegate;
- (void)addDelegate:(nonnull id<TIPImageDownloadDelegate>)delegate;
- (void)removeDelegate:(nonnull id<TIPImageDownloadDelegate>)delegate;
- (void)executePerDelegateSuspendingQueue:(nullable dispatch_queue_t)queue block:(nonnull void(^)(id<TIPImageDownloadDelegate> __nonnull))block;
+ (void)executeDelegate:(nonnull id<TIPImageDownloadDelegate>)delegate suspendingQueue:(nullable dispatch_queue_t)queue block:(nonnull void (^)(id<TIPImageDownloadDelegate> __nonnull))block;

@end
