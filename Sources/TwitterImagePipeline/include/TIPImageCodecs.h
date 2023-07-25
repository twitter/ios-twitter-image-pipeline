//
//  TIPImageCodecs.h
//  TwitterImagePipeline
//
//  Created on 11/7/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <CoreGraphics/CGGeometry.h>
#import <Foundation/Foundation.h>
#import <TIPImageTypes.h>
#import <UIKit/UIView.h> // UIViewContentMode

@protocol TIPImageEncoder;
@protocol TIPImageDecoder;
@protocol TIPImageDecoderContext;
@protocol TIPImageCodec;

@class UIImage;
@class TIPImageContainer;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Constants

/** Properties of a codec */
typedef NS_OPTIONS(NSInteger, TIPImageCodecProperties)
{
    /** no properties */
    TIPImageCodecNoProperties = 0,
    /** can decode */
    TIPImageCodecSupportsDecoding = 1 << 0,
    /** can encode */
    TIPImageCodecSupportsEncoding = 1 << 1,
    /** supports animations */
    TIPImageCodecSupportsAnimation = 1 << 2,
    /** supports decoding progressively */
    TIPImageCodecSupportsProgressiveLoading = 1 << 3,
};

/**
 Result when a `TIPImageDecoder` is detecting if the given data matches what the decoder can decode
 */
typedef NS_ENUM(NSInteger, TIPImageDecoderDetectionResult)
{
    /** no match, this decoder will not support decoding the given image data */
    TIPImageDecoderDetectionResultNoMatch = -1,
    /** need more data, this decoder needs more data before it can determine if it is a match */
    TIPImageDecoderDetectionResultNeedMoreData = 0,
    /** match, this decoder can decode the provided image data */
    TIPImageDecoderDetectionResultMatch = 1,
};

/** Result after appending data to a decoder or finalizing the decoder */
typedef NS_ENUM(NSInteger, TIPImageDecoderAppendResult)
{
    /** progress was made, but nothing significant was accomplished */
    TIPImageDecoderAppendResultDidProgress = 0,
    /** headers were loaded */
    TIPImageDecoderAppendResultDidLoadHeaders = 1,
    /** at least 1 frame finished loading */
    TIPImageDecoderAppendResultDidLoadFrame = 2,
    /** the image finished loading */
    TIPImageDecoderAppendResultDidCompleteLoading = 3,
};

/**
 The mode to render with the `TIPImageDecoder`.
 Decoders should consider rendering at the greediest capability that comes close
 to a given render mode without exceeding.
 Modes are ordered from most greedy to least greedy.
 */
typedef NS_ENUM(NSInteger, TIPImageDecoderRenderMode)
{
    /** greedily render whatever the decoder can support */
    TIPImageDecoderRenderModeAnyProgress = 0,
    /** render the latest full frame of progress */
    TIPImageDecoderRenderModeFullFrameProgress = 1,
    /** render the completed image */
    TIPImageDecoderRenderModeCompleteImage = 2,
};

#pragma mark - Protocols

/**
 Protocol for an image codec
 */
@protocol TIPImageCodec <NSObject>

@required
/**
 Return the `TIPImageDecoder` for this codec
 */
- (id<TIPImageDecoder>)tip_decoder;
/**
 Return the `TIPImageEncoder` for this codec.
 Return `nil` to indicate this codec does not support writing/encoding.
 */
- (nullable id<TIPImageEncoder>)tip_encoder;

@optional
/**
 Return `YES` to indicate the codec is for animated images
 */
- (BOOL)tip_isAnimated;

@end

/**
 Protocol for an image encoder
 */
@protocol TIPImageEncoder <NSObject>

@required
/**
 Write the target `TIPImageContainer` to an `NSData` instance
 @param encodingOptions the `TIPImageEncodingOptions` to encode with
 @param quality the quality to encode with.  Value is between `0` and `1`. `1.f` for lossless.
 @param error the error if one was encountered
 @return the encoded image as an `NSData` or `nil` if there was an error
 */
- (nullable NSData *)tip_writeDataWithImage:(TIPImageContainer *)image
                            encodingOptions:(TIPImageEncodingOptions)encodingOptions
                           suggestedQuality:(float)quality
                                      error:(out NSError * __nullable * __nullable)error;

@optional
/**
 Write the target `UIImage` to file path (optional)

 If not provided, writing this encoder's codec to disk will use the `"write data"` method

 @param filePath the path to write the image to
 @param image the `TIPImageContainer` to encode
 @param encodingOptions the `TIPImageEncodingOptions` to encode with
 @param quality the quality to encode with. Value is between `0` and `1`. `1.f` for lossless.
 @param error the error if one was encountered
 @param atomic if the writing of the file should be atomic
 @return `YES` on success, `NO` on failure
 */
- (BOOL)tip_writeToFile:(NSString *)filePath
              withImage:(TIPImageContainer *)image
        encodingOptions:(TIPImageEncodingOptions)encodingOptions
       suggestedQuality:(float)quality
             atomically:(BOOL)atomic
                  error:(out NSError * __nullable * __nullable)error;

@end

/**
 Protocol for decoder context
 */
@protocol TIPImageDecoderContext <NSObject>

@required

/** the optionally provided config object */
@property (nonatomic, readonly, nullable) id tip_config;
/** expose the current buffer of data */
@property (nonatomic, readonly) NSData *tip_data;
/** expose the dimensions of the image being decoded */
@property (nonatomic, readonly) CGSize tip_dimensions;
/**
 Expose the frame count of the image being decoded.
 Animations and progressive images will have multiple frames.
 Static images will only have 1 frame (once the complete image is loaded).
 */
@property (nonatomic, readonly) NSUInteger tip_frameCount;

@optional

/** decoding is being done progressively */
@property (nonatomic, readonly) BOOL tip_isProgressive;
/** decoding an animation */
@property (nonatomic, readonly) BOOL tip_isAnimated;
/** decoding an image with alpha */
@property (nonatomic, readonly) BOOL tip_hasAlpha;
/** decoding detected GPS info, which is a no-no */
@property (nonatomic, readonly) BOOL tip_hasGPSInfo;

@end

/**
 Protocol for an image decoder

    // Pattern for decoding (in pseudo code):
    if (Match == decoder.DetectIfDecodable()) {
       context = decoder.InitiateContext()
       while (data = MoreData()) {
           decoder.Append(context, data)
           ... optional ... {
               image = decoder.Render(context)
           }
       }
       decoder.Finalize(context)
       image = decoder.Render(context)
    }
 */
@protocol TIPImageDecoder <NSObject>

@required

/**
 Detect if the given _data_ can be decoded.
 @param data        the image data to decode (can be incomplete)
 @param complete    `YES` if the image data to decode is complete, otherwise pass `NO`
 @param imageType   a guess as to the image type, can be `nil`
 @return `Match` if decodable, `NoMatch` if not decodable and `NeedMoreData` if inconclusive
 */
- (TIPImageDecoderDetectionResult)tip_detectDecodableData:(NSData *)data
                                           isCompleteData:(BOOL)complete
                                      earlyGuessImageType:(nullable NSString *)imageType;

/**
 Initiate decoding, will be called first in the decoding process.
 Will always be balanced with a `tip_finalizeDecoding:` if the image data loading completes.
 @param config an optional opaque object to provide extra customization for how the decoding should operate, totally safe for implementation to ignore
 @param expectedDataLength the expected length of the full image data to decode
 @param buffer a prefilled buffer to start decoding with, can be `nil`.
 Can safely use this as the image decoding buffer or just copy the data from the buffer.
 @return a context to use throughout the decoding process (to help maintain state)
 */
- (id<TIPImageDecoderContext>)tip_initiateDecoding:(nullable id)config
                                expectedDataLength:(NSUInteger)expectedDataLength
                                            buffer:(nullable NSMutableData *)buffer;

/**
 Append data to a decoding

 Decoder's can just return `Progress` if they are just buffering the data and not decoding on the
 fly, which is fine.

 @param context the context to use when appending data and updating state
 @param data the non-nil data to append (though it can be zero-length)
 @return the result of the append if decoding on the fly.
 */
- (TIPImageDecoderAppendResult)tip_append:(id<TIPImageDecoderContext>)context
                                     data:(NSData *)data;

/**
 Render the image with given _mode_ with whatever progress has been made.

 Simplest implementation is to return `nil` until the decoding has been finalized
 (marked as _complete_) and then return the fully decoded image.
 More advanced decoders will progressively offer results and intelligently cache
 the progressive renders in the _context_ to avoid redundant decoding work when
 no tangible progress has happened.

 Can be called anytime after the decoding has initiated including after being finalized.

 The target sizing arguments (_targetDimensions_ and _targetContentMode_) are optional for the decoder.
 Advanced decoders will decode directly to the target sizing given, reducing RAM overhead of decoding
 the full size first.  If a codec does not support target size based decoding, they _SHOULD NOT_ scale
 the decoded full size image and instead just return the full size image for __TIP__ to handle scaling.

 @param context the context to use when rendering the image
 @param renderMode the `TIPImageDecoderRenderMode` mode to render with
 @param targetDimensions the dimension sizing constraints to decode the image into (`CGSizeZero` for full size) -- can be ignored by codec to simplify implementation
 @param targetContentMode the content mode sizing constraints to decode the image into (any non-scaling mode for full size) -- can be ignored by codec to simplify implementation
 @return an image (encapsulated in a `TIPImageContainer`) or `nil`.
 */
- (nullable TIPImageContainer *)tip_renderImage:(id<TIPImageDecoderContext>)context
                                     renderMode:(TIPImageDecoderRenderMode)renderMode
                               targetDimensions:(CGSize)targetDimensions
                              targetContentMode:(UIViewContentMode)targetContentMode;

/**
 Finalize the decoding, only called after all image data has been provided with `tip_append:data:`.
 @param context the context whose decoding is being finalized
 @return the result of the finalize.
 */
- (TIPImageDecoderAppendResult)tip_finalizeDecoding:(id<TIPImageDecoderContext>)context;

@optional

/**
 This decoder supports decoding progressively (if provided a progressive image to decode)
 */
- (BOOL)tip_supportsProgressiveDecoding;

/**
 Optional implementation for _quick_ decoding.
 Some decoders have alternative decoding mechanism when the entire image data is available.
 Implementing this method will offer that feature to __TIP__.
 Otherwise, the normal decoding pattern will be used (init, append, finalize & render).
 @param imageData the image data to decode
 @param targetDimensions the dimension sizing constraints to decode the image into (`CGSizeZero` for full size) -- can be ignored by codec to simplify implementation
 @param targetContentMode the content mode sizing constraints to decode the image into (any non-scaling mode for full size) -- can be ignored by codec to simplify implementation
 @param config an optional opaque object to provide extra customization for how the decoding should operate
 @return the decoded image (wrapped in a `TIPImageContainer`) or `nil` if the image could not be decoded
 */
- (nullable TIPImageContainer *)tip_decodeImageWithData:(NSData *)imageData
                                       targetDimensions:(CGSize)targetDimensions
                                      targetContentMode:(UIViewContentMode)targetContentMode
                                                 config:(nullable id)config;
- (nullable TIPImageContainer *)tip_decodeImageWithData:(NSData *)imageData
                                                 config:(nullable id)config __attribute__((deprecated("Implement tip_decodeImageWithData:targetDimensions:targetContentMode:config:")));


@end

#pragma mark - Convenience Functions

//! Convenience function to decode an image from data
FOUNDATION_EXTERN TIPImageContainer * __nullable TIPDecodeImageFromData(id<TIPImageCodec> codec,
                                                                        id __nullable config,
                                                                        NSData *imageData,
                                                                        CGSize targetDimensions,
                                                                        UIViewContentMode targetContentMode) __attribute__((overloadable));
//! Convenience function to decode an image from data, with a guess at the image type to be decoded
FOUNDATION_EXTERN TIPImageContainer * __nullable TIPDecodeImageFromData(id<TIPImageCodec> codec,
                                                                        id __nullable config,
                                                                        NSData *imageData,
                                                                        CGSize targetDimensions,
                                                                        UIViewContentMode targetContentMode,
                                                                        NSString * __nullable earlyGuessImageType) __attribute__((overloadable));
//! Convenience function to encode an image to a file
FOUNDATION_EXTERN BOOL TIPEncodeImageToFile(id<TIPImageCodec> codec,
                                            TIPImageContainer *imageContainer,
                                            NSString *filePath,
                                            TIPImageEncodingOptions options,
                                            float quality,
                                            BOOL atomic,
                                            NSError * __nullable * __nullable error);

NS_ASSUME_NONNULL_END
