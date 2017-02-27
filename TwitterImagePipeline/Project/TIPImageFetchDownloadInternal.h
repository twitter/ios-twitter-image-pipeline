//
//  TIPImageFetchDownloadInternal.h
//  TwitterImagePipeline
//
//  Created on 8/24/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import "TIPImageFetchDownload.h"

@interface TIPImageFetchDownloadInternal : NSObject <TIPImageFetchDownload>
- (nonnull NSURLSession *)URLSession;
- (nonnull instancetype)initWithContext:(nonnull id<TIPImageFetchDownloadContext>)context;
@end

@interface TIPImageFetchDownloadProviderInternal : NSObject <TIPImageFetchDownloadProvider>
@end
