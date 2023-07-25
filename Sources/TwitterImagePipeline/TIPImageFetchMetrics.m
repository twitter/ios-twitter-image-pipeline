//
//  TIPImageFetchMetrics.m
//  TwitterImagePipeline
//
//  Created on 6/19/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <mach/mach_time.h>
#import "TIP_Project.h"
#import "TIPImageFetchMetrics+Project.h"
#import "TIPTiming.h"

NS_ASSUME_NONNULL_BEGIN

@interface TIPImageFetchMetricInfo ()
// Concrete properties for `NetworkSourceInfo` category
@property (nonatomic, readonly, nullable) id networkMetrics;
@property (nonatomic, readonly, nullable) NSURLRequest *networkRequest;
@property (nonatomic, readonly) NSTimeInterval totalNetworkLoadDuration;
@property (nonatomic, readonly) NSTimeInterval firstProgressiveFrameNetworkLoadDuration;
@property (nonatomic, readonly) NSUInteger networkImageSizeInBytes;
@property (nonatomic, copy, readonly, nullable) NSString *networkImageType;
@property (nonatomic, readonly) CGSize networkImageDimensions;
@property (nonatomic, readonly) float networkImagePixelsPerByte;
@end

@implementation TIPImageFetchMetrics
{
    struct {
        TIPImageLoadSource currentSource:4;
        BOOL isTrackingCurrentSource:1;
        BOOL wasCancelled:1;
    } _flags;
    uint64_t _machStartTime;
    uint64_t _machFirstImageLoadTime;
    uint64_t _machEndTime;

    /*
     max value + 1 == number of values
     number of values - 1 == number of non-unknown values
     number of non-unknown values == max value
     */
    TIPImageFetchMetricInfo *_infos[TIPImageLoadSourceMaxValue];
}

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (instancetype)initProject
{
    return [super init];
}

#pragma mark Public

- (nullable TIPImageFetchMetricInfo *)metricInfoForSource:(TIPImageLoadSource)source
{
    if (source == TIPImageLoadSourceUnknown || source > TIPImageLoadSourceMaxValue) {
        return nil;
    }
    return _infos[source - 1];
}

- (BOOL)wasCancelled
{
    return _flags.wasCancelled;
}

- (NSTimeInterval)totalDuration
{
    if (_machStartTime && _machEndTime) {
        return TIPComputeDuration(_machStartTime, _machEndTime);
    }

    return 0.0;
}

- (NSTimeInterval)firstImageLoadDuration
{
    if (_machStartTime && _machFirstImageLoadTime) {
        return TIPComputeDuration(_machStartTime, _machFirstImageLoadTime);
    }

    return 0.0;
}

#pragma mark Project

- (void)startWithSource:(TIPImageLoadSource)source
{
    if (_flags.wasCancelled) {
        return;
    }

    if (_flags.isTrackingCurrentSource) {
        @throw [NSException exceptionWithName:NSObjectNotAvailableException reason:[NSString stringWithFormat:@"%@ cannot %@ while in the middle of capturing the metrics of another TIPImageLoadSource!", NSStringFromClass([self class]), NSStringFromSelector(_cmd)] userInfo:nil];
    }

    if (_flags.currentSource >= source) { // also prevents accessing Unknown which is 0
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"%@ cannot %@ with a TIPImageLoadSource (%ti) that has already been captured!", NSStringFromClass([self class]), NSStringFromSelector(_cmd), (TIPImageLoadSource)_flags.currentSource] userInfo:nil];
    }

    _flags.isTrackingCurrentSource = 1;
    _flags.currentSource = source;
    const uint64_t machTime = mach_absolute_time();
    if (!_machStartTime) {
        _machStartTime = machTime;
    }

    _infos[source-1] = [[TIPImageFetchMetricInfo alloc] initWithSource:source startTime:machTime];
}

- (void)endSource
{
    if (_flags.wasCancelled) {
        return;
    }

    if (!_flags.isTrackingCurrentSource) {
        NSString *reason = [NSString stringWithFormat:@"%@ cannot %@ when %@ has not been called yet!", NSStringFromClass([self class]), NSStringFromSelector(_cmd), @"startWithSource:"];
        @throw [NSException exceptionWithName:NSObjectNotAvailableException
                                       reason:reason
                                     userInfo:nil];
    }

    _machEndTime = mach_absolute_time();
    [_infos[_flags.currentSource - 1] end];
    _flags.isTrackingCurrentSource = 0;
}

- (void)cancelSource
{
    if (_flags.wasCancelled) {
        return;
    }

    _flags.wasCancelled = 1;
    _machEndTime = mach_absolute_time();
    if (_flags.isTrackingCurrentSource) {
        [_infos[_flags.currentSource - 1] cancel];
        _flags.isTrackingCurrentSource = 0;
    }
}

- (void)convertNetworkMetricsToResumedNetworkMetrics
{
    if (_flags.wasCancelled) {
        return;
    }

    if (_flags.currentSource != TIPImageLoadSourceNetwork) {
        return;
    }

    if (!_flags.isTrackingCurrentSource) {
        return;
    }

    TIPImageFetchMetricInfo *currentInfo = _infos[_flags.currentSource - 1];
    [currentInfo flipLoadSourceFromNetworkToNetworkResumed];
    _flags.currentSource = TIPImageLoadSourceNetworkResumed;
    _infos[TIPImageLoadSourceNetwork - 1] = nil;
    _infos[TIPImageLoadSourceNetworkResumed - 1] = currentInfo;
}

- (void)addNetworkMetrics:(nullable id)metrics
               forRequest:(NSURLRequest *)request
                imageType:(nullable NSString *)imageType
         imageSizeInBytes:(NSUInteger)sizeInBytes
          imageDimensions:(CGSize)dimensions
{
    if (_flags.wasCancelled) {
        return;
    }

    const BOOL isNetworkSource = _flags.currentSource == TIPImageLoadSourceNetwork || _flags.currentSource == TIPImageLoadSourceNetworkResumed;
    if (!_flags.isTrackingCurrentSource || !isNetworkSource) {
        NSString *reason = [NSString stringWithFormat:@"%@ cannot %@ when not tracking network source!", NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
        @throw [NSException exceptionWithName:NSObjectNotAvailableException
                                       reason:reason
                                     userInfo:nil];
    }

    [_infos[_flags.currentSource - 1] addNetworkMetrics:metrics
                                             forRequest:request
                                              imageType:imageType
                                       imageSizeInBytes:sizeInBytes
                                        imageDimensions:dimensions];
}

- (void)previewWasHit:(NSTimeInterval)renderLatency
{
    [self _hit:TIPImageFetchLoadResultHitPreview
 renderLatency:renderLatency
 synchronously:NO];
}

- (void)progressiveFrameWasHit:(NSTimeInterval)renderLatency
{
    [self _hit:TIPImageFetchLoadResultHitProgressFrame
 renderLatency:renderLatency
 synchronously:NO];
}

- (void)finalWasHit:(NSTimeInterval)renderLatency synchronously:(BOOL)sync
{
    [self _hit:TIPImageFetchLoadResultHitFinal
 renderLatency:renderLatency
 synchronously:sync];
}

- (void)_hit:(TIPImageFetchLoadResult)result
        renderLatency:(NSTimeInterval)latency
        synchronously:(BOOL)synchronously TIP_OBJC_DIRECT
{
    if (_flags.isTrackingCurrentSource) {
        if (!_machFirstImageLoadTime) {
            _machFirstImageLoadTime = mach_absolute_time();
        }
        [_infos[_flags.currentSource - 1] hit:result
                                renderLatency:latency
                                synchronously:synchronously];
    }
}

- (NSString *)description
{
    const size_t count = sizeof(_infos) / sizeof(_infos[0]);
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:count];
    for (TIPImageLoadSource i = 1; (size_t)i <= count; i++) {
        TIPImageFetchMetricInfo *info = _infos[i - 1];
        if (info) {
            [array addObject:info];
        }
    }
    NSString *state = nil;
    if (self.wasCancelled) {
        state = @"cancelled";
    } else if (_machFirstImageLoadTime) {
        state = @"hit";
    } else {
        state = @"miss";
    }
    [array addObject:[NSString stringWithFormat:@"total : %@=%.3fs", state, self.totalDuration]];
    return array.description;
}

@end

@implementation TIPImageFetchMetricInfo
{
    struct {
        BOOL wasCancelled:1;
        BOOL didEnd:1;
    } _flags;
    uint64_t _machStartTime;
    uint64_t _machEndTime;
    NSTimeInterval _renderLatency;

    uint64_t _machFirstTime;
    TIPImageFetchLoadResult _firstResult;
    NSTimeInterval _firstResultRenderLatency;
}

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (instancetype)initWithSource:(TIPImageLoadSource)source
                     startTime:(uint64_t)startMachTime
{
    if (TIPImageLoadSourceUnknown == source) {
        NSString *reason = [NSString stringWithFormat:@"%@ cannot init with an Unknown TIPImageLoadSource!", NSStringFromClass([self class])];
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:reason
                                     userInfo:nil];
    }

    if (self = [super init]) {
        _result = _firstResult = TIPImageFetchLoadResultNeverCompleted;
        _machStartTime = startMachTime;
        _source = source;
    }
    return self;
}

- (NSTimeInterval)loadDuration
{
    if (_machEndTime) {
        return TIPComputeDuration(_machStartTime, _machEndTime);
    }

    return 0.0;
}

- (BOOL)wasCancelled
{
    return _flags.wasCancelled;
}

- (void)end
{
    if (_flags.wasCancelled) {
        return;
    }

    if (_flags.didEnd) {
        NSString *reason = [NSString stringWithFormat:@"%@ cannot %@ after it has already ended!", NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
        @throw [NSException exceptionWithName:NSObjectNotAvailableException
                                       reason:reason
                                     userInfo:nil];
    }

    _flags.didEnd = 1;
    _machEndTime = mach_absolute_time();
    if (TIPImageFetchLoadResultNeverCompleted == _result) {
        _result = TIPImageFetchLoadResultMiss;
    }
}

- (void)cancel
{
    if (_flags.wasCancelled || _flags.didEnd) {
        return;
    }

    _flags.wasCancelled = 1;
    _machEndTime = mach_absolute_time();
}

- (void)hit:(TIPImageFetchLoadResult)result
        renderLatency:(NSTimeInterval)renderLatency
        synchronously:(BOOL)sync
{
    if (_flags.didEnd || _flags.wasCancelled) {
        return;
    }

    if (_result < result) {

        if (_result != TIPImageFetchLoadResultNeverCompleted) {
            _firstResult = _result;
            _firstResultRenderLatency = _renderLatency;
        }

        if (!_machFirstTime) {
            _machFirstTime = mach_absolute_time();
        }

        if (TIPImageFetchLoadResultHitProgressFrame == result) {
            _firstProgressiveFrameNetworkLoadDuration = TIPComputeDuration(_machStartTime, mach_absolute_time());
        }

        _wasLoadedSynchronously = sync;
        if (sync) {
            TIPAssert(TIPImageFetchLoadResultHitFinal == result && TIPImageLoadSourceMemoryCache == _source);
        }

        _result = result;
        _renderLatency = renderLatency;
    }
}

- (void)flipLoadSourceFromNetworkToNetworkResumed
{
    if (_source == TIPImageLoadSourceNetwork) {
        _source = TIPImageLoadSourceNetworkResumed;
    }
}

- (void)addNetworkMetrics:(nullable id)metrics
               forRequest:(NSURLRequest *)request
                imageType:(nullable NSString *)imageType
         imageSizeInBytes:(NSUInteger)sizeInBytes
          imageDimensions:(CGSize)dimensions
{
    if (_flags.wasCancelled) {
        return;
    }

    if (_source != TIPImageLoadSourceNetwork && _source != TIPImageLoadSourceNetworkResumed) {
        return;
    }

    _networkMetrics = metrics;
    _networkRequest = request;
    if (imageType) {
        _networkImageDimensions = dimensions;
        _networkImageSizeInBytes = sizeInBytes;
        _networkImageType = [imageType copy];
        uint64_t machTime = mach_absolute_time();
        _totalNetworkLoadDuration = TIPComputeDuration(_machStartTime, machTime);
    }
}

- (float)networkImagePixelsPerByte
{
    if (_networkImageSizeInBytes > 0 && _networkImageDimensions.height > 0 && _networkImageDimensions.width > 0) {
        return ((float)_networkImageDimensions.height * (float)_networkImageDimensions.width) / (float)_networkImageSizeInBytes;
    }
    return 0;
}

- (NSString *)description
{
    const NSTimeInterval duration = self.loadDuration;
    NSString *source = nil;
    NSString *result = nil;
    switch (_source) {
        case TIPImageLoadSourceMemoryCache: {
            source = @"memory";
            break;
        }
        case TIPImageLoadSourceDiskCache: {
            source = @"disk";
            break;
        }
        case TIPImageLoadSourceAdditionalCache: {
            source = @"alt";
            break;
        }
        case TIPImageLoadSourceNetwork: {
            source = @"network";
            break;
        }
        case TIPImageLoadSourceNetworkResumed: {
            source = @"network_resumed";
            break;
        }
        default: {
            break;
        }
    }

    switch (_result) {
        case TIPImageFetchLoadResultNeverCompleted: {
            result = (_flags.wasCancelled) ? @"cancelled" : @"DNF";
            break;
        }
        case TIPImageFetchLoadResultMiss: {
            result = @"miss";
            break;
        }
        case TIPImageFetchLoadResultHitPreview: {
            result = @"preview";
            break;
        }
        case TIPImageFetchLoadResultHitProgressFrame: {
            result = @"progressFrame";
            break;
        }
        case TIPImageFetchLoadResultHitFinal: {
            result = @"final";
            break;
        }
    }

    NSString *firstResult = @"";
    if (_firstResult == TIPImageFetchLoadResultHitPreview || _firstResult == TIPImageFetchLoadResultHitProgressFrame) {
        NSString *firstLatency = (_firstResultRenderLatency > 0) ? [NSString stringWithFormat:@" 1_dRen=%.3fs", _firstResultRenderLatency] : @"";
        firstResult = [NSString stringWithFormat:@", 1_%@=%.3fs%@", (_firstResult == TIPImageFetchLoadResultHitPreview) ? @"preview" : @"progress", TIPComputeDuration(_machStartTime, _machFirstTime), firstLatency];
    }

    NSString *renderLatency = @"";
    if (_renderLatency > 0) {
        renderLatency = [NSString stringWithFormat:@" dRen=%.3fs", _renderLatency];
    }

    NSString *pixelsPerByte = @"";
    NSString *imageType = @"";
    if (_source == TIPImageLoadSourceNetwork || _source == TIPImageLoadSourceNetworkResumed) {
        if (_networkImageType) {
            imageType = [NSString stringWithFormat:@" %@", _networkImageType];
        }
        float pixelsPerByteFloat = self.networkImagePixelsPerByte;
        if (pixelsPerByteFloat > FLT_EPSILON) {
            pixelsPerByte = [NSString stringWithFormat:@" pixelsPerByte=%.3f", pixelsPerByteFloat];
        }
    }

    return [NSString stringWithFormat:@"%@ : %@=%.3fs%@%@%@%@", source, result, duration, renderLatency, firstResult, pixelsPerByte, imageType];
}

@end

NS_ASSUME_NONNULL_END
