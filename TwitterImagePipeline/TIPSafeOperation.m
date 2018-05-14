//
//  TIPSafeOperation.m
//  TwitterImagePipeline
//
//  Created on 6/1/17
//  Copyright © 2017 Twitter. All rights reserved.
//

#import "TIPSafeOperation.h"

NS_ASSUME_NONNULL_BEGIN

static BOOL _NSOperationHasCompletionBlockBug(void)
{
    static BOOL sHasBug = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSProcessInfo *processInfo = [NSProcessInfo processInfo];
        if (![processInfo respondsToSelector:@selector(isOperatingSystemAtLeastVersion:)]) {
            // Technically, on iOS 7 and lower, it's not a bug but rather by design...
            // For our purposes though, we'll treat it as a bug so we can use our "safety" support
            sHasBug = YES;
            return;
        }
#if TARGET_OS_WATCH
        // fixed watchOS 4
        sHasBug = ![processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){ 4, 0 , 0}];
#elif TARGET_OS_IOS || TARGET_OS_TV
        // fixed iOS/tvOS 11
        sHasBug = ![processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){ 11, 0 , 0}];
#else
        // macOS or newer OSes, no bug
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
    [super setCompletionBlock:NULL];
}

@end

NS_ASSUME_NONNULL_END
