//
//  NSData+TIPAdditions.m
//  TwitterImagePipeline
//
//  Created on 9/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <objc/runtime.h>
#import "NSData+TIPAdditions.h"

@implementation NSData (TIPAdditions)

- (nonnull NSData *)tip_safeSubdataNoCopyWithRange:(NSRange)range
{
    if (range.location == 0 && range.length == self.length) {
        return self;
    }

    // TODO: optimize so that self.bytes doesn't have to be called,
    // since it triggers a copy of all bytes when the NSData has non-continuous data

    const void *bytePtr = self.bytes + range.location;
    NSData *data = [NSData dataWithBytesNoCopy:(void *)bytePtr length:range.length freeWhenDone:NO];
    objc_setAssociatedObject(data, _cmd, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return data;
}

@end
