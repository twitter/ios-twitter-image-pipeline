//
//  TIPTestImageFetchDownloadInternalWithStubbing.h
//  TwitterImagePipeline
//
//  Created on 8/28/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIPImageFetchDownloadInternal.h"

@interface TIPTestImageFetchDownloadInternalWithStubbing : TIPImageFetchDownloadInternal <TIPImageFetchDownload>
- (instancetype)initWithContext:(id<TIPImageFetchDownloadContext>)context NS_UNAVAILABLE;
- (instancetype)initWithContext:(id<TIPImageFetchDownloadContext>)context stub:(BOOL)stub;
@end

@interface TIPTestImageFetchDownloadProviderInternalWithStubbing : NSObject <TIPImageFetchDownloadProviderWithStubbingSupport>
@property (nonatomic, readwrite) BOOL downloadStubbingEnabled;
@end
