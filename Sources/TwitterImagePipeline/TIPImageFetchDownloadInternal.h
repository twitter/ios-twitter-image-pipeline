//
//  TIPImageFetchDownloadInternal.h
//  TwitterImagePipeline
//
//  Created on 8/24/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIPImageFetchDownload.h"

NS_ASSUME_NONNULL_BEGIN

@interface TIPImageFetchDownloadInternal : NSObject <TIPImageFetchDownload>
- (NSURLSession *)URLSession;
- (instancetype)initWithContext:(id<TIPImageFetchDownloadContext>)context;
@end

@interface TIPImageFetchDownloadProviderInternal : NSObject <TIPImageFetchDownloadProvider>
@end

NS_ASSUME_NONNULL_END
