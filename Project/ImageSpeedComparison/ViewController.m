//
//  ViewController.m
//  ImageSpeedComparison
//
//  Created on 9/4/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <Accelerate/Accelerate.h>

#import "TIPTestImageFetchDownloadInternalWithStubbing.h"

#import "ViewController.h"

typedef struct {
    __unsafe_unretained NSString *type;
    const char *name;
    const char *file; // provide a URL to load from the inet instead of simulating the load
    BOOL isProgressive;
    BOOL isAnimated;
} ImageTypeStruct;

static const ImageTypeStruct sImageTypes[] = {
    { @"public.jpeg",           "JPEG",         "twitterfied.jpg",          NO,     NO  },
    { @"public.jpeg",           "PJPEG",        "twitterfied.pjpg",         YES,    NO  },
    { @"public.jpeg-2000",      "JPEG-2000",    "twitterfied.jp2",          NO,     NO  },
    { @"public.png",            "PNG",          "twitterfied.png",          NO,     NO  },
    { @"public.tiff",           "TIFF",         "twitterfied.tiff",         NO,     NO  },
    { @"com.compuserve.gif",    "GIF",          "fireworks_original.gif",   NO,     YES },
    { @"org.webmproject.webp",  "WEBP",         "twitterfied.webp",         NO,     NO  },
    //{ @"org.webmproject.webp",  "Ani-WEBP",     "fireworks_original.webp",  NO,     YES },
    { @"org.webmproject.webp",  "Ani-WEBP",     "tenor_test.webp",          NO,     YES },
    // { @"com.compuserve.gif",    "Static GIF",   "https://media3.giphy.com/media/d3F2Dj8zECyDLFpm/v1.Y2lkPWU4MjZjOWZjOGViZWNhZmJmMjk0NDIyZGQzZjM2ZjhkMzhlNGRhZTk5OTYzZjliMQ/200_s.gif",               NO,     NO  },
    { @"public.heic",           "HEIC",         "twitterfied.heic",         NO,     NO  },
    // { @"public.heic",           "Ani-HEIC",     "starfield_animation.heic", NO,     YES },
    { @"public.jpeg",           "Small-PJPEG",  "twitterfied.small.pjpg",   YES,    NO  },
};

static const NSUInteger kBitrateDribble = 4 * 1000;
static const NSUInteger kBitrate80sModem = 16 * 1000;
static const NSUInteger kBitrateBad2G = 56 * 1000;
static const NSUInteger kBitrate2G = 128 * 1000; // 2G
static const NSUInteger kBitrate2GPlus = kBitrate2G * 2; // 2.5G
static const NSUInteger kBitrate3G = kBitrate2GPlus * 2; // 3G
static const NSUInteger kBitrate3GPlus = kBitrate3G + kBitrate2GPlus; // 3.5G
static const NSUInteger kBitrate4G = kBitrate3G * 2; // 4G
static const NSUInteger kBitrate4GPlus = kBitrate4G * 2; // ~LTE

static const NSUInteger sBitrates[] = {
    kBitrateDribble, kBitrate80sModem, kBitrateBad2G,
    kBitrate2G, kBitrate2GPlus,
    kBitrate3G, kBitrate3GPlus,
    kBitrate4G, kBitrate4GPlus
};

static const NSUInteger kDefaultBitrateIndex = 5;

@interface ViewController () <UIPickerViewDataSource, UIPickerViewDelegate, TIPImageFetchRequest, TIPImageFetchDelegate, TIPImageFetchTransformer>
@end

@implementation ViewController
{
    IBOutlet UIImageView *_imageView;
    IBOutlet UIProgressView *_progressView;
    IBOutlet UIButton *_selectImageTypeButton;
    IBOutlet UIButton *_selectSpeedButton;
    IBOutlet UIButton *_startButton;
    IBOutlet UIPickerView *_pickerView;
    IBOutlet UILabel *_resultsLabel;
    IBOutlet UISwitch *_blurSwitch;

    BOOL _selectingSpeed;
    UITapGestureRecognizer *_tapper;
    NSUInteger _imageTypeIndex;
    NSUInteger _speedIndex;
    TIPImagePipeline *_imagePipeline;
    id<TIPImageFetchDownloadProviderWithStubbingSupport> _downloadProvider;
    TIPImageFetchOperation *_fetchOperation;

    CFAbsoluteTime _startTime;
    CFAbsoluteTime _firstImageTime;
    CFAbsoluteTime _finalImageTime;
    NSUInteger _size;

    CGSize _cachedBounds;
    UIViewContentMode _cachedContentMode;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _progressView.progress = 0;

    _imageTypeIndex = 0;
    _speedIndex = kDefaultBitrateIndex;

    [self hidePickerView:NO];
    [self updateImageTypeButtonTitle];
    [self updateSpeedButtonTitle];

    _tapper = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(stopSelecting:)];
    _tapper.enabled = NO;
    [_imageView addGestureRecognizer:_tapper];

    _imagePipeline = [[TIPImagePipeline alloc] initWithIdentifier:@"ImageSpeedComparison"];
    _downloadProvider =[[TIPTestImageFetchDownloadProviderInternalWithStubbing alloc] init];
    [TIPGlobalConfiguration sharedInstance].imageFetchDownloadProvider = _downloadProvider;

    [_downloadProvider setDownloadStubbingEnabled:YES];
}

- (void)viewDidLayoutSubviews
{
    CGRect frame;

    frame = _progressView.frame;
    frame.origin.y = CGRectGetMaxY(_imageView.frame);
    _progressView.frame = frame;

    frame = _selectImageTypeButton.frame;
    frame.origin.y = CGRectGetMaxY(_progressView.frame) + 5;
    _selectImageTypeButton.frame = frame;

    frame = _selectSpeedButton.frame;
    frame.origin.y = CGRectGetMaxY(_selectImageTypeButton.frame) + 5;
    _selectSpeedButton.frame = frame;

    frame = _selectSpeedButton.frame;
    frame.origin.y += frame.size.height;
    frame.size = _blurSwitch.bounds.size;
    frame.origin.x = self.view.bounds.size.width - (frame.size.width + 5);
    _blurSwitch.frame = frame;

    frame = _startButton.frame;
    frame.origin.y = CGRectGetMaxY(_selectSpeedButton.frame) + 5;
    _startButton.frame = frame;

    frame = _resultsLabel.frame;
    frame.origin.y = CGRectGetMaxY(_startButton.frame) + 5 ;
    _resultsLabel.frame = frame;

    [super viewDidLayoutSubviews];
}

#pragma mark Actions

- (IBAction)start:(id)sender
{
    if (_fetchOperation) {
        return;
    }

    _startButton.enabled = NO;
    _cachedBounds = _imageView.bounds.size;
    _cachedContentMode = _imageView.contentMode;
    _fetchOperation = [_imagePipeline operationWithRequest:self context:nil delegate:self];
    [self registerCannedImage];
    [_imagePipeline fetchImageWithOperation:_fetchOperation];
}

- (IBAction)select:(UIButton *)sender
{
    if (!_pickerView.userInteractionEnabled) {
        _selectingSpeed = (sender == _selectSpeedButton);
        [self showPickerView:YES];
        _imageView.image = nil;
        _progressView.progress = 0;
        _startTime = 0;
        [self updateResults];
    }
}

- (IBAction)stopSelecting:(id)sender
{
    if (_pickerView.userInteractionEnabled) {
        UIButton *button = (_selectingSpeed) ? _selectSpeedButton : _selectImageTypeButton;
        if (!button.enabled) {
            [self hidePickerView:YES];
        }
    }
}

#pragma mark UI

- (void)updateResults
{
    if (0 == _startTime) {
        _resultsLabel.text = nil;
    } else {
        NSString *firstResult = @"N/A";
        NSString *finalResult = @"N/A";
        NSString *totalSize = @"X KBs";

        if (0 != _firstImageTime) {
            firstResult = [NSString stringWithFormat:@"%.4fs", _firstImageTime - _startTime];
        }

        if (0 != _finalImageTime) {
            finalResult = [NSString stringWithFormat:@"%.4fs", _finalImageTime - _startTime];
        }

        if (0 != _size) {
            totalSize = [NSByteCountFormatter stringFromByteCount:(long long)_size countStyle:NSByteCountFormatterCountStyleBinary];
        }

        _resultsLabel.text = [NSString stringWithFormat:@"First Scan: %@\nFinal Scan: %@\nFinal Size: %@", firstResult, finalResult, totalSize];
    }
}

- (void)updateImageTypeButtonTitle
{
    [_selectImageTypeButton setTitle:[NSString stringWithFormat:@"Type: %@", @(sImageTypes[_imageTypeIndex].name)]
                            forState:UIControlStateNormal];
}

- (void)updateSpeedButtonTitle
{
    [_selectSpeedButton setTitle:[NSString stringWithFormat:@"Speed: %tu Kbps", sBitrates[_speedIndex] / 1000] forState:UIControlStateNormal];
}

#pragma mark Canned Image

- (void)registerCannedImage
{
    NSURL *cannedImageURL = [self cannedImageFileURL];
    NSURL *imageURL = self.imageURL;

    if (cannedImageURL.isFileURL) {
        NSData *imageData = [NSData dataWithContentsOfURL:cannedImageURL
                                                  options:NSDataReadingMappedIfSafe
                                                    error:NULL];
        [_downloadProvider addDownloadStubForRequestURL:imageURL responseData:imageData responseMIMEType:nil shouldSupportResuming:NO suggestedBitrate:sBitrates[_speedIndex]];
    }
}

- (void)unregisterCannedImage
{
    NSURL *imageURL = self.imageURL;
    [_downloadProvider removeDownloadStubForRequestURL:imageURL];
}

#pragma mark Picker View

- (void)showPickerView:(BOOL)animated
{
    _selectImageTypeButton.enabled = NO;
    _selectSpeedButton.enabled = NO;
    _startButton.enabled = NO;

    [_imagePipeline clearMemoryCaches];
    [_imagePipeline clearDiskCache];

    [_pickerView reloadAllComponents];
    [_pickerView selectRow:(_selectingSpeed) ? (NSInteger)_speedIndex : (NSInteger)_imageTypeIndex inComponent:0 animated:NO];

    [UIView animateWithDuration:animated ? 0.5 : 0.0
                     animations:^{
                         self->_selectImageTypeButton.alpha = 0;
                         self->_selectSpeedButton.alpha = 0;
                         self->_startButton.alpha = 0;
                         self->_resultsLabel.alpha = 0;
                         CGRect frame = self->_pickerView.frame;
                         frame.origin.y = self.view.bounds.size.height - frame.size.height;
                         self->_pickerView.frame = frame;
                     }
                     completion:^(BOOL finished) {
                         self->_pickerView.userInteractionEnabled = YES;
                         self->_tapper.enabled = YES;
                     }];
}

- (void)hidePickerView:(BOOL)animated
{
    _pickerView.userInteractionEnabled = NO;
    [UIView animateWithDuration:animated ? 0.5 : 0.0
                     animations:^{
                         self->_selectImageTypeButton.alpha = 1;
                         self->_selectSpeedButton.alpha = 1;
                         self->_startButton.alpha = 1;
                         self->_resultsLabel.alpha = 1;
                         CGRect frame = self->_pickerView.frame;
                         frame.origin.y = self.view.bounds.size.height;
                         self->_pickerView.frame = frame;
                     }
                     completion:^(BOOL finished) {
                         self->_startButton.enabled = YES;
                         self->_selectImageTypeButton.enabled = YES;
                         self->_selectSpeedButton.enabled = YES;
                         self->_tapper.enabled = NO;
                     }];
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    if (row < 0) {
        return;
    }

    if (_selectingSpeed) {
        _speedIndex = (NSUInteger)row;
        [self updateSpeedButtonTitle];
    } else {
        _imageTypeIndex = (NSUInteger)row;
        [self updateImageTypeButtonTitle];
    }
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    return (_selectingSpeed) ? [NSString stringWithFormat:@"%tu Kbps", sBitrates[row] / 1000] : @(sImageTypes[row].name);
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
    return (_selectingSpeed) ? (sizeof(sBitrates) / sizeof(sBitrates[0])) : (sizeof(sImageTypes) / sizeof(sImageTypes[0]));
}

#pragma mark Image Fetch Request

- (NSURL *)imageURL
{
    NSString *imageName = @(sImageTypes[_imageTypeIndex].file);
    NSString *imageURLString;
    if ([imageName hasPrefix:@"http"]) {
        imageURLString = imageName;
    } else {
        imageURLString = [NSString stringWithFormat:@"https://www.twitterfied.com/%@", imageName];
    }
    NSURL *imageURL = [NSURL URLWithString:imageURLString];
    return imageURL;
}

- (CGSize)targetDimensions
{
    return TIPDimensionsFromPointSize(_cachedBounds);
}

- (UIViewContentMode)targetContentMode
{
    return _cachedContentMode;
}

- (id<TIPImageFetchTransformer>)transformer
{
    return _blurSwitch.on ? self : nil;
}

- (UIImage *)tip_transformImage:(UIImage *)image withProgress:(float)progress hintTargetDimensions:(CGSize)targetDimensions hintTargetContentMode:(UIViewContentMode)targetContentMode forImageFetchOperation:(TIPImageFetchOperation *)op
{
    if (!image.CGImage) {
        return nil;
    }

    BOOL shouldScaleFirst = NO;
    const CGSize imageDimension = [image tip_dimensions];
    CGFloat blurRadius = 0;
    if (progress < 0 || progress >= 1.f) {
        // placeholder?
        id<TIPImageFetchRequest> request = op.request;
        if (![request respondsToSelector:@selector(options)]) {
            return nil;
        }
        if ((request.options & TIPImageFetchTreatAsPlaceholder) == 0) {
            return nil;
        }
        if (targetDimensions.width <= imageDimension.width && targetDimensions.height <= imageDimension.height) {
            return nil;
        }
        blurRadius = (CGFloat)log2(MAX(targetDimensions.height / imageDimension.height, targetDimensions.width / targetDimensions.width));
        shouldScaleFirst = YES;
    } else {
        // progressive
        if (progress > .65f) {
            return nil;
        }
        const CGFloat divisor = (1.f + progress) * 2.f;
        blurRadius = (CGFloat)log2(MAX(imageDimension.width, imageDimension.height)) / divisor;
        blurRadius *= 1.f - progress;
    }

    if (blurRadius < 0.5) {
        return nil;
    }

    // TRANSFORM!
    if (shouldScaleFirst) {
        image = [image tip_scaledImageWithTargetDimensions:targetDimensions contentMode:targetContentMode];
    }
    UIImage *transformed = [image tip_blurredImageWithRadius:blurRadius];
    NSAssert(CGSizeEqualToSize([image tip_dimensions], [transformed tip_dimensions]), @"sizing missmatch!");
    return transformed;
}

- (NSString *)tip_transformerIdentifier
{
    return @"speed.test.transformer";
}

//- (NSDictionary *)progressiveLoadingPolicies
//{
//    return @{ TIPImageTypeJPEG : [[TIPGreedyProgressiveLoadingPolicy alloc] init] };
//}

//- (NSDictionary *)progressiveLoadingPolicies
//{
//    if (sImageTypes[_imageTypeIndex].isProgressive) {
//        if (![sImageTypes[_imageTypeIndex].type isEqualToString:TIPImageTypeJPEG]) {
//            return @{ sImageTypes[_imageTypeIndex].type : [[TIPGreedyProgressiveLoadingPolicy alloc] init] };
//        }
//    }
//    return nil;
//}

- (NSDictionary *)progressiveLoadingPolicies
{
    return @{ TIPImageTypeWEBP : [[TIPFullFrameProgressiveLoadingPolicy alloc] init] };
}

- (NSURL *)cannedImageFileURL
{
    NSString *file = @(sImageTypes[_imageTypeIndex].file);
    if ([file hasPrefix:@"http"]) {
        return [NSURL URLWithString:file];
    }
    return [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:file ofType:nil]];
}

#pragma mark Image Fetch Operation

- (void)tip_imageFetchOperationDidStart:(TIPImageFetchOperation *)op
{
    _progressView.progressTintColor = [UIColor yellowColor];
    _progressView.progress = 0;
    _imageView.image = nil;
    _startTime = 0;
    [self updateResults];
    _startTime = CFAbsoluteTimeGetCurrent();
    _firstImageTime = _finalImageTime = 0;
    _size = 0;
}

- (BOOL)tip_imageFetchOperation:(TIPImageFetchOperation *)op
shouldLoadProgressivelyWithIdentifier:(NSString *)identifier
                            URL:(NSURL *)URL
                      imageType:(NSString *)imageType
             originalDimensions:(CGSize)originalDimensions
{
    return sImageTypes[_imageTypeIndex].isProgressive;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
      didUpdateProgressiveImage:(id<TIPImageFetchResult>)progressiveResult
                       progress:(float)progress
{
    [_progressView setProgress:progress animated:YES];
    _imageView.image = progressiveResult.imageContainer.image;
    if (0 == _firstImageTime) {
        _firstImageTime = CFAbsoluteTimeGetCurrent();
    }
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFirstAnimatedImageFrame:(id<TIPImageFetchResult>)progressiveResult progress:(float)progress
{
    [_progressView setProgress:progress animated:YES];
    _imageView.image = progressiveResult.imageContainer.image;
    _progressView.progress = progress;
    if (0 == _firstImageTime) {
        _firstImageTime = CFAbsoluteTimeGetCurrent();
    }
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didUpdateProgress:(float)progress
{
    [_progressView setProgress:progress animated:YES];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didLoadFinalImage:(id<TIPImageFetchResult>)finalResult
{
    [self unregisterCannedImage];
    if (0 == _firstImageTime) {
        _firstImageTime = CFAbsoluteTimeGetCurrent();
    }
    _size = [op.metrics metricInfoForSource:finalResult.imageSource].networkImageSizeInBytes;
    _finalImageTime = CFAbsoluteTimeGetCurrent();
    _imageView.image = finalResult.imageContainer.image;
    [_progressView setProgress:1.f animated:YES];
    _progressView.progressTintColor = [UIColor greenColor];
    _fetchOperation = nil;
    _startButton.enabled = YES;
    _selectImageTypeButton.enabled = YES;
    [self updateResults];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didFailToLoadFinalImage:(NSError *)error
{
    [self unregisterCannedImage];
    _progressView.progressTintColor = [UIColor redColor];
    _fetchOperation = nil;
    _startButton.enabled = YES;
    _selectImageTypeButton.enabled = YES;
    [self updateResults];
}

@end
