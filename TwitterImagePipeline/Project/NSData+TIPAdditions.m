//
//  NSData+TIPAdditions.m
//  TwitterImagePipeline
//
//  Created on 9/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <objc/runtime.h>
#import "NSData+TIPAdditions.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSData (TIPAdditions)

- (NSData *)tip_safeSubdataNoCopyWithRange:(NSRange)range
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

- (NSString *)tip_hexStringValue
{
    static const unsigned char hexLookup[] = "0123456789abcdef";
    const NSUInteger hexLength = self.length * 2;
    if (!hexLength) {
        return @"";
    }

    unichar* hexChars = (unichar*)malloc(sizeof(unichar) * (hexLength));
    __block unichar *hexCharPtr = hexChars;
    [self enumerateByteRangesUsingBlock:^(const void *bytes, NSRange byteRange, BOOL *stop) {
        unsigned char *bytePtr = (unsigned char *)bytes;
        for (NSUInteger i = 0; i < byteRange.length; ++i) {
            const unsigned char byte = *bytePtr++;
            *hexCharPtr++ = hexLookup[(byte >> 4) & 0xF];
            *hexCharPtr++ = hexLookup[byte & 0xF];
        }
    }];

    return [[NSString alloc] initWithCharactersNoCopy:hexChars length:hexLength freeWhenDone:YES];
}

@end

NS_ASSUME_NONNULL_END

