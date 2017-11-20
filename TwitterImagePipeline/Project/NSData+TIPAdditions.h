//
//  NSData+TIPAdditions.h
//  TwitterImagePipeline
//
//  Created on 9/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (TIPAdditions)
- (NSData *)tip_safeSubdataNoCopyWithRange:(NSRange)range;
- (NSString *)tip_hexStringValue;
@end

NS_ASSUME_NONNULL_END
