//
//  TIPSafeOperation.m
//  TwitterImagePipeline
//
//  Created on 6/1/17
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPSafeOperation.h"

NS_ASSUME_NONNULL_BEGIN

static BOOL _NSOperationHasCompletionBlockBug(void)
{
    static BOOL sHasBug = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if TARGET_OS_OSX
        // no bug on macOS
        sHasBug = NO;
#else
        // bug fixed iOS 11
        if (tip_available_ios_11) {
            sHasBug = NO;
        } else {
            sHasBug = YES;
        }
#endif
    });
    return sHasBug;
}

@implementation TIPSafeOperation

- (void)setCompletionBlock:(nullable void (^)(void))completionBlock
{
    if (!_NSOperationHasCompletionBlockBug()) {
        [super setCompletionBlock:completionBlock];
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
    [super setCompletionBlock:^{
        if (completionBlock) {
            completionBlock();
        }

        [self tip_clearCompletionBlock];
    }];
#pragma clang diagnostic pop
}

- (void)tip_clearCompletionBlock
{
    [super setCompletionBlock:nil];
}

@end

NS_ASSUME_NONNULL_END


