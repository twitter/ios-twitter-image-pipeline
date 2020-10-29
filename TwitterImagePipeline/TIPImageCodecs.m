//
//  TIPImageCodecs.m
//  TwitterImagePipeline
//
//  Created on 11/7/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPImageCodecs.h"

NS_ASSUME_NONNULL_BEGIN

TIPImageContainer * __nullable TIPDecodeImageFromData(id<TIPImageCodec> codec,
                                                      id __nullable config,
                                                      NSData *imageData,
                                                      CGSize targetDimensions,
                                                      UIViewContentMode targetContentMode) __attribute__((overloadable))
{
    return TIPDecodeImageFromData(codec, config, imageData, targetDimensions, targetContentMode, nil);
}

TIPImageContainer * __nullable TIPDecodeImageFromData(id<TIPImageCodec> codec,
                                                      id __nullable config,
                                                      NSData *imageData,
                                                      CGSize targetDimensions,
                                                      UIViewContentMode targetContentMode,
                                                      NSString * __nullable earlyGuessImageType) __attribute__((overloadable))
{
    TIPImageContainer *container = nil;
    id<TIPImageDecoder> decoder = codec.tip_decoder;
    if ([decoder respondsToSelector:@selector(tip_decodeImageWithData:targetDimensions:targetContentMode:config:)]) {
        container = [decoder tip_decodeImageWithData:imageData
                                    targetDimensions:targetDimensions
                                   targetContentMode:targetContentMode
                                              config:config];
    } else if ([decoder respondsToSelector:@selector(tip_decodeImageWithData:config:)]) {
        TIPLogWarning(@"%@ implements legacy %@, needs to be updated to implement modern %@ method",
                      decoder,
                      NSStringFromSelector(@selector(tip_decodeImageWithData:config:)),
                      NSStringFromSelector(@selector(tip_decodeImageWithData:targetDimensions:targetContentMode:config:)));
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        container = [decoder tip_decodeImageWithData:imageData
                                              config:config];
#pragma clang diagnostic pop
    } else {
        const TIPImageDecoderDetectionResult result = [decoder tip_detectDecodableData:imageData
                                                                        isCompleteData:YES
                                                                   earlyGuessImageType:earlyGuessImageType];
        if (TIPImageDecoderDetectionResultMatch == result) {
            id<TIPImageDecoderContext> context = [decoder tip_initiateDecoding:config
                                                            expectedDataLength:imageData.length
                                                                        buffer:nil];
            [decoder tip_append:context data:imageData];
            if (TIPImageDecoderAppendResultDidCompleteLoading == [decoder tip_finalizeDecoding:context]) {
                container = [decoder tip_renderImage:context
                                          renderMode:TIPImageDecoderRenderModeCompleteImage
                                    targetDimensions:targetDimensions
                                   targetContentMode:targetContentMode];
            }
        }
    }
    return container;
}

BOOL TIPEncodeImageToFile(id<TIPImageCodec> codec,
                          TIPImageContainer *imageContainer,
                          NSString *filePath,
                          TIPImageEncodingOptions options,
                          float quality,
                          BOOL atomic,
                          NSError * __autoreleasing __nullable * __nullable error)
{
    BOOL success = NO;
    id<TIPImageEncoder> encoder = codec.tip_encoder;
    if (!encoder) {
        if (error) {
            *error = [NSError errorWithDomain:TIPErrorDomain
                                         code:TIPErrorCodeEncodingUnsupported
                                     userInfo:@{ @"codec" : codec }];
        }
    } else {
        if ([encoder respondsToSelector:@selector(tip_writeToFile:withImage:encodingOptions:suggestedQuality:atomically:error:)]) {
            success = [encoder tip_writeToFile:filePath
                                     withImage:imageContainer
                               encodingOptions:options
                              suggestedQuality:quality
                                    atomically:atomic
                                         error:error];
        } else {
            NSData *data = [encoder tip_writeDataWithImage:imageContainer
                                           encodingOptions:options
                                          suggestedQuality:quality
                                                     error:error];
            if (data) {
                success = [data writeToFile:filePath options:(atomic) ? NSDataWritingAtomic : 0 error:error];
            }
        }
    }

    if (!success && error) {
        TIPAssert(*error != nil);
        if (!*error) {
            *error = [NSError errorWithDomain:TIPErrorDomain
                                         code:TIPErrorCodeUnknown
                                     userInfo:nil];
        }
    }

    return success;
}

NS_ASSUME_NONNULL_END
