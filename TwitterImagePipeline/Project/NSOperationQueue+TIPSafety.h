//
//  NSOperationQueue+TIPSafety.h
//  TwitterImagePipeline
//
//  Created on 8/14/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Long story short, QoS in iOS 8 can lead to a crash with async NSOperations.
 This is a workaround that doesn't eliminate the risk of the crash but mitigates it by 99.9%.
 */
@interface NSOperationQueue (TIPSafety)

/**
 Same as `[NSOperationQueue addOperation:]` but with added safety.
 If _op_ returns `YES` for `isAsynchronous`, the operation will be retained for a period that
 extends beyond the lifetime of the operation executing to avoid a crash.
 */
- (void)tip_safeAddOperation:(NSOperation *)op;

@end

NS_ASSUME_NONNULL_END
