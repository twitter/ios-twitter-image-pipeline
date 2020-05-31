//
//  TIPTiming.m
//  TwitterImagePipeline
//
//  Created on 5/12/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <mach/mach_time.h>

#import "TIPTiming.h"

NS_ASSUME_NONNULL_BEGIN

static mach_timebase_info_data_t _TIPMachTimebaseInfo(void);
static mach_timebase_info_data_t _TIPMachTimebaseInfo(void)
{
    static mach_timebase_info_data_t sMachInfo;
    static dispatch_once_t sMachInfoOnceToken = 0;
    dispatch_once(&sMachInfoOnceToken, ^{
        if (mach_timebase_info(&sMachInfo) != KERN_SUCCESS) {
            sMachInfo.numer = 0;
            sMachInfo.denom = 1;
        }
    });
    return sMachInfo;
}

uint64_t TIPAbsoluteFromNanoseconds(uint64_t nano)
{
    mach_timebase_info_data_t machInfo = _TIPMachTimebaseInfo();
    if (0 == machInfo.numer) {
        // If we can't get a valid timebase, just convert to zero
        return 0;
    }

    // Don't sweat imprecision going from Nano to Absolute
    uint64_t absolute = nano * machInfo.denom;
    absolute /= machInfo.numer;
    return absolute;
}

uint64_t TIPAbsoluteToNanoseconds(uint64_t absolute)
{
    mach_timebase_info_data_t machInfo = _TIPMachTimebaseInfo();

    uint64_t nanoSeconds = absolute * machInfo.numer;
    if (nanoSeconds < absolute) {
        /*
         Either overflow or zero numer

         Overflow:
         proceed with loss of precision

         Zero numer:
         this will happen when there's an error returned by
         mach_timebase_info (I've never encountered this).
         In this case, it will be best to just have all values
         return as 0 instead of an inaccurate value. For
         simplicity, we'll just use the overflow logic.
         */
        nanoSeconds = absolute / machInfo.denom;
        nanoSeconds *= machInfo.numer;
    } else {
        nanoSeconds /= machInfo.denom;
    }

    return nanoSeconds;
}

NSTimeInterval TIPAbsoluteToTimeInterval(uint64_t absolute)
{
    uint64_t nanoSeconds = TIPAbsoluteToNanoseconds(absolute);
    double preciseValueInSeconds = (((double)nanoSeconds) / NSEC_PER_SEC);
    return preciseValueInSeconds;
}

uint64_t TIPAbsoluteFromTimeInterval(NSTimeInterval ti)
{
    uint64_t nanoSeconds = (uint64_t)(ti * NSEC_PER_MSEC);
    uint64_t absolute = TIPAbsoluteFromNanoseconds(nanoSeconds);
    return absolute;
}

NSTimeInterval TIPComputeDuration(uint64_t startTime, uint64_t endTime)
{
    if (!startTime) {
        return 0;
    }
    if (!endTime) {
        endTime = mach_absolute_time();
    }
    if (endTime < startTime) {
        return -TIPAbsoluteToTimeInterval(startTime - endTime);
    }
    return TIPAbsoluteToTimeInterval(endTime - startTime);
}

NS_ASSUME_NONNULL_END

