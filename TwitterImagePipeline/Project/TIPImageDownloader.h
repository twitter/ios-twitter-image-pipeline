//
//  TIPImageDownloader.h
//  TwitterImagePipeline
//
//  Created on 3/3/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import <UIKit/UIImage.h>

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

NS_ASSUME_NONNULL_END

typedef void(^TIPImageDownloaderResumeInfoBlock)(NSUInteger alreadyDownloadedBytes, NSString * __nullable lastModified);

@interface TIPImageDownloader : NSObject

+ (nonnull instancetype)sharedInstance;
- (nonnull instancetype)init NS_UNAVAILABLE;
+ (nonnull instancetype)new NS_UNAVAILABLE;

- (nonnull id<TIPImageDownloadContext>)fetchImageWithDownloadDelegate:(nonnull id<TIPImageDownloadDelegate>)delegate;
- (void)removeDelegate:(nonnull id<TIPImageDownloadDelegate>)delegate forContext:(nonnull id<TIPImageDownloadContext>)context;
- (void)updatePriorityOfContext:(nonnull id<TIPImageDownloadContext>)context;

@end

@protocol TIPImageDownloadContext <NSObject>
@end

@protocol TIPImageDownloadRequest <NSObject>

@required

// Image identity
- (nonnull NSURL *)imageDownloadURL;
- (nonnull NSString *)imageDownloadIdentifier;

// HTTP Request info
- (nullable NSDictionary<NSString *, NSString *> *)imageDownloadHeaders;

// Request behavior info
- (NSOperationQueuePriority)imageDownloadPriority;
- (nullable TIPImageFetchHydrationBlock)imageDownloadHydrationBlock;

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

- (nonnull id<TIPImageDownloadRequest>)imageDownloadRequest;

- (nullable dispatch_queue_t)imageDownloadDelegateQueue;

- (nullable TIPImagePipeline *)imagePipeline;

- (nonnull TIPImageDiskCacheTemporaryFile *)regenerateImageDownloadTemporaryFileForImageDownload:(nonnull id<TIPImageDownloadContext>)context;

// Events

- (void)imageDownloadDidStart:(nonnull id<TIPImageDownloadContext>)context;

- (void)imageDownload:(nonnull id<TIPImageDownloadContext>)context didResetFromPartialImage:(nonnull TIPPartialImage *)oldPartialImage;

- (void)imageDownload:(nonnull id<TIPImageDownloadContext>)op
       didAppendBytes:(NSUInteger)byteCount
       toPartialImage:(nonnull TIPPartialImage *)partialImage
               result:(TIPImageDecoderAppendResult)result;

- (void)imageDownload:(nonnull id<TIPImageDownloadContext>)op
didCompleteWithPartialImage:(nullable TIPPartialImage *)partialImage
         lastModified:(nullable NSString *)lastModified
             byteSize:(NSUInteger)bytes
            imageType:(nullable NSString *)imageType
                image:(nullable TIPImageContainer *)image
   imageRenderLatency:(NSTimeInterval)latency
                error:(nullable NSError *)error;

@end
