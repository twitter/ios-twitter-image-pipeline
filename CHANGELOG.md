# Twitter Logging Service Change Log

## Info

**Document version:** 2.7.2

**Last updated:** 10/24/2017

**Author:** Nolan O'Brien

## History

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
