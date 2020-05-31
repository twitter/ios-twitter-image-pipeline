//
//  NSData+TIPAdditions.h
//  TwitterImagePipeline
//
//  Created on 9/9/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (TIPAdditions)
- (NSData *)tip_safeSubdataNoCopyWithRange:(NSRange)subRange; // throws `NSRangeException`
- (nullable NSData *)tip_safeSubdataNoCopyWithRange:(NSRange)subRange error:(out NSError * __nullable * __nullable)outError;
- (NSString *)tip_hexStringValue;
@end

NS_ASSUME_NONNULL_END

