//
//  TIPImageDownloadInternalContext.m
//  TwitterImagePipeline
//
//  Created on 10/14/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageDownloadInternalContext.h"
#import "TIPTiming.h"

static NSUInteger const kSmallPacketSize = 1 * 1024;

@implementation TIPImageDownloadInternalContext
{
    NSMutableArray<id<TIPImageDownloadDelegate>> *_delegates;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _delegates = [NSMutableArray array];
    }
    return self;
}

- (NSUInteger)delegateCount
{
    return _delegates.count;
}

- (TIPImageFetchOperation *)associatedImageFetchOperation
{
    for (id<TIPImageDownloadDelegate> delegate in _delegates) {
        if ([delegate isKindOfClass:[TIPImageFetchOperation class]]) {
            return (id)delegate;
        }
    }
    return nil;
}

- (id<TIPImageDownloadDelegate>)firstDelegate
{
    return _delegates.firstObject;
}

- (NSOperationQueuePriority)downloadPriority
{
    NSOperationQueuePriority pri = NSOperationQueuePriorityVeryLow;
    for (id<TIPImageDownloadDelegate> delegate in _delegates) {
        const NSOperationQueuePriority delegatePriority = delegate.imageDownloadRequest.imageDownloadPriority;
        pri = MAX(pri, delegatePriority);
    }
    return pri;
}

- (int64_t)latestBytesPerSecond
{
    if (!_latestBytesReceivedMachTime || !_firstBytesReceivedMachTime) {
        return -1;
    }

    const NSTimeInterval ti = TIPComputeDuration(_firstBytesReceivedMachTime, _latestBytesReceivedMachTime);
    const double bytesPerSecond = (double)_totalBytesReceived / ti;
    return (int64_t)bytesPerSecond;
}

- (BOOL)canContinueAsDetachedDownload
{
    // Does the protocol handle cancel gracefully?
    if (self.doesProtocolSupportCancel) {
        // Don't continue, just cancel
        TIPLogDebug(@"Download[%p] has protocol that supports cancelling so we won't detach", self.download);
        return NO;
    }

    NSTimeInterval maxTimeRemaining = [TIPGlobalConfiguration sharedInstance].maxEstimatedTimeRemainingForDetachedHTTPDownloads;
    if (maxTimeRemaining < 0.01) {
        TIPLogDebug(@"Download[%p] cannot be detached because detaching is disabled", self.download);
        return NO;
    }

    // Pull out the bitrate
    int64_t bytesPerSecond = self.latestBytesPerSecond;
    if (bytesPerSecond <= 0) {
        TIPEstimatedBitrateProviderBlock estimatingBlock = [TIPGlobalConfiguration sharedInstance].estimatedBitrateProviderBlock;
        if (estimatingBlock) {
            bytesPerSecond = estimatingBlock(self.hydratedRequest.URL.host ?: self.originalRequest.URL.host) / 8; // divide by 8 to get Byte-rate instead of bit-rate
            if (bytesPerSecond > 0) {
                TIPLogInformation(@"Download[%p] doesn't have a known bitrate yet, defering bitrate estimate to external provider", self.download);
            }
        }
    }

    NSUInteger bytesRemaining = 0;

    // Did we get the Content-Length?
    if (0 == self.contentLength) {
        if (0 == self.response.statusCode) {
            // Guesstimate the download size to start
            bytesRemaining = 1 * 1024 * 1024;
        } else {
            // Indeterminate download
            TIPLogInformation(@"Download[%p] is indeterminate, cancelling instead of detaching. %@", self.download, self.hydratedRequest.URL);
            return NO;
        }
    } else if (self.contentLength >= self.partialImage.byteCount) {
        // Get the actual bytes remaining
        bytesRemaining = self.contentLength - self.partialImage.byteCount;
    } else {
        // More bytes downloaded than bytes expected from the Content-Length header.
        // Let's calculate how much over we are.

        double overload = (double)(self.partialImage.byteCount - self.contentLength) / (double)self.contentLength;

        // Are we more than 10% over?
        if (overload > 0.1) {
            // more than 10%, this is an indeterminate download
            TIPLogInformation(@"Download[%p] bytes exceed expected bytes by %%%.02f, cancelling instead of detaching. %@", self.download, overload * 100.0, self.hydratedRequest.URL);
            return NO;
        } else {
            // Let's treat this as an inaccurate Content-Length header (happens all the time).
            // Estimate the bytes remaining to be the same as the bytes we've exceeded.
            bytesRemaining = self.partialImage.byteCount - self.contentLength;
            // As the bytes remaining grows, the time remaining estimate will also grow making it
            // more likely to not detach (just cancel) which is reasonable since it will become
            // more likely that the download is indeterminate.

            TIPLogDebug(@"Download[%p] bytes exceeded expected bytes by %tu bytes. %@", self.download, bytesRemaining, self.hydratedRequest.URL);
        }
    }

    // Do we have less than a KB left?
    if (bytesRemaining < kSmallPacketSize) {
        // Permit "detached" downloading
        TIPLog(self.delegateCount == 0 ? TIPLogLevelDebug : TIPLogLevelInformation, @"Download[%p] bytes remaing is small (%tu), detaching", self.download, bytesRemaining);
        return YES;
    }

    // Do we have a calculated bit-rate?
    if (bytesPerSecond <= 0) {
        // No bitrate or unknown bitrate...rather than block the network, just cancel
        TIPLogInformation(@"Download[%p] bitrate is unknown, cancelling instead of detaching", self.download);
        return NO;
    }

    NSTimeInterval timeRemaining = (double)bytesRemaining / (double)bytesPerSecond;

    // Is the time remaining reasonable?
    if (timeRemaining >= 0.0 && timeRemaining < maxTimeRemaining) {
        // Permit "detached" downloading
        TIPLog(self.delegateCount == 0 ? TIPLogLevelDebug : TIPLogLevelInformation, @"Download[%p] bitrate is fast enough (%@ps), detaching", self.download, [NSByteCountFormatter stringFromByteCount:bytesPerSecond countStyle:NSByteCountFormatterCountStyleBinary]);
        return YES;
    }

    // Unreasonable time remaining, don't detach
    TIPLogInformation(@"Download[%p] bitrate is too slow (%@ps), cancelling instead of detaching", self.download, [NSByteCountFormatter stringFromByteCount:bytesPerSecond countStyle:NSByteCountFormatterCountStyleBinary]);
    return NO;
}

- (BOOL)containsDelegate:(id<TIPImageDownloadDelegate>)delegate
{
    return [_delegates containsObject:delegate];
}

- (void)addDelegate:(id<TIPImageDownloadDelegate>)delegate
{
    [_delegates addObject:delegate];
}

- (void)removeDelegate:(id<TIPImageDownloadDelegate>)delegate
{
    NSUInteger count = _delegates.count;
    [_delegates removeObject:delegate];
    if (count > _delegates.count) {
        id<TIPImageFetchDownload> download = self.download;
        [TIPImageDownloadInternalContext executeDelegate:delegate suspendingQueue:NULL block:^(id<TIPImageDownloadDelegate> blockDelegate) {
            [blockDelegate imageDownload:(id)download didCompleteWithPartialImage:nil lastModified:nil byteSize:0 imageType:nil image:nil imageRenderLatency:0.0 error:[NSError errorWithDomain:TIPImageFetchErrorDomain code:TIPImageFetchErrorCodeCancelled userInfo:nil]];
        }];
    }
}

- (void)executePerDelegateSuspendingQueue:(dispatch_queue_t)queue block:(void(^)(id<TIPImageDownloadDelegate>))block;
{
    for (id<TIPImageDownloadDelegate> delegate in _delegates) {
        [TIPImageDownloadInternalContext executeDelegate:delegate suspendingQueue:queue block:block];
    }
}

+ (void)executeDelegate:(id<TIPImageDownloadDelegate>)delegate suspendingQueue:(dispatch_queue_t)queue block:(void (^)(id<TIPImageDownloadDelegate>))block;
{
    dispatch_queue_t delegateQueue = [delegate respondsToSelector:@selector(imageDownloadDelegateQueue)] ? delegate.imageDownloadDelegateQueue : NULL;
    if (delegateQueue) {
        if (queue) {
            dispatch_suspend(queue);
        }
        dispatch_async(delegateQueue, ^{
            block(delegate);
            if (queue) {
                dispatch_resume(queue);
            }
        });
    } else {
        block(delegate);
    }
}

@end
