//
//  TIPImageDownloader.h
//  TwitterImagePipeline
//
//  Created on 3/3/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import <UIKit/UIImage.h>

#import "TIP_Project.h"
#import "TIPImageCodecs.h"
#import "TIPImageFetchRequest.h"
#import "TIPPartialImage.h"

@class TIPImageResponse;
@class TIPImageDiskCacheTemporaryFile;
@class TIPImagePipeline;

@protocol TIPImageDownloadContext;
@protocol TIPImageDownloadRequest;
@protocol TIPImageDownloadDelegate;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString * const TIPImageDownloaderCancelSource;

typedef void(^TIPImageDownloaderResumeInfoBlock)(NSUInteger alreadyDownloadedBytes,
                                                 NSString * __nullable lastModified);

TIP_OBJC_FINAL TIP_OBJC_DIRECT_MEMBERS
@interface TIPImageDownloader : NSObject

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (id<TIPImageDownloadContext>)fetchImageWithDownloadDelegate:(id<TIPImageDownloadDelegate>)delegate;
- (void)removeDelegate:(id<TIPImageDownloadDelegate>)delegate
            forContext:(id<TIPImageDownloadContext>)context;
- (void)updatePriorityOfContext:(id<TIPImageDownloadContext>)context;

@end

@protocol TIPImageDownloadContext <NSObject>
@end

@protocol TIPImageDownloadRequest <NSObject>

@required

// Image identity - either returning `nil` is an invalid request
- (nullable NSURL *)imageDownloadURL;
- (nullable NSString *)imageDownloadIdentifier;

// HTTP Request info
- (nullable NSDictionary<NSString *, NSString *> *)imageDownloadHeaders;

// Request behavior info
- (NSOperationQueuePriority)imageDownloadPriority;
- (nullable TIPImageFetchHydrationBlock)imageDownloadHydrationBlock;
- (nullable TIPImageFetchAuthorizationBlock)imageDownloadAuthorizationBlock;
- (nullable NSDictionary<NSString *, id> *)decoderConfigMap;
- (CGSize)targetDimensions;
- (UIViewContentMode)targetContentMode;

// Loaded image behavior info
- (NSTimeInterval)imageDownloadTTL;
- (TIPImageFetchOptions)imageDownloadOptions;

// Resume info
- (nullable NSString *)imageDownloadLastModified;
- (nullable TIPPartialImage *)imageDownloadPartialImageForResuming;
- (nullable TIPImageDiskCacheTemporaryFile *)imageDownloadTemporaryFileForResuming;

@end

@protocol TIPImageDownloadDelegate <NSObject>

@required

// Execution

- (id<TIPImageDownloadRequest>)imageDownloadRequest;

- (nullable dispatch_queue_t)imageDownloadDelegateQueue;

- (nullable TIPImagePipeline *)imagePipeline;

- (TIPImageDiskCacheTemporaryFile *)regenerateImageDownloadTemporaryFileForImageDownload:(id<TIPImageDownloadContext>)context;

// Events

- (void)imageDownloadDidStart:(id<TIPImageDownloadContext>)context;

- (void)imageDownload:(id<TIPImageDownloadContext>)context
        didResetFromPartialImage:(TIPPartialImage *)oldPartialImage;

- (void)imageDownload:(id<TIPImageDownloadContext>)op
       didAppendBytes:(NSUInteger)byteCount
       toPartialImage:(TIPPartialImage *)partialImage
               result:(TIPImageDecoderAppendResult)result;

- (void)imageDownload:(id<TIPImageDownloadContext>)op
        didCompleteWithPartialImage:(nullable TIPPartialImage *)partialImage
        lastModified:(nullable NSString *)lastModified
        byteSize:(NSUInteger)bytes
        imageType:(nullable NSString *)imageType
        image:(nullable TIPImageContainer *)image
        imageData:(nullable NSData*)imageData
        imageRenderLatency:(NSTimeInterval)latency
        statusCode:(NSInteger)statusCode
        error:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
