//
//  TIPImageContainer.h
//  TwitterImagePipeline
//
//  Created on 10/8/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <ImageIO/CGImageSource.h>
#import <TIPImageUtils.h>
#import <UIKit/UIImage.h>
#import <UIKit/UIView.h>

@class TIPImageCodecCatalogue;

NS_ASSUME_NONNULL_BEGIN

/**
 `TIPImageContainer` encapsulates a `UIImage` and any relevant meta-data for that image.
 For now, animated images (specifically GIF) can have additional info related to animation which
 `UIImage` doesn't offer.
 */
@interface TIPImageContainer : NSObject

#pragma mark Properties

/** The `UIImage` being encapsulated by the container */
@property (nonatomic, readonly) UIImage *image;
/**
 `YES` if the _image_ is animated.
 See `TIPImageContainer(Animated)` for more.
 */
@property (nonatomic, readonly, getter=isAnimated) BOOL animated;
/**
 An opaque descriptor object encapsulating info about this `TIPImageContainer` w/o the large `UIImage`.
 Can be used to create a new `TIPImageContainer` along with the matching `UIImage` using `[TIPImageContainer imageContainerWithImage:descriptor:]`.
 */
@property (nonatomic, readonly) id descriptor;

#pragma mark Initialization

/**
 Initializer to create a `TIPImageContainer` with a specified image.
 Can end up being an animated or static image.
 @param image the `UIImage` to encapsulate
 @return The image container encapsulating the specified _image_.
 */
- (instancetype)initWithImage:(UIImage *)image;

/** `NS_UNAVAILABLE` */
- (instancetype)init NS_UNAVAILABLE;
/** `NS_UNAVAILABLE` */
+ (instancetype)new NS_UNAVAILABLE;

@end

/**
 Interface for methods/properties related to animated image containers
 */
@interface TIPImageContainer (Animated)

#pragma mark Properties

/** Number of loops in the animation.  `0` indicates _loop forever_. */
@property (nonatomic, readonly) NSUInteger loopCount;
/** Number of frames in the animation. */
@property (nonatomic, readonly) NSUInteger frameCount;
/**
 All the frames of the animation (as `UIImage` objects).
 This array will have the same count as _frameCount_.
 */
@property (nonatomic, readonly, nullable) NSArray<UIImage *> *frames;
/**
 The durations paired to each frame.  Durations are `NSNumber` objects wrapping `float` values.
 This array will have the same count as _frameCount_.
 */
@property (nonatomic, readonly, nullable) NSArray<NSNumber *> *frameDurations;

#pragma mark Initialization

/**
 Initializer to create a `TIPImageContainer` with a specified animated image.
 As the name indicates, this initializer expects an animated image with _animation_ arguments,
 but the resulting `TIPImageContainer` can still be a static image based on the _image_ passed in.
 @param image the `UIImage` to encapsulate
 @param loopCount the number of loops for the animation
 @param durations the durations for each frame of the animation.
 If `nil` or count doesn't match the frames of _image_, `frameDurations` will fall back to being
 calculated off of `[UIImage duration]`.
 @return The image container encapsulating the specified _image_.
 */
- (instancetype)initWithAnimatedImage:(UIImage *)image
                            loopCount:(NSUInteger)loopCount
                       frameDurations:(nullable NSArray<NSNumber *> *)durations;

#pragma mark Methods

/**
 Access a specific frame by index.
 @param index The index of the frame to grab
 @return the `UIImage` of the frame, or `nil` if _index_ is out of bounds
 */
- (nullable UIImage *)frameAtIndex:(NSUInteger)index;
/**
 Access a specific frame's duration by index.
 @param index The index of the frame's duration to grab
 @return the time interval for the frame at _index_ or `0.0` if the _index_ is out of bounds.
 */
- (NSTimeInterval)frameDurationAtIndex:(NSUInteger)index;

@end

/**
 `TIPImageContainer(Convenience)` offers additional convenience methods to `TIPImageContainer`.
 */
@interface TIPImageContainer (Convenience)

#pragma mark Constructors

/**
 Convenience constructor.
 @param image the `UIImage` to encapsulate
 @param descriptor the matching descriptor (sourced from a `TIPImageContainer` with the same _image_)
 @return image container encapsulating the desired image, or `nil` if the _descriptor_ and _image_ are incompatible
 */
+ (nullable instancetype)imageContainerWithImage:(UIImage *)image descriptor:(id)descriptor;

/**
 Convenience constructor.
 @param imageSource the `CGImageSourceRef` to read in as a `UIImage` and encapsulate
 @param targetDimensions the dimension sizing constraints to decode the image into (`CGSizeZero` for full size)
 @param targetContentMode the content mode sizing constraints to decode the image into (any non-scaling mode for full size)
 @return image container encapsulating the desired image, or `nil` if the image could not be loaded
 @note unlike the other `TIPImageContainer` convenience constructor methods, this method
 does NOT load via a `TIPImageCodecCatalogue`.
 */
+ (nullable instancetype)imageContainerWithImageSource:(CGImageSourceRef)imageSource
                                      targetDimensions:(CGSize)targetDimensions
                                     targetContentMode:(UIViewContentMode)targetContentMode;
+ (nullable instancetype)imageContainerWithImageSource:(CGImageSourceRef)imageSource;

/**
 Convenience constructor.
 @param data the `NSData` to load as a `UIImage` and encapsulate
 @param targetDimensions the dimension sizing constraints to decode the image into (`CGSizeZero` for full size)
 @param targetContentMode the content mode sizing constraints to decode the image into (any non-scaling mode for full size)
 @param decoderConfigMap an optional dictionary of opaque config objects for the decoder to use (config will be matched by the decoder's image type string), passing `nil` is always fine
 @param catalogue the catalogue of codecs to load with, pass `nil` to use
 `[TIPImageCodecCatalogue sharedInstance]`
 @return image container encapsulating the desired image, or `nil` if the image could not be loaded
 */
+ (nullable instancetype)imageContainerWithData:(NSData *)data
                               targetDimensions:(CGSize)targetDimensions
                              targetContentMode:(UIViewContentMode)targetContentMode
                               decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
                                 codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue;
+ (nullable instancetype)imageContainerWithData:(NSData *)data
                               decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
                                 codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue;

/**
 Convenience constructor.
 @param filePath the file path to load as a `UIImage` and encpasulate
 @param targetDimensions the dimension sizing constraints to decode the image into (`CGSizeZero` for full size)
 @param targetContentMode the content mode sizing constraints to decode the image into (any non-scaling mode for full size)
 @param decoderConfigMap an optional dictionary of opaque config objects for the decoder to use (config will be matched by the decoder's image type string), passing `nil` is always fine
 @param catalogue the catalogue of codecs to load with, pass `nil` to use
 `[TIPImageCodecCatalogue sharedInstance]`
 @param map `YES` to load the image data via memory map, `NO` (default) to load the image data into memory
 @return image container encapsulating the desired image, or `nil` if the image could not be loaded
 @warning Loading with memory mapped file is very fragile. Modification/move/deletion and even high velocity reading of the underlying file (at that path) can yield a crash or corruption. Take care to only provide `YES` for _map_ if you are very confident in the approach.
 */
+ (nullable instancetype)imageContainerWithFilePath:(NSString *)filePath
                                   targetDimensions:(CGSize)targetDimensions
                                  targetContentMode:(UIViewContentMode)targetContentMode
                                   decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
                                     codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
                                          memoryMap:(BOOL)map;
+ (nullable instancetype)imageContainerWithFilePath:(NSString *)filePath
                                   decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
                                     codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
                                          memoryMap:(BOOL)map;

/**
 Convenience constructor.
 @param fileURL the file path `NSURL` to load as a `UIImage` and encpasulate
 @param targetDimensions the dimension sizing constraints to decode the image into (`CGSizeZero` for full size)
 @param targetContentMode the content mode sizing constraints to decode the image into (any non-scaling mode for full size)
 @param decoderConfigMap an optional dictionary of opaque config objects for the decoder to use (config will be matched by the decoder's image type string), passing `nil` is always fine
 @param catalogue the catalogue of codecs to load with, pass `nil` to use
 `[TIPImageCodecCatalogue sharedInstance]`
 @param map `YES` to load the image data via memory map, `NO` (default) to load the image data into memory
 @return image container encapsulating the desired image, or `nil` if the image could not be loaded
 @warning Loading with memory mapped file is very fragile. Modification/move/deletion and even high velocity reading of the underlying file (at that path) can yield a crash or corruption. Take care to only provide `YES` for _map_ if you are very confident in the approach.
 */
+ (nullable instancetype)imageContainerWithFileURL:(NSURL *)fileURL
                                  targetDimensions:(CGSize)targetDimensions
                                 targetContentMode:(UIViewContentMode)targetContentMode
                                  decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
                                    codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
                                         memoryMap:(BOOL)map;
+ (nullable instancetype)imageContainerWithFileURL:(NSURL *)fileURL
                                  decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
                                    codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
                                         memoryMap:(BOOL)map;

#pragma mark Inferred Properties

/** the size, in bytes, the encapsulated image takes up in memory */
@property (nonatomic, readonly) NSUInteger sizeInMemory;
/** the dimensions, in pixels (not points), of the encapsulated image */
@property (nonatomic, readonly) CGSize dimensions;
/** the size, in points (not pixels), of the encapsulated image */
@property (nonatomic, readonly) CGSize pointSize;

#pragma mark Methods

/** synchronously decode the encapsulated image */
- (void)decode;

/**
 Scale the encapsulated image to a new `TIPImageContainer`
 @param dimensions the target dimensions (in pixels) to scale to
 @param contentMode the target content mode to scale with
 @return the new `TIPImageContainer` encapsulated the scaled image, `nil` in the extreme case that
 the scaling failed (super exceptional case).
 */
- (nullable TIPImageContainer *)scaleToTargetDimensions:(CGSize)dimensions
                                            contentMode:(UIViewContentMode)contentMode;

/**
 Save the encapsulated image to disk
 @param path the file path to save the image to
 @param type the _TIPImageType_ to save as
 @param catalogue the catalogue of codecs to load with, pass `nil` for the `sharedInstance`
 @param options the `TIPImageEncodingOptions` to save with
 @param quality the quality (`0.0` to `1.0`) to save lossy images as, if _type_ supports lossy
 @param atomic whether or not to atomically write the image to disk
 @param error set if an error was encountered
 @return `YES` on success, `NO` on failure
 */
- (BOOL)saveToFilePath:(NSString *)path
                  type:(nullable NSString *)type
        codecCatalogue:(nullable TIPImageCodecCatalogue *)catalogue
               options:(TIPImageEncodingOptions)options
               quality:(float)quality
                atomic:(BOOL)atomic
                 error:(out NSError * __nullable * __nullable)error;

@end

NS_ASSUME_NONNULL_END
