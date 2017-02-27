//
//  NSData+TIPAdditions.h
//  TwitterImagePipeline
//
//  Created on 9/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (TIPAdditions)
- (nonnull NSData *)tip_safeSubdataNoCopyWithRange:(NSRange)range;
@end
