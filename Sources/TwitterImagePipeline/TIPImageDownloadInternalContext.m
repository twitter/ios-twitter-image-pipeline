//
//  TIPImageDownloadInternalContext.m
//  TwitterImagePipeline
//
//  Created on 10/14/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageDownloadInternalContext.h"
#import "TIPTiming.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TIPImageDownloadInternalContext

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

- (void)reset
{
    TIPAssert(!_flags.didComplete);
    TIPAssert(!_progressStateError);

    _response = nil;
    _contentLength = 0;

    _hydratedRequest = nil;
    _authorization = nil;

    memset(&_flags, 0, sizeof(_flags));
}

- (nullable TIPImageFetchOperation *)associatedImageFetchOperation
{
    for (id<TIPImageDownloadDelegate> delegate in _delegates) {
        if ([delegate isKindOfClass:[TIPImageFetchOperation class]]) {
            return (id)delegate;
        }
    }
    return nil;
}

- (nullable id<TIPImageDownloadDelegate>)firstDelegate
{
    return _delegates.firstObject;
}

- (NSOperationQueuePriority)downloadPriority
{
    NSOperationQueuePriority pri = NSOperationQueuePriorityVeryLow + 1;
    for (id<TIPImageDownloadDelegate> delegate in _delegates) {
        const NSOperationQueuePriority delegatePriority = delegate.imageDownloadRequest.imageDownloadPriority;
        pri = MAX(pri, delegatePriority);
    }
    return pri;
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
        id<TIPImageFetchDownload> download = _download;
        [TIPImageDownloadInternalContext executeDelegate:delegate suspendingQueue:NULL block:^(id<TIPImageDownloadDelegate> blockDelegate) {
            [blockDelegate imageDownload:(id)download
             didCompleteWithPartialImage:nil
                            lastModified:nil
                                byteSize:0
                               imageType:nil
                                   image:nil
                               imageData:nil
                      imageRenderLatency:0.0
                              statusCode:0
                                   error:[NSError errorWithDomain:TIPImageFetchErrorDomain
                                                             code:TIPImageFetchErrorCodeCancelled
                                                         userInfo:nil]];
        }];
    }
}

- (void)executePerDelegateSuspendingQueue:(nullable dispatch_queue_t)queue
                                    block:(void(^)(id<TIPImageDownloadDelegate>))block
{
    for (id<TIPImageDownloadDelegate> delegate in _delegates) {
        [TIPImageDownloadInternalContext executeDelegate:delegate
                                         suspendingQueue:queue block:block];
    }
}

+ (void)executeDelegate:(id<TIPImageDownloadDelegate>)delegate
        suspendingQueue:(nullable dispatch_queue_t)queue
                  block:(void (^)(id<TIPImageDownloadDelegate>))block
{
    dispatch_queue_t delegateQueue = [delegate respondsToSelector:@selector(imageDownloadDelegateQueue)] ? delegate.imageDownloadDelegateQueue : NULL;
    if (delegateQueue) {
        if (queue) {
            dispatch_suspend(queue);
        }
        tip_dispatch_async_autoreleasing(delegateQueue, ^{
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

NS_ASSUME_NONNULL_END
