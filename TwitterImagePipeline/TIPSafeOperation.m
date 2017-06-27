//
//  TIPSafeOperation.m
//  TwitterImagePipeline
//
//  Created by Nolan O'Brien on 6/1/17.
//  Copyright © 2017 Twitter. All rights reserved.
//

#import "TIPSafeOperation.h"

@implementation TIPSafeOperation

- (void)setCompletionBlock:(void (^)(void))completionBlock
{
    // As of iOS 8+, documentation states that the completion
    // block will automatically be set to `nil` after it begins executing.
    // https://developer.apple.com/reference/foundation/nsoperation/1408085-completionblock?language=objc
    //
    // However, this is provably not true on iOS:
    // https://gist.github.com/bjhomer/e866a405c425e83c8cad53a8ee8f055e
    //
    // It appears that macOS does the right thing.
    // We have duplicated these results on iOS 9 and iOS 10 (on device and sim).
    //
    // Instead, enforce the docs and always clear the completion block.

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
