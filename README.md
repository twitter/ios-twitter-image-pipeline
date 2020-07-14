# Twitter Image Pipeline (a.k.a. TIP)

## Background

The __Twitter Image Pipeline__ is a streamlined framework for _fetching_ and
_storing_ images in an application.  The high level concept is that all
requests to fetch or store an image go through an _image pipeline_ which
encapsulates the work of checking the _in memory caches_ and an _on disk
cache_ before retrieving the image from over the _network_ as well as
keeping the caches both up to date and pruned.

## Goals and Requirements

_Twitter Image Pipeline_ came to fruition as numerous needs rose out of
Twitter for iOS use cases.  The system for image loading prior to TIP was
fragile and inefficient with some severe edge cases.  Designing a new
framework from the ground up to holistically approach the need for loading
images was the best route and led to *TIP*.

- Progressive image loading support (Progressive JPEG)
  - PJPEG can render progressive scans with a fraction of the bytes needed for the full image
  - Users can see a 35% to 65% improvement in how soon an image is visible (occasionally even better)
  - PJPEG images happen to be 10% smaller (on average) than their non-progressive counterparts
  - PJPEG is hardware decodable on iOS devices, just like non-progressive JPEG images
- Resumable download support
  - If an image load is terminated (via failure or cancellation) when an image is partially loaded, the next load of that image should resume from where it left off saving on bytes needing to be transferred
  - Has a compounding benefit with Progressive JPEG as resuming an image that is partially loaded can render to screen with a progressive scan immediately while remaining bytes can be loaded to improve the quality
- Support programmatically/manually storing images to the cache(s)
  - By being able to store images to the underlying cache(s), cases where images are uploaded can have those images in cache at the right location without having to make a fetch.  (Ex// Post a Tweet with an image, that image can be stored to the cache before it is ever seen in the timeline making the timeline's fetch of that image immediate and avoids hitting the network.)
- Support vending a larger variant when a smaller variant is fetched
  - By maintaining the largest variant in cache, we can merely scale the image (in the background) and vend that image instead of hitting the network
- Support vending a smaller variant when a larger variant is fetched
  - When fetching a larger variant of an image when a smaller variant is in the cache, the smaller variant should be optionally be consumable as the larger variant is loaded over the network
  - This improves the user experience by providing an image at lower quality while loading the higher quality variant instead of just having an empty/blank UI or placeholder
- Asynchronous architecture
  - Using requests to encapsulate _what_ to load, using an operation for executing the asynchronous work, and having a delegate for callbacks we can provide a strong and scalable pattern for image loading
- Cancellable fetches
  - When an image fetch is no longer relevant (such as navigating away from an image that hasn't finished loading), we should be permitted to cancel fetches
  - HTTP/1.1 based fetch downloads that are cancelled will have the negative side effect of tearing down that TCP connection which is expensive to re-establish at the tradeoff of saving on bandwidth and unnecessary network contention with other network requests
  - HTTP/2 (or SPDY) based fetch downloads will have no negative side effects since the protocol supports midstream cancellation without impacting overall network performance
- Fast access to cached images
  - Having the fetch synchronously load already scaled and cached images will keep the UI smooth by avoiding lapses when the image is immediately available
- Background rendering/scaling/decoding of fetched images
  - Fetched images need to be decoded and often scaled and even rendered, doing so on a background thread will eliminate framerate drops from trying to do the same expensive work from the main thread
- Segregated caches / pipelines
  - By having caches support being segregated, the Twitter app can utilize this segregation to keep caches separate per user account.  On account removal, that account's cache can be cleared without affecting other account caches.
- Image fetch hydration support
  - Certain image fetches will require the fetch to sign the request to be loaded over the network, having support for a hydration step will enable this with "pull" based pattern vs a "push" based pattern that would require applying any such request construct up front.
- Support for custom networking to execute the downloading of images.
  - Twitter has strict requirements to have all networking go through its network layer and as such *TIP* has abstracted out networking so that any network layer can be plugged in via the abstraction interface for downloads.
  - An NSURLSession based download plugin is used by default, but consumers can plug in whatever network layer they desire.
- Support any image codec desired
  - By default, all ImageIO supported image types are supported
  - A plugin architecture supports custom codecs for encoding and/or decoding images in TIP
  - Use cases include WebP support, or any custom decoding support such as JPEG decoding with a shared quantization table and/or header, or even applying some visual transform (like a blur) as a part of the rendering

## Architecture

### Caches

There are 3 separate caches for each _image pipeline_: the rendered
in-memory cache, the in-memory cache, and the on-disk cache.  Entries in the
caches are keyed by an _image identifier_ which is provided by the creator of
the fetch request or automatically generated from the image fetch's URL.

- The _On-Disk Cache_ will maintain both the latest partial image and the largest completed image for an _image identifier_
- The _In-Memory Cache_ will maintain the largest matching UIImage (based on the image identifier), but has no bias to the image being rendered/decoded or not
- The _Rendered In-Memory Cache_ will maintain the 3 most recently sized and rendered/decoded UIImages that match (based on the image identifier)

The image will simultaneously be loaded into memory (as raw bytes) and
written to the disk cache when retrieving from the Network.  Partial images
will be persisted as well and not replace any completed images in the cache.

Once the image is either retrieved from any of the caches or the
network, the retrieved image will percolate back through the caches in its
various forms.

Caches will be configurable at a global level to have maximum size.  This
maximum will be enforced across all image pipeline cache's of the same kind,
and be maintained with the combination of time-to-live (TTL) expiration and
least-recently-used (LRU) purging.  (This solves the long standing issue for
the Twitter iOS app of having an unbounded cache that could consume
Gigabytes of disk space).


### Execution

The architecture behind the fetch operation is rather straightforward and
streamlined into a pipeline (hence, "_image pipeline_").

When the request is made, the fetch operation will perform the following:

- Synchronously consult the _Rendered In-Memory Cache_ for an image that will fit the target dimensions and content mode.
- On miss, asynchronously consult the _In-Memory Cache_ that maintains the UIImage of the largest matching image (based on identifier).
- On miss, asynchronously consult the _On-Disk Cache_ that maintains the raw bytes of the largest matching image (based on identifier).  As an optimization, *TIP* will take it a step further and also consult all other registered _pipeline disk caches_ - thus saving on the cost of network load by pulling from disk. The cross pipeline retrieved image will be stored to the fetching pipeline's caches to maintain image pipeline siloing.  _Note:_ this cross pipeline access requires the fetching image identifier and image URL to match.
- On miss, asynchronously consult any provided _additional caches_ (based on URL).  This is so that legacy caches can be pulled from when transitioning to *TIP* without having to forcibly load all assets again.
- On miss, asynchronously retrieve the image from the _Network_, resuming any partially loaded data that may exist in the _On-Disk Cache_.

### Preview Support

In addition to this simple progression, the fetch operation will offer the first matching
(based on image identifier) complete image in the In-Memory Cache or On-Disk Cache
(rendered and resized to the request's specified target sizing) as a preview image when the URLs
don't match.  At that point, the fetch delegate can choose to just use the preview image or continue
with the _Network_ loading the final image.  This is particularly useful when the fetch image URL is
for a smaller image than the image in cache, no need to hit the network :)

### Progressive Support

A great value that the _image pipeline_ offers is the ability to stream progressive scans of an
image, if it is PJPEG, as the image is loaded from the Network.  This progressive rendering is
natively supported by iOS 8+, the same minimum OS for *TIP*.
Progressive support is opt-in and also configurable in how scans should load.

### Resuming Image Downloads

As already mentioned, by persisting the partial load of an image to the _On-Disk Cache_, we are able
to support resumable downloads.  This requires no interface either, it's just a part of how the
image pipeline works.

## Twitter Image Pipeline features

- Fetching
    - Progress reporting
    - Customizable progressive loading policies
    - Preview loading with option to avoid continuing to load
    - Placeholder support (for non-canonical images that get purged)
    - Automatic scaling to target view's size
    - Custom caching uptions
    - Customizable set of loading sources (caches and network)
    - NSOperation based
        - Cancellable
        - Priority support
        - Dependency chain support
    - Delegate pattern (for robust support)
    - Block callback pattern (for simple use cases)
- Storing
    - Manual storage support (UIImage, NSData or file on disk)
    - Manual purging support
    - Dependency chain support (like NSOperation)
- Caching
    - Synchronous/fast cache for rendered images
    - Async memory cache for images
    - Async disk cache for images
    - Automatic LRU purging
    - Automatic TTL purging
    - Siloed caches (via multiple `TIPImagePipeline` instances)
    - Support for loading from additional non-TIP caches (helps with migration)
    - Expose method to copy disk cache images directly
- Downloads
    - Coalescing image downloads
    - Image download resumption support built in
        - Image response "Accept-Ranges" must be "bytes" and have "Last-Modified" header
        - Uses "Range" and "If-Range" headers to specify continuation
    - Pluggable networking (use your own network layer)
        - Check out how to integrate [Twitter Network Layer](https://github.com/twitter/ios-twitter-network-layer) as your pluggable downloader with this [gist](https://gist.github.com/NSProgrammer/6e4c93ca9b9518178c9cbc7d950efd9c)
    - Custom hydration (useful for authenticated fetches)
- Detailed insights
    - Global pipeline observability
    - Individual pipeline observability
    - Global problem observability (non-fatal problems for monitoring)
    - Asserts can be enabled/disabled
    - Pluggable logging
    - Inspectable (can inspect each pipeline's entries)
    - Robust errors
    - Detailed metrics on fetch operation completion
- Robust image support
    - Pluggable codecs (can add WebP or other image codecs)
    - Can serialize access to CGContext
    - UIImage convenience methods
    - Animated image support (GIFs, by default)
- UIKit integration
    - Dedicated helper object decoupling logic from views w/ `TIPImageViewFetchHelper`
    - Fetch helper offers useful fetch behavior encapsulation
    - Debug overlay feature to see debug details of the image view
    - `UIImageView` category for convenient pairing with a `TIPImageViewFetchHelper`
- Configurable
    - caches sizes (both in bytes and image count)
    - max cache entry size
    - max time for detached download
    - max concurrent downloads


## Components of the Twitter Image Pipeline

- `TIPGlobalConfiguration`
  - The global configuration for *TIP*
  - Configure/modify this configuration to adjust *TIP* behavior for your needs
- `TIPImagePipeline`
  - the pipeline for fetching images from and storing images to
  - multiple pipelines can exist providing segregation by use case
  - a fetch operation is constructed by providing a _request_ (`TIPImageFetchRequest`) with a delegate (`TIPImageFetchDelegate`) or completion block (`TIPImagePipelineFetchCompletionBlock`) to a desired pipeline.  The operation can then be provided to that same pipeline to start the fetching.  This two step approach is necessary to support both synchronous and asynchronous loading while incurring minimal burden on the developer.
- `TIPImageFetchRequest`
  - the protocol that encapsulates the information necessary for retrieving an image
- `TIPImageFetchDelegate`
  - the delegate for dealing with dynamic decisions and event callbacks
- `TIPImageFetchOperation`
  - the `NSOperation` that executes the request and provides a handle to the operation
  - the operation maintains the state of the fetch's progress as it executes
  - the operation offers several features:
    - cancelability
    - dependency support
    - prioritization (can be mutated at any time)
    - a unique reference for distinguishing between operations
- `TIPImageStoreRequest`
  - the protocol that encapsulates the information necessary for programmatically storing an image
- `TIPImageContainer`
  - object to encapsulate the relevant info for a fetched image
  - the `TIPImageFetchDelegate` will use `TIPImageContainer` instances for callbacks, and the `TIPImageFetchOperation` will maintain `TIPImageFetchOperation` properties as it progresses.
- `TIPImageViewFetchHelper`
  - powerful class that can encapsulate the majority of use cases for loading an image and displaying it in a `UIImageView`
  - 99% of image loading and displaying use cases can be solved by using this class, configuring it and providing a delegate and/or data source
  - having the logic in this class avoid coupling _controller_ code with _view_ code in the _MVC_ practice
- `UIView(TIPImageFetchable)` and `UIImageView(TIPImageFetchable)`
  - convenience categories on `UIImageView` and `UIView` for associating a `TIPImageViewFetchHelper`

## Usage

The simplest way to use *TIP* is with the `TIPImageViewHelper` counterpart.

For concrete coding samples, look at the *TIP Sample App* and *TIP Swift Sample App* (in Objective-C and Swift, respectively).

Here's a simple example of using *TIP* with a `UIViewController` that has an array of image views to
populate with images.

```objc

    /* category on TIPImagePipeline */

    + (TIPImagePipeline *)my_imagePipeline
    {
        static TIPImagePipeline *sPipeline;
        static dispatch_once_t sOnceToken;
        dispatch_once(&sOnceToken, ^{
            sPipeline = [[TIPImagePipeline alloc] initWithIdentifier:@"com.my.app.image.pipeline"];

            // support looking in legacy cache before hitting the network
            sPipeline.additionalCaches = @[ [MyLegacyCache sharedInstance] ];
        });
        return sPipeline;
    }

    // ...

    /* in a UIViewController */

    - (void)viewDidLayoutSubviews
    {
        [super viewDidLayoutSubviews];

        if (nil == self.view.window) {
            // not visible
            return;
        }

        [_imageFetchOperations makeAllObjectsPerformSelector:@selector(cancelAndDiscardDelegate)];
        [_imageFetchOperations removeAllObjects];

        TIPImagePipeline *pipeline = [TIPImagePipeline my_imagePipeline];
        for (NSInteger imageIndex = 0; imageIndex < self.imageViewCount; imageIndex++) {
            UIImageView *imageView = _imageView[imageIndex];
            imageView.image = nil;
            id<TIPImageFetchRequest> request = [self _my_imageFetchRequestForIndex:imageIndex];

            TIPImageFetchOperation *op = [pipeline operationWithRequest:request context:@(imageIndex) delegate:self];

            // fetch can complete sync or async, so we need to hold the reference BEFORE
            // triggering the fetch (in case it completes sync and will clear the ref)
            [_imageFetchOperations addObject:op];
            [[TIPImagePipeline my_imagePipeline] fetchImageWithOperation:op];
        }
    }

    - (id<TIPImageFetchRequest>)_my_imageFetchRequestForIndex:(NSInteger)index
    {
        NSAssert(index < self.imageViewCount);

        UIImageView *imageView = _imageViews[index];
        MyImageModel *model = _imageModels[index];

        MyImageFetchRequest *request = [[MyImageFetchRequest alloc] init];
        request.imageURL = model.thumbnailImageURL;
        request.imageIdentifier = model.imageURL.absoluteString; // shared identifier between image and thumbnail
        request.targetDimensions = TIPDimensionsFromView(imageViews);
        request.targetContentMode = imageView.contentMode;

        return request;
    }

    /* delegate methods */

    - (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
                didLoadPreviewImage:(id<TIPImageFetchResult>)previewResult
                         completion:(TIPImageFetchDidLoadPreviewCallback)completion
    {
        TIPImageContainer *imageContainer = previewResult.imageContainer;
        NSInteger idx = [op.context integerValue];
        UIImageView *imageView = _imageViews[idx];
        imageView.image = imageContainer.image;

        if ((imageContainer.dimension.width * imageContainer.dimensions.height) >= (originalDimensions.width * originalDimensions.height)) {
            // scaled down, preview is plenty
            completion(TIPImageFetchPreviewLoadedBehaviorStopLoading);
        } else {
            completion(TIPImageFetchPreviewLoadedBehaviorContinueLoading);
        }
    }

    - (BOOL)tip_imageFetchOperation:(TIPImageFetchOperation *)op
    shouldLoadProgressivelyWithIdentifier:(NSString *)identifier
                                URL:(NSURL *)URL
                          imageType:(NSString *)imageType
                 originalDimensions:(CGSize)originalDimensions
    {
        // only load progressively if we didn't load a "preview"
        return (nil == op.previewImageContainer);
    }

    - (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
          didUpdateProgressiveImage:(id<TIPImageFetchResult>)progressiveResult
                           progress:(float)progress
    {
        NSInteger idx = [op.context integerValue];
        UIImageView *imageView = _imageViews[idx];
        imageView.image = progressiveResult.imageContainer.image;
    }

    - (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
                  didLoadFinalImage:(id<TIPImageFetchResult>)finalResult
    {
        NSInteger idx = [op.context integerValue];
        UIImageView *imageView = _imageViews[idx];
        imageView.image = finalResult.imageContainer.image;

        [_imageFetchOperations removeObject:op];
    }

    - (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
            didFailToLoadFinalImage:(NSError *)error
    {
        NSInteger idx = [op.context integerValue];
        UIImageView *imageView = _imageViews[idx];
        if (!imageView.image) {
            imageView.image = MyAppImageLoadFailedPlaceholderImage();
        }

        NSLog(@"-[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), error);
        [_imageFetchOperations removeObject:op];
    }

```

## Inspecting Image Pipelines

_Twitter Image Pipeline_ has built in support for inspecting the caches via convenience categories.
`TIPGlobalConfiguration` has an `inspect:` method that will inspect all registered
`TIPImagePipeline` instances (even if they have not been explicitely loaded) and will provide
detailed results for those caches and the images there-in.  You can also call `inspect:` on a
specific `TIPImagePipeline` instance to be provided detailed info for that specific pipeline.
Inspecting pipelines is asynchronously done on background threads before the inspection callback is
called on the main thread.  This can provide very useful debugging info.  As an example, Twitter has
built in UI and tools that use the inspection support of *TIP* for internal builds.

# License

Copyright 2015-2020 Twitter, Inc.

Licensed under the Apache License, Version 2.0: https://www.apache.org/licenses/LICENSE-2.0

# Security Issues?

Please report sensitive security issues via Twitter's bug-bounty program (https://hackerone.com/twitter) rather than GitHub.
