//
//  TIPSafeOperation.h
//  TwitterImagePipeline
//
//  Created on 6/1/17
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 `TIPSafeOperation` works to encapsulate fixes for `NSOperation`.

 Specifically:
 - `NSOperation` is supposed to clear the `completionBlock` after it has been called.  It does do this on macOS, but not on all versions of iOS.  `TIPSafeOperation` fixes this.
 */
@interface TIPSafeOperation : NSOperation
@end

NS_ASSUME_NONNULL_END

