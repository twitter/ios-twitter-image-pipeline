# Twitter Image Pipeline Change Log

## Info

**Document version:** 2.25.01

**Last updated:** 07/25/2023

**Author:** Nolan O'Brien

## History

### 2.25.1 - Liam Nichols

- Support Swift Package Manager for distribution
- Update WebP dependency to 1.2.4 using XCFrameworks

### 2.25.0

- Fix codec detection for images that are not JPEG, PNG, GIF or BMP
  - In more recent versions of iOS, more image types require the complete image data to detect the image type instead of just the headers
    - This mostly just affects very small images, larger images generally were never affected
  - This regressed our codec detection logic for images that do not also have TIPs "magic numbers" image type detection
  - This fixes that by informing the codecs if the data being provided for detection is the complete image data or not
  - Caveat: for images other than JPEG, PNG, GIF, BMP or WEBP, it is likely that it will take the complete image data to detect those images now which can lengthen the duration for book-keeping overhead as the image is being loaded
    - If you want to have an image format detected faster than what Core Graphics detects (all data required for most formats), you can either provide a custom codec with better format detection logic or you can update the magic numbers APIs in `TIPImageTypes.m`

### 2.24.3

- Fix scaling logic to better preserve source size aspect ratio during scale
  - For example: 800x800 scaled to fill 954x954 would yield a 953x954 size.  Now it will properly yield 954x954.

### 2.24.2

- Fix WebP decoder for animations
  - Complex animations were not properly being decoded

### 2.24.1 - Liam Nichols

- Add MP4 and WebP subspecs for CocoaPods

### 2.24.0

- Drop iOS 8 and iOS 9 support

### 2.23.5

- Refactor WebP decoder to support animation decoding and improve efficiency
  - Requires _WebPDemux.framework_ for iOS (the Catalyst lib already has the necessary bits)
  - The `TIPXWebPCodec` also supports progressive loading (rendering the first frame while more data is loading)
    - This makes it potentially a better choice as a decoder than the iOS 14+ built in decoder, depending on your use case
  - Improve decoder to support having static _WebP_ images decode into the provided target sizing for better efficiency

### 2.23.2

- Update to WebP v1.1.0
  - Also fixes building WebP for Apple Silicon Catalyst builds

### 2.23.1

- Optimize the rendered cache unloading when `clearMemoryCachesOnApplicationBackgroundEnabled` is `YES`
  - When the app goes into the background, the rendered cache used to clear the oldest rendered images and just keep a max of 50% of the rendered cache capacity for when the app resumes
    - This was mostly effective for keeping the on screen images in cache avoiding any flashing UI, but had edge cases that could lead flashing or holding onto too much in memory that isn't needed for app resumes
  - Now, the rendered cache will turn each cache entry as _weak_ and on app resume, these _weak_ entries will be made strong again.
    - This will have the effect of all rendered cache images with no references being purged, but all those references being retained
    - Effectively, any UI that is holding the rendered images will keep those around for when the app resumes, making it seemless
    - For any UI that has unloaded its images when not visible, those images will be purged and will reload when the view becomes visible again
    - This works especially well with `TIPImageViewFetchHelper` when `disappearanceBehavior` is `TIPImageViewDisappearanceBehaviorUnload` or `TIPImageViewDisappearanceBehaviorReplaceWithPlaceholder`

### 2.23.0

- Replace `TIPImageFetchProgressiveLoadingPolicy` class methods with C functions
  - Swift does not like having an `@interface` have the same name as an `@protocol`
  - It can work, but gets very messy
  - Best to avoid it and replace the convenient class method interfaces in Objective-C with C functions
  - Though this is a minor version bump, it is API breaking
    - There isn't a way to deprecated the old APIs and introduce new ones, we just have to remove the old ones to fix usages in Swift
    - _Apologies for the inconvenience!_

### 2.22.0

- Add `TIPImageFetchSkipStoringToRenderedCache` to `TIPImageFetchOptions`
  - This permits a fetch to skip storing to the synchronous rendered cache altogether after a fetch
  - This is useful for UI that displays a large image but is not frequented regularly, such as a full screen image view
  - By avoiding infrequent images going to rendered cache, the rendered cache can keep more relevent images in cache (or can be configured to be smaller)
- Add `TIPImageViewDisappearanceBehaviorUnload` to `TIPImageViewDisappearanceBehavior`
  - This new behavior will set the `fetchView` image to `nil` on disappearance
  - This new feature can really level up an app at keeping a memory footprint down automatically, no extra work is needed when using `TIPImageViewFetchHelper` for displaying images!
- Add `TIPImageViewDisappearanceBehaviorReplaceWithPlaceholder` to `TIPImageViewDisappearanceBehavior`
  - This new behavior will set the `fetchView` image to a placeholder (low resolution) version on disappearance, which will be replace with the full image on visible return
  - Similar benefits to `TIPImageViewDisappearanceBehaviorUnload` but with the compromise of keeping a little more RAM for a placeholder to avoid UI situations that could yield an empty image view temporarily as the full image is decoded (notably for large images or slow devices)
- Rename `TIPImageViewFetchHelper` class' `fetchDisappearanceBehavior` to `disappearanceBehavior`
- Add `shouldTreatApplicationBackgroundAsViewDisappearance` property to `TIPImageViewFetchHelper`
  - This `BOOL` property will opt the fetch helper into using the disappearance behavior when the app backgrounds
  - Another big improvement for app memory footprint as the large amount of RAM used for images can be unloaded on app background, reducing the risk of the app being jettisoned!
  - Impact is really great for large images on screen when backgrounded, be sure to set to `YES` for your large image views!

### 2.21.5

- Adopt `direct` support for Objective-C code and eliminate `PRIVATE_SELF` C function pattern
  - Preserves Objective-C calling syntax for better code legibility (less C-style calls interleaving ObjC)
  - Safer than `PRIVATE_SELF` C functions (don't need to check `self != nil`)
  - Avoids awkward `self->_ivar` access in the direct methods (can stick with just using `_ivar`)
  - Same low binary overhead as private C functions

### 2.21.0

- Revise `TIPError.h` to be much more Swift compatible

### 2.20.5

- Revise _WebP_ support by adding _iOS 14_ decoder and integrating that with existing `TIPXWebPCodec`
  - Also means _Animated WebP_ are supported (decode only) on _iOS 14+_ now

### 2.20.0

- Fundamentally apply a rearchitecture to __Twitter Image Pipeline__
  - First: when loading images from data or files, the target sizing (dimensions & content mode) can now be used by codecs for more efficient decoding
    - This means that decoding a large image into a view port that is smaller can now decode directly into the appropriate size, reducing RAM and CPU of the decode AND avoiding needing to scale the image down before delivering the image as a result (more CPU savings)
    - This is implemented with the `ImageIO` based codecs, but not the extended codecs (`WebP` and `MP4`)...yet
  - Second: there are 3 caches in __TIP__: Rendered image cache, In Memory image cache, and On Disk image data cache.
    - The In Memory cache has been been restructured to cache the compressed image data instead of the image itself
    - This means:
      - Less RAM is needed for this middle cache
      - Less RAM is used when decoding the image to serve as a response
      - No more scaling the image from full size to the size to serve as a response (for core image codecs)
- Given how substantial this change is, we are bumping from version `2.13` to `2.20`
  - In particular, custom codecs will need to be updated to support the new `targetDimensions` and `targetContentMode` arguments

### 2.13.5

- Add _WebP_ support to Catalyst builds
  - See `WEBP_README.md`
- Miscellaneous performance improvements
  - Async load the default codes to avoid main thread blockage on app launch
  - Tighter memory management with autorelease pools
  - `TIPImageFetchHelper` will now register for all image cache updates and filter on observation vs registering against specific pipelines, which avoids register/unregister locking performance impact
  - Add `TIPDetectImageTypeFromFile(...)` for efficient and effective image type detection from a file
- Add replacements for `UIImagePNGRepresentation` and `UIImageJPEGRepresentation`
  - Unifies to the __TIP__ codec based encoding rather than the __UIKit__ implementation which can be unreliable for consistency.
  - Provides progressive support for JPEG variant of functionality.
  - See `-[UIImage tip_PNGRepresentation]` and `-[UIImage tip_JPEGRepresentationWithQuality:progressive:]`
- Add some palette based image utilities
  - `-[UIImage tip_canLosslesslyEncodeUsingIndexedPaletteWithOptions:]`
- Fix bug where a GIF load may be incomplete in response but complete in data loaded failing to load in __TIP__
  - Mostly an issue with some CDN vendors terminating the HTTP response incorrectly

### 2.13.2

- Add `[TIPGlobalConfiguration defaultInterpolationQuality]`
  - By default, will use `CGInterpolationQualityDefault` which is same behavior as before
  - Add quality arg to image scaling with `[UIImage tip_scaledImageWithTargetDimensions:contentMode:interpolationQuality:decode:]`

### 2.13.1

- Add `[TIPImageFetchDelegate tip_imageFetchOperation:didLoadDirtyPreviewImage:]` support
  - This allows for the rendered cache to mark a specific entry dirty (by identifier)
  - On fetch operation load, the dirty preview can be synchronously loaded while the op continues on async
  - This helps systems where a larger version of an image with a shared identifier loads and matching fetch helpers that are not visible in the UI take note in order to refresh with the better resolution image, but without the risk of clearing that image's render cache which can lead to a 1 or 2 frame "flash" of the image loading async from cache

### 2.13.0

- Separate out authentication support for image requests from hydration support
  - Hydration now just serves populating the image fetch's URL request
  - Authorization now serves to generate an _Authorization_ header's value to be applied as a separate step
  - Works better with multi step networking frameworks such as __TwitterNetworkLayer__
  - See `[TIPImageFetchRequest imageRequestAuthorizationBlock]`

### 2.12.2

- Add automatic handling of unnecessary image download errors when the download has finished loading
  - It is not uncommon for a service/CDN to yield an error after the final byte of the response has been loaded by the client
  - The consequence of treating a successful load as a failure is that upon next fetch for that image an unnessecary network request will trigger:
    - For image resumption supported loads, resumes the load beyond the available byte range
    - For full image loads, a redundant download
  - When TIP sees an error on image download but has all the bytes (looking at `Content-Length` header), TIP now posts `TIPProblemImageDownloadedWithUnnecessaryError` problem

### 2.12.1

- Fix bugs related to capping the sizes of caches
  - Capping a cache to `0` bytes would not completely disable it as documented, fixed
  - Setting the max ratio value to a negative value would not use the default value as documented, fixed
  - Thanks to @jml5qh for filing this issue (#41)

### 2.12.0

- Add `TIPImageTypeHEIC` and `TIPImageTypeAVCI` support
  - There are OS version limitations, see `TIPImageTypes.h` for details

### 2.11.1

- Update defaults in `TIPGlobalConfiguration` for cache sizes
  - `TIPMaxBytesForAllRenderedCachesDefault` and `TIPMaxBytesForAllMemoryCachesDefault`
    - the lesser of `System RAM / 12` or `160 MBs`
  - `TIPMaxCountForAllRenderedCachesDefault` and `TIPMaxCountForAllMemoryCachesDefault`
    - default cap to `255` instead of `511`

### 2.11.0

- add support for animated images with `TIPImageViewFetchHelper` by supporting `TIPImageContainer` as well as `UIImage`
  - to support animated images, implement a `UIView` that adopts `TIPImageFetchable` with `tip_fetchedImageContainer` that can animate the provided `TIPImageContainer`
  - update `TIPImageFetchable`
    - add `tip_fetchedImageContainer` as optional property
    - mark `tip_fetchedImage` as optional
    - require at least one of the two methods be implemented to conform to `TIPImageFetchable`
  - add helper functions:
    - `TIPImageFetchableHasImage`
    - `TIPImageFetchableGetImage` and `TIPImageFetchableGetImageContainer`
    - `TIPImageFetchableSetImage` and `TIPImageFetchableSetImageContainer`
  - update `TIPImageViewFetchHelper`
    - add `setImageContainerAsIfLoaded:`
    - add `setImageContainerAsIfPlaceholder:`
  - update `TIPImageViewFetchHelperDataSource`
    - add `tip_imageContainerForFetchHelper:`
  - update `TIPImageViewFetchHelperDelegate`
    - add `tip_fetchHelper:didUpdateDisplayedImageContainer:fromSourceDimensions:isFinal:`
    - deprecate `tip_fetchHelper:didUpdateDisplayedImage:fromSourceDimensions:isFinal:`
    - add `tip_fetchHelper:shouldReloadAfterDifferentFetchCompletedWithImageContainer:dimensions:identifier:URL:treatedAsPlaceholder:manuallyStored:`
    - deprecate `tip_fetchHelper:shouldReloadAfterDifferentFetchCompletedWithImage:dimensions:identifier:URL:treatedAsPlaceholder:manuallyStored:`

### 2.10.0

- drop support for iOS 7
  - the code had already diverged to requiring many iOS 8+ only APIs, this just makes it official

### 2.9.4 - Armand Raynor

- Fix MP4 decoder when decoding anamorphic mp4s into animations

### 2.9.3

- Add `notifyAllFetchHelpersToRetryFailedLoads` class method to `TIPImageViewFetchHelper`
  - This will offer an easy way for consuming apps to trigger a reload of failed image fetches when the network conditions change

### 2.9.2

- Add `TIPRenderImage` util function
- Add `tip_imageWithRenderFormattings:render:` method to `UIImage+TIPAdditions`

### 2.9.1

- Use modern `UIGraphicsImageRenderer` always when scaling images on iOS 10+
  - source the `UIGraphicsImageRendererFormat` from the image being scaled, this is optimal
  - roughly 10% speed boost
  - add _GraphicsRendererSpeed_ project that validates the perf differences

### 2.9.0

- Add P3 color gamut support
  - Image scaling preserves P3 (on device's with P3 screens) now
  - Add functions to check if a screen supports P3
  - Add category property to UIImage to check if image has P3 colorspace

### 2.8.1

- Persist source image dimensions for Rendered Cache
  - this provides more context about the source image, such as knowing if the displayed image was scaled up or scaled down
  - also added new "RMem" value when showing info with debug info feature on `TIPImageViewFetchHelper`
  - improve `TIPImageViewFetchHelper` when reloading an image after a new "matching" image was cached (such as a larger resolution)

### 2.8.0

- Move `TIPImageViewFetchHelper` from using `UIImageView` instances directly to using `UIView` with `TIPImageFetchable` protocol
  - makes it possible for  `UIView` subclasses to support the fetch helper, like `UIButton` or a custom view

### 2.7.2

- improve `TIPImageFetchTransformer` support with optional identifier
  - was easy to get the rendered cache images mixed up between transformed and non-transformed fetches
  - now, transform requests can only fetch images from the rendered cache if there is a match with the `tip_tranformerIdentifier`
  - transformers that don't provide an identifier cannot be cached nor retrieved from the rendered cache
- removed transformer from `TIPGlobalConfiguration` (would interfere with above improvement)

### 2.7.1

- add generic concrete class for `TIPImageFetchRequest` as convenience
  - generic fetch request is mutable/immutable pair: `TIPGenericImageFetchRequest` and `TIPMutableGenericImageFetchRequest`

### 2.7.0

- add decoder config support
  - enables custom TIPImageDecoder implementations to have configurable ways of being decoded
- add memory map loading option for images
  - default continues to not use memory map loading, but it's now exposed on TIPImageContainer
- add MP4 decoder to TIP (as an extended decoder, not bundled by default)
  - decodes MP4s as animated images

### 2.6.0

- Remove `TIPImageView`, just use `UIImageView` category instead
  - Add `hidden` property support to `UIImageView` fetch helper category
- Remove `TIPImageViewFetchHelper` subclassing event methods
  - Use delegate pattern for eventing instead of polymorphism #Simplify
- Remove `setViewHidden:` method for `TIPImageViewFetchHelper`
  - It never did what it was advertised to do and muddied the control flow
- Add `fetchResultDimensions` to `TIPImageViewFetchHelper` for more insight into results



### 2.5.0

- Remove detached downloads support for TIP image fetches
  - using HTTP/2 is the ideal solution, removing the complexity to remove the crutch

### 2.4.5

- reduce thread count for TIP by unifying all disk caches to using 1 manifest queue
  - make disk cache manifest load async instead of sync now that it is shared
  - no real speed improvements, just fewer threads need to be used in multi-pipeline apps
- clean up some large inline functions to be regular functions

### 2.4.4 - protosphere

- Fix WebP Encoder (channels could be mixed up)

### 2.4.3

- Update WebP codec to v0.6.0

### 2.4.2

- Add support for changing a cached image's identifier

### 2.4.1 - Brandon Carpenter

- Add category to `UIImageView` for setting a `TIPImageViewFetchHelper`
  - offers convenience of __TIP__ work encapsulated in `TIPImageViewFetchHelper` without needing to refactor onto `TIPImageView`

### 2.4.0

- Add image transform support to __TIP__
- A `TIPImageFetchTransform` can be set globally or on a specific request
- Clean up some nullability notation
- Update ImageSpeedComparison sample app
    - add WebP
    - add more bitrates
    - add optional blur transform (for progress)
    - add smaller PJPEG

### 2.3.0

- Reduce memory pressure w/ `@autoreleasepool` blocks on GCD queues in _TIP_
- Add "problem" for images not caching because they are too large
- Add "problem" when downloaded image cannot be decoded
- Add Animated PNG support (iOS 8+)
- Add the store operation as an argument to `TIPImagePipelineStoreCompletionBlock`
- Tightened up some threading race conditions that cropped up with the thread sanitizer

### 2.2.2

- Fix decoder bug on iOS 9 that prevented images from decoding

### 2.2.1

- Revise `TIPImageFetchViewHelper` to use delegate and data source pattern, like `UITableView` and `UIPickerView` do.
  - Less fiddly with simpler touch points by implementing the delegate and/or data source.
- Added a sample application that uses the Twitter API.

### 2.2.0

- Refactor `TIPImageFetchOperation` and `TIPImageFetchDelegate` to use an encapsulated `TIPImageFetchResult`
  - Gives us a consistent interface for preview, progressive and final image results

### 2.1.0

- Add support for "placeholder" images
  - This offers a way to contextually "flag" certain images as "less valuable" that full images
  - Consider a black and white preview of a full color image, that could be flagged as a "placeholder"
- Cap caches to have a max number of images too

### 2.0.0

- __TwitterImagePipeline__ now supports pluggable image decoding and encoding w/ `TIPImageCodecs.h`
  - `TIPImageCodecCatalogue` exists to encapsulate the set of known codecs for TIP to use
  - The default codecs are all those included by iOS
  - WebP codec is used in the unit tests, but does not come bundled with TIP as a default
    - Consumers of TIP can use the WebP codec in their projects if they want to use it

### 1.16.1 - Jeff Holliday

- By default, process entries from the disk image cache manifest in parallel, reducing manifest load time by 25-50%

### 1.16.0

- Properly prefix methods in __TwitterImagePipeline__ with `tip_` prefix

### 1.15.1

- Remove `forceUITraitCollectionToSynchronizeConstruction` property from `TIPGlobalConfiguration`
- _TIP_ will now always force the synchronization fix on iOS 8 & 9

### 1.15.0

- Move many image helper functions into `UIImage(TIPAdditions)` category
- For some methods, add error output
- Rename remaining helper functions to have better names and drop the "Image" prefix

### 1.14.0

- Abstract out the networking of __TIP__ via the `TIPImageFetchDownload` protocol in `TIPImageFetchDownload.h`
- This permits __TIP__ to have it's own basic implementation but also frees consumers to plug in whatever networking layer they prefer instead.  Twitter uses the protocol to plug in it's own __Twitter Network Layer__ framework.
- Plugging in a custom `TIPImageFetchDownload` is done via the `imageFetchDownloadClass` property on `TIPGlobalConfiguration`.
- The default __TIP__ `TIPImageFetchDownload` implementation is just a thin wrapper on `NSURLSession`.

### 1.13.0

- Refactor __TIP__ to use `NSString` representations for image types instead of `TIPImageType`

### 1.12.1

- Restructure __TIP__.  No code/interface changes, just project layout and code moving between files.

### 1.12.0

- Add swizzling to mitigate crash in Apple's `UIImage`.
- `UIImage` is thread safe _except_ with image creation (Apple bugs #27141588 and #26954460) which creates a `UITraitCollection` that has a race condition that leads to overrelease.
- Following same pattern as Peter Steinberger to mitigate the issue: https://pspdfkit.com/blog/2016/investigating-thread-saftey-of-UIImage/
- Swizzle `[UITraitCollection traitCollectionWithDisplayScale:]` to use a mutex for thread safety
- Swizzling is opt-in via `TIPGlobalConfiguration.forceUITraitCollectionToSynchronizeConstruction`
- This issue definitely exists on iOS 9, but it might have been fixed on iOS 10.  iOS 10 is in beta a.t.m. so we'll need to wait until we can validate in production.

### 1.11.0 - Brandon Carpenter

- Update the API to be more Swift-friendly
- Value accessors in TIPImageFetchRequest and TIPImageStoreRequest are now defined as read-only properties, rather than as methods.
- Moves TIPImageFetchLoadingSourcesNone out of the TIPImageFetchLoadingSources NS_OPTIONS and defines it as a constant instead so that it does not break Swift's automatic prefix stripping for the rest of the values.

### 1.10.0

- Create `TIPImageViewFetchHelper` to encapsulate reusable fetch behavior for an Image View
- With given *glue methods*, a fetch helper can dynamically update the fetch request to target the desired image view's constraints.
- By subclassing, a custom fetch helper can add additional concrete utility such as auto-selecting the best URL for a fetch based on the constraints of the target image view.
- Encapsulate `TIPImageViewFetchHelper` in a `TIPImageView` for convenience

### 1.9.0

- Remove Twitter specific logging framework dependency and expose hooks to provide any desired logger

### 1.8.1

- Increase metadata of network downloaded images
- Support multiple global TIP observers instead of just one

### 1.8.0

- Rework `TIPImageFetchDelegate` to be weakly held and cancel its operation(s) on dealloc

### 1.7.2

- Add support for capping the size of an entry in the caches
- `[TIPGlobalConfiguration maxRatioSizeOfCacheEntry]`

### 1.7.1

- Add `imageFetchOperation:willAttemptToLoadFromSource:` to `TIPImageFetchDelegate`

### 1.7.0

- Provide extensibility to `TIPImageStoreRequest` by offering ability to provide a `TIPImageStoreRequestHydrater`.
- The hydrater can be used to extend the work that executes for an image store operation.
- Useful for asynchronously loading the image from a PhotoKit
-    or asynchronously tranforming or modifying the image to be cached.
- Expose the underlying `NSOperation` for the image store operation so that it can be used in dependency chains (but as a `TIPDependencyOperation`)
- Useful for preventing a fetch operation from starting until a related store operation completes
- Offers being made a dependency, being waited on until finished, and Key-Value-Observing when it finishes or transitions to/from executing
- Does not offer mutability of the operation: that includes cancelling, prioritization or applying dependencies
- Increase versatility of `TIPImageStoreRequest` by permitting a request to have both a data representation (`NSData` or `NSString` file path) and a `UIImage` representation.
- This provides a single action that applies a `UIImage` to the memory cache and the data representation to the disk cache so that if the caller already made these expensive serializations/deserializations, they needn't be duplicated by the image pipeline during storage.
- Previous behavior is in tact so if only one image representation is provided, it will be accurately converted to the right formats for the appropriate caches.

### 1.6.4

- provide load source when a progressive frame is loaded or the first frame of an animated image is loaded

### 1.6.3

- Optimize TIP for when a TIPImageFetchOperation over HTTP/1.1 is cancelled
- When an op is cancelled and the underlying download would have no more delegates do the following:
- If the download is known to be going over SPDY or HTTP/2 (not always easy to detect), cancel the download
- If there is less than 1 KB of data left to download, continue as a "detached" download
- If there is less than 3 seconds of estimated time remaining, continue as a "detached" download
- Otherwise, just as before, cancel the download
- As a "detached" download receives more data; if the download slows down too much, cancel the download
- When a "detached" download completes, don't decode the image.  Just store it to the disk cache.
- This optimization is particularly valuable on HTTP/1.1 (vs SPDY or HTTP/2) since it prevents connections from being closed and having to build up a new connection for subsequent image downloads

### 1.6.2

- Share max concurrent operations across all image pipelines

### 1.6.1

- Add method to TIPImagePipeline to get a copy of the on disk cache file for an image entry

### 1.6.0

- Add TIPGlobalConfiguration
- Share cache max bytes across all caches

### 1.5.0

- Encapsulate images fetched by TIP in a `TIPImageContainer` so that additional meta data can be maintained
- Currently, additiona meta data is loop count and frame durations for animated images (GIFs)

### 1.4.0

- Add preliminary support for progressive JPEG-2000
- Still not ready and disabled in code
- Have progressive loading policy split into progressive loading policies so that a policy can be specified per `TIPImageType`
- This will allow us to hone our policy for JPEG-2000 separately from PJPEG

### 1.3.1

- Fix bug in Progressive Loading logic for PJPEG (could skip scans by mistake)
- Update unit tests

### 1.3.0

- Add support for GIFs
- Animated GIFs will automatically be supported and retrieved as `UIImage`s with `images` property
populated with the animated frames.  Adding an animated `UIImage` to a `UIImageView` will automatically animate.
- `TIPImageFetchDelegate` now has a method to optionally have the first frame of an animated image loaded while the remainder of the animated image loads
- `[TIPImageFetchDelegate tip_imageFetchOperation:didLoadFirstAnimatedImageFrame:progress:]`

### 1.2.5

- Add TIPImageFetchMetrics for encapsulating the information related to an image fetch

### 1.2.1

- Provide ability to inspect TIPImagePipeline (info on all the entries in each cache)
- Provide mechanism to clear memory and/or disk caches specifically (usefull for debugging)

### 1.2.0

- Split up image fetches into two methods: 1) for constructing the operation and 2) for starting the operation
- Add ability to discard the delegate of a `TIPImageFetchOperation`
- Increase sanitization of image identifiers loaded from disk that were hashed (under the covers, so a transparent increase in robustness)

### 1.1.1

- Detect invalid requests and elicit an appropriate error when encountered

### 1.1.0

- Add `TIPImagePipelineObserver`

### 1.0.0 (04/21/2015)

- Initial release
