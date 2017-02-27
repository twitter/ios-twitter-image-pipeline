//
//  TIPURLStringCoding.h
//  TwitterImagePipeline
//
//  Created on 8/12/16.
//  Copyright (c) 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

FOUNDATION_EXTERN NSString *TIPURLEncodeString(NSString *string);
FOUNDATION_EXTERN NSString *TIPURLDecodeString(NSString *string, BOOL replacePlussesWithSpaces);
