//
//  TIPSafeOperation.h
//  TwitterImagePipeline
//
//  Created by Nolan O'Brien on 6/1/17.
//  Copyright © 2017 Twitter. All rights reserved.
//

#import <Foundation/NSOperation.h>

/**
 `TIPSafeOperation` works to encapsulate fixes for `NSOperation`.

 Specifically:
 - `NSOperation` is supposed to clear the `completionBlock` after it has been called.  It does do this on macOS, but not on iOS.  `TIPSafeOperation` fixes this.
 */
@interface TIPSafeOperation : NSOperation
@end
