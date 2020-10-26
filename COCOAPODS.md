# CocoaPods

## Basic Integration

To integrate TIP into your iOS project using CocoaPods, simply add the following to your **Podfile**:

```ruby
target 'MyApp' do
  pod 'TwitterImagePipeline', '~> 2.24.2'
end
```

Then run a `pod install` inside your terminal, or from CocoaPods.app.

## Extended Integration

TIP also has support for two additional codecs that are not included with the default installation:

- WebP (Backwards compatible to iOS 10)
- MP4

If you wish to include these codecs, modify your **Podfile** to define the appropriate subspecs like the examples below:

```ruby
target 'MyApp' do
  pod 'TwitterImagePipeline', '~> 2.24.2', :subspecs => ['WebPCodec/Default']

  pod 'TwitterImagePipeline', '~> 2.24.2', :subspecs => ['WebPCodec/Animated']

  pod 'TwitterImagePipeline', '~> 2.24.2', :subspecs => ['MP4Codec']

  pod 'TwitterImagePipeline', '~> 2.24.2', :subspecs => ['WebPCodec/Animated', 'MP4']
end
```

- **`WebP/Default`**: Includes the `TIPXWebPCodec` with the WebP framework for basic WebP support.
- **`WebP/Animated`**: Adds additional support to the `TIPXWebPCodec` for demuxing WebP data allowing for animated images.
- **`MP4Codec`**: Includes the `TIPXMP4Codec`.

**Note:** You are still required to add these codecs to the `TIPImageCodecCatalogue` manually:

```objc
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    TIPImageCodecCatalogue *codecCatalogue = [TIPImageCodecCatalogue sharedInstance];

    [codecCatalogue setCodec:[[TIPXWebPCodec alloc] initPreservingDefaultCodecsIfPresent:NO]
                forImageType:TIPImageTypeWEBP];

    [codecCatalogue setCodec:[[TIPMP4Codec alloc] init]
                forImageType:TIPXImageTypeMP4];

    // ...
}
```
