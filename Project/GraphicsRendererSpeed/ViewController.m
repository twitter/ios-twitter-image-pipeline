//
//  ViewController.m
//  GraphicsRendererSpeed
//
//  Copyright © 2020 Twitter. All rights reserved.
//

#include <sys/utsname.h>

#import <TwitterImagePipeline.h>

#import "ViewController.h"

typedef NS_ENUM(NSInteger, RenderBehavior)
{
    RenderBehaviorLegacy = 0,
    RenderBehaviorTwitterImagePipeline,
    RenderBehaviorModernForcePrefersWideColorNo,
    RenderBehaviorModernForcePrefersWideColorYes,
    RenderBehaviorModernPrefersWideColorAutoScreen,
    RenderBehaviorModernPrefersWideColorAutoImage,
};

static const NSInteger kRenderBehaviorCount = 6;

#define CACHE_RENDERER 0

static NSString *RenderBehaviorToString(RenderBehavior behavior);
static NSString *RenderBehaviorToString(RenderBehavior behavior)
{
    switch (behavior) {
        case RenderBehaviorLegacy:
            return @"legacy";
        case RenderBehaviorTwitterImagePipeline:
            return @"tip";
        case RenderBehaviorModernForcePrefersWideColorNo:
            return @"wide=NO";
        case RenderBehaviorModernForcePrefersWideColorYes:
            return @"wide=YES";
        case RenderBehaviorModernPrefersWideColorAutoScreen:
            return @"wide=auto-screen";
        case RenderBehaviorModernPrefersWideColorAutoImage:
            return @"wide=auto-image";
    }
    return @"unknown";
}

static NSString *ModelName(void);
static NSString *ModelName()
{
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

@interface ViewController ()
{
    BOOL _running;
    UITextView *_textView;
    dispatch_queue_t _q;

    UIGraphicsImageRenderer *_cachedRenderer;
    RenderBehavior _cachedRendererBehavior;
}
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    _textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.editable = NO;
    _textView.contentInset = UIEdgeInsetsMake(40.0, 10.0, 0.0, 10.0);
    [self.view addSubview:_textView];
    _q = dispatch_queue_create("queue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self _start];
}

- (void)_appendText:(NSString *)text
{
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:text waitUntilDone:NO];
        return;
    }

    @autoreleasepool {
        NSString *existingText = _textView.text;
        if (existingText.length) {
            text = [existingText stringByAppendingString:text];
        }
        _textView.text = text;
        [_textView scrollRangeToVisible:NSMakeRange(text.length - 1, 1)];
    }
}

- (void)_start
{
    if (_running) {
        return;
    }

    _running = YES;
    [self _appendText:ModelName()];
    [self _appendText:@" - Starting...\n"];
    [self performSelector:@selector(_run) withObject:nil afterDelay:2.0];
}

- (void)_run
{
    NSArray<NSString *> *imageNames = @[
                                        @"iceland_P3.jpg",
                                        @"iceland_sRGB.jpg",
                                        @"iceland_png8.png",
                                        @"italy_P3.jpg",
                                        @"italy_sRGB.jpg",
                                        @"parrot_wide.jpg",
                                        @"parrot_srgb.jpg",
                                        @"parrot_png8.png",
                                        @"shoes_adobeRGB.jpg",
                                        @"shoes_sRGB.jpg",
                                        @"webkit_P3.png",
                                        @"webkit_sRGB.png",
                                        @"carnival.png",
                                        @"carnival_less_color.png",
                                        @"carnival_less_color_alpha_pixels.png",
                                        @"carnival_less_color_transparent_pixels.png",
                                        ];

    [self _appendText:TIPMainScreenSupportsWideColorGamut() ? @"is" : @"is not"];
    [self _appendText:@" wide gamut screen...\n"];

    for (NSString *imageName in imageNames) {
        [self _testImageWithName:imageName];
    }

    dispatch_async(_q, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_async(self->_q, ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self _appendText:@"\n\nComplete!"];
                    self->_running = NO;
                });
            });
        });
    });
}

- (void)_testImageWithName:(NSString *)imageName
{
    dispatch_async(_q, ^{
        [self _appendText:@"\n"];
        [self _appendText:imageName];

        NSString *path = [[NSBundle mainBundle] pathForResource:imageName ofType:nil];
        NSData *data = [NSData dataWithContentsOfFile:path];
        UIImage *image = [UIImage imageWithData:data];
        CGSize dims = image.tip_dimensions;
        CGSize resizeDims = dims;
        resizeDims.width = (CGFloat)round((double)resizeDims.width * 3.0 / 4.0);
        resizeDims.height = (CGFloat)round((double)resizeDims.height * 3.0 / 4.0);
        const BOOL isWideColor = CGColorSpaceIsWideGamutRGB(CGImageGetColorSpace(image.CGImage));

        [self _appendText:[NSString stringWithFormat:@" (%ix%i", (int)resizeDims.width, (int)resizeDims.height]];
        if (isWideColor) {
            [self _appendText:@":color=wide"];
        }
        [self _appendText:@")"];

        NSTimeInterval averages[kRenderBehaviorCount] = { 0 };
        for (RenderBehavior behavior = 0; behavior < kRenderBehaviorCount; behavior++) {
            averages[behavior] = [self _q_testImage:image targetDimensions:resizeDims behavior:behavior];
            const double ratio = (averages[behavior] / averages[0]);
            [self _appendText:[NSString stringWithFormat:@" - %.2f:1", ratio]];
        }

        [self _appendText:@"\n\tindexable="];
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        BOOL indexable = [image tip_canLosslesslyEncodeUsingIndexedPaletteWithOptions:TIPIndexedPaletteEncodingNoOptions];
        CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
        [self _appendText:(indexable) ? @"YES" : @"NO"];
        [self _appendText:[NSString stringWithFormat:@": %.2fms", (end - start) * 1000.0]];
        if (indexable) {
            [self _appendText:[NSString stringWithFormat:@", %.1fpx/ms", (dims.width * dims.height) / ((end - start) * 1000.)]];
        }
    });
}

- (NSTimeInterval)_q_testImage:(UIImage *)image targetDimensions:(CGSize)targetDims behavior:(RenderBehavior)behavior
{
    [self _appendText:@"\n\t"];
    [self _appendText:RenderBehaviorToString(behavior)];
    [self _appendText:@":"];

    NSTimeInterval total = 0.0;
    for (NSUInteger i = 0; i < 10; i++) {
        @autoreleasepool {
            total += [self _q_scaleSpeedCheckWithImage:image dimensions:targetDims behavior:behavior];
        }
    }

    _cachedRenderer = nil;
    NSTimeInterval avg = total / 10.0;
    [self _appendText:[NSString stringWithFormat:@" %.2fms", (avg * 1000.0)]];
    return avg;
}

- (NSTimeInterval)_q_scaleSpeedCheckWithImage:(UIImage *)image dimensions:(CGSize)dims behavior:(RenderBehavior)behavior
{
    const BOOL hasAlpha = [image tip_hasAlpha:NO];
    const CGFloat scale = image.scale;
    CGRect drawRect = CGRectMake(0, 0, dims.width / scale, dims.height / scale);
    const CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    UIImage *renderedImage = nil;
    if (RenderBehaviorLegacy == behavior) {
        UIGraphicsBeginImageContextWithOptions(drawRect.size, !hasAlpha, scale);
        [image drawInRect:drawRect];
        renderedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    } else if (RenderBehaviorTwitterImagePipeline == behavior) {
        renderedImage = [image tip_imageWithRenderFormatting:^(id<TIPRenderImageFormat> format) {
            format.renderSize = drawRect.size;
            format.scale = scale;
        } render:^(UIImage *sourceImage, CGContextRef ctx) {
            [sourceImage drawInRect:drawRect];
        }];
    } else {
        if (!_cachedRenderer || behavior != _cachedRendererBehavior) {
            UIGraphicsImageRendererFormat *format;
            if (RenderBehaviorModernPrefersWideColorAutoImage == behavior) {
                format = [image imageRendererFormat];
                assert(format.scale == scale);
            } else {
                if (@available(iOS 11, *)) {
                    format = [UIGraphicsImageRendererFormat preferredFormat];
                } else {
                    format = [UIGraphicsImageRendererFormat defaultFormat];
                }
                format.opaque = !hasAlpha;
                if (@available(iOS 12, *)) {
                    if (RenderBehaviorModernForcePrefersWideColorNo == behavior) {
                        format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
                    } else if (RenderBehaviorModernForcePrefersWideColorYes == behavior) {
                        format.preferredRange = UIGraphicsImageRendererFormatRangeExtended;
                    }
#if !TARGET_OS_MACCATALYST
                } else {
                    if (RenderBehaviorModernForcePrefersWideColorNo == behavior) {
                        format.prefersExtendedRange = NO;
                    } else if (RenderBehaviorModernForcePrefersWideColorYes == behavior) {
                        format.prefersExtendedRange = YES;
                    }
#endif
                }
                format.scale = scale;
            }
            _cachedRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:drawRect.size format:format];
            _cachedRendererBehavior = behavior;
        }
        renderedImage = [_cachedRenderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [image drawInRect:drawRect];
        }];
#if !CACHE_RENDERER
        _cachedRenderer = nil;
#endif
    }

    (void)renderedImage;
    return CFAbsoluteTimeGetCurrent() - start;
}

@end
