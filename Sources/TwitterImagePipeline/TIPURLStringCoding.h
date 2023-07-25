//
//  TIPURLStringCoding.h
//  TwitterImagePipeline
//
//  Created on 8/12/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString * __nullable TIPURLEncodeString(NSString * __nullable string);
FOUNDATION_EXTERN NSString * __nullable TIPURLDecodeString(NSString * __nullable string, BOOL replacePlussesWithSpaces);

NS_ASSUME_NONNULL_END
