//
//  TIPTiming.h
//  TwitterImagePipeline
//
//  Created on 5/12/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN uint64_t TIPAbsoluteToNanoseconds(uint64_t absolute);
FOUNDATION_EXTERN uint64_t TIPAbsoluteFromNanoseconds(uint64_t nano);

FOUNDATION_EXTERN NSTimeInterval TIPAbsoluteToTimeInterval(uint64_t absolute);
FOUNDATION_EXTERN uint64_t TIPAbsoluteFromTimeInterval(NSTimeInterval ti);

static const NSTimeInterval kTIPTimeEpsilon = 0.0005;

// If endTime is 0, mach_absolute_time() will be used in the calculation
FOUNDATION_EXTERN NSTimeInterval TIPComputeDuration(uint64_t startTime, uint64_t endTime);

NS_ASSUME_NONNULL_END

