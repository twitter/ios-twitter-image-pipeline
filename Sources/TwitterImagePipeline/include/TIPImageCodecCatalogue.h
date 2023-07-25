//
//  TIPImageCodecCatalogue.h
//  TwitterImagePipeline
//
//  Created on 11/9/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TIPImageCodecs.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSDictionary<NSString *, id<TIPImageCodec>> * _Nullable (^TIPImageCodecCatalogueCodecsProvider)(void);

/**
 Catalogue of image codecs (encoder/decoder pairs)
 */
@interface TIPImageCodecCatalogue : NSObject

/**
 All the default codecs that come with __Twitter Image Pipeline__

 Warning: this method can block for a very long time. It is highly recommended you not use it from the main thread.
 */
+ (NSDictionary<NSString *, id<TIPImageCodec>> *)defaultCodecs;

/**
 Singleton accessor, defaults to having all `defaultCodecs` registered.
 */
+ (instancetype)sharedInstance;

/**
 Initialize with no codecs.
 */
- (instancetype)init;

/**
 Designated initializer
 @param codecs the dictionary of codecs by image type
 */
- (instancetype)initWithCodecs:(nullable NSDictionary<NSString *, id<TIPImageCodec>> *)codecs NS_DESIGNATED_INITIALIZER;

/**
 Designated initializer
 @param codecsProvider a block that returns the codecs by image type. Useful for avoiding pausing the calling thread while the codecs are built.
 */
- (instancetype)initWithCodecsProvider:(TIPImageCodecCatalogueCodecsProvider)codecsProvider NS_DESIGNATED_INITIALIZER;

/**
 All codecs in this catalogue
 */
@property (atomic, readonly) NSDictionary<NSString *, id<TIPImageCodec>> *allCodecs;

/**
 Retrieve the codec (or `nil`) for the specified _imageType_
 */
- (nullable id<TIPImageCodec>)codecForImageType:(NSString *)imageType;

/**
 set the codec for an image type
 @param codec the codec to set
 @param imageType the type of image
 */
- (void)setCodec:(id<TIPImageCodec>)codec forImageType:(NSString *)imageType;

/**
 Search the catalogue for a codec for the image type, and then invoke a block that may map it into a new one.

 It is very important that `replacementBlock` not call out to other `TIPImageCodecCatalogue` instance methods. Doing so
 will very likely cause a deadlock.

 @param imageType the type of image
 @param replacementBlock a block to map an existing codec (or `nil` if one was not found) into a replacement
 */
- (void)replaceCodecForImageType:(NSString *)imageType usingBlock:(id<TIPImageCodec> (^)(id<TIPImageCodec> _Nullable existingCodec))replacementBlock;

/**
 remove the codec for the given _imageType_
 */
- (void)removeCodecForImageType:(NSString *)imageType;
/**
 remove the given codec
 @param imageType the image type for the codec to remove
 @param codec if not set to `NULL`, will be populated with the codec that was removed (or `nil` if
 no codec was removed)
 */
- (void)removeCodecForImageType:(NSString *)imageType
                   removedCodec:(out id<TIPImageCodec> __nullable * __nullable)codec;

@end

/**
 Keyed subscripting support for codec catalogue
 */
@interface TIPImageCodecCatalogue (KeyedSubscripting)

/**
 `catalogue[imageType] = codec;`
 @param codec The `TIPImageCodec` to set.  `nil` will remove the value for the specified _key_.
 @param imageType The image type `NSString`
 __See Also:__ `setCodec:forImageType:`
 */
- (void)setObject:(nullable id<TIPImageCodec>)codec forKeyedSubscript:(NSString *)imageType;
/**
 `id<TIPImageTypeCodec> codec = catalogue[imageType]`
 @param imageType The image type `NSString` to look up
 @return the codec matching the _imageType_.  If not found, returns `nil`.
 */
- (nullable id<TIPImageCodec>)objectForKeyedSubscript:(NSString *)imageType;

@end

/**
 Convenience methods
 */
@interface TIPImageCodecCatalogue (Convenience)

/** Determine if the provided image type can be loaded progressively with _TIP_ */
- (BOOL)codecWithImageTypeSupportsProgressiveLoading:(nullable NSString *)type;
/** Determine if the provided image type can be loaded as an animated image with _TIP_ */
- (BOOL)codecWithImageTypeSupportsAnimation:(nullable NSString *)type;
/** Determine if the provided image type can be read/decoded into a `UIImage` by _TIP_ */
- (BOOL)codecWithImageTypeSupportsDecoding:(nullable NSString *)type;
/** Determine if the provided image type can be written/encoded from a `UIImage` by _TIP_ */
- (BOOL)codecWithImageTypeSupportsEncoding:(nullable NSString *)type;

/** Determine properties of the provided image type */
- (TIPImageCodecProperties)propertiesForCodecWithImageType:(nullable NSString *)type;

/** Convenience method to load an image via catalogue of codecs  */
- (nullable TIPImageContainer *)decodeImageWithData:(NSData *)data
                                   targetDimensions:(CGSize)targetDimensions
                                  targetContentMode:(UIViewContentMode)targetContentMode
                                   decoderConfigMap:(nullable NSDictionary<NSString *, id> *)decoderConfigMap
                                          imageType:(out NSString * __nullable * __nullable)imageType;

/** Convenience method to save an image to a file (_quality_ is between `0` and `1`) */
- (BOOL)encodeImage:(TIPImageContainer *)image
         toFilePath:(NSString *)filePath
      withImageType:(NSString *)imageType
            quality:(float)quality
            options:(TIPImageEncodingOptions)options
             atomic:(BOOL)atomic
              error:(out NSError * __nullable * __nullable)error;

/** Convenience method to encode an image to `NSData` (_quality_ is between `0` and `1`) */
- (nullable NSData *)encodeImage:(TIPImageContainer *)image
                   withImageType:(NSString *)imageType
                         quality:(float)quality
                         options:(TIPImageEncodingOptions)options
                           error:(out NSError * __nullable * __nullable)error;

@end

NS_ASSUME_NONNULL_END
