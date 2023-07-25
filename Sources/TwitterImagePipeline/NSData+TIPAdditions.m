//
//  NSData+TIPAdditions.m
//  TwitterImagePipeline
//
//  Created on 9/9/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <objc/runtime.h>
#import "NSData+TIPAdditions.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSData (TIPAdditions)

- (NSData *)tip_safeSubdataNoCopyWithRange:(NSRange)subRange
{
    if (subRange.location == 0 && subRange.length == self.length) {
        // exact match, return early
        return self;
    }

    if (subRange.location + subRange.length > self.length) {
        // out of range, throw exception just like [NSData subdataWithRange:]
        NSString *subrangeString = NSStringFromRange(subRange);
        NSString *rangeString = NSStringFromRange(NSMakeRange(0, self.length));
        @throw [NSException exceptionWithName:NSRangeException
                                       reason:[NSString stringWithFormat:@"subdata %@ is out of range %@!", subrangeString, rangeString]
                                     userInfo:nil];
    }

    if (subRange.length == 0) {
        // zero length is still valid
        return [NSData data];
    }

#if __LP64__
    __block dispatch_data_t dispatchData = dispatch_data_create("", 0, NULL, NULL);
#else
    NSMutableData *mutableData = [[NSMutableData alloc] init];
#endif

    [self enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {

        if (byteRange.location >= (subRange.location + subRange.length)) {
            // past the end
            *stop = YES;
            return;
        }

        if ((byteRange.location + byteRange.length) <= subRange.location) {
            // before the beginning
            return;
        }

        NSRange cutRange = byteRange;
        NSInteger delta;

        delta = (NSInteger)subRange.location - (NSInteger)cutRange.location;
        if (delta > 0) {
            // byteRange provided offers excess bytes at the beginning, disregard those
            cutRange.length -= (NSUInteger)delta;
            cutRange.location = subRange.location;
        }

        delta = (NSInteger)(cutRange.location + cutRange.length) - (NSInteger)(subRange.location + subRange.length);
        if (delta > 0) {
            // byteRange provided offers excess bytes at the end, disregard those
            cutRange.length -= (NSUInteger)delta;
        }

        // find byte pointer, which is bytes plus our calculated offset for start of bytes
        const void *bytePtr = bytes + (cutRange.location - byteRange.location);

        // append the data as-is (no copy, no free when done)
#if __LP64__
        dispatch_data_t cutData = dispatch_data_create(bytePtr, cutRange.length, NULL, ^{ /*noop*/ });
        dispatchData = dispatch_data_create_concat(dispatchData, cutData);
#else // 32 bit
        NSData *rData = [NSData dataWithBytesNoCopy:(void*)bytePtr length:cutRange.length freeWhenDone:NO];
        [mutableData appendData:rData];
#endif

    }];

    NSData *retData = nil;
#if __LP64__
    retData = (NSData *)dispatchData; // nice!
#else // 32 bit
    retData = (NSData *)mutableData;
#endif

    // preserve the source data for the lifetime of the subdata
    objc_setAssociatedObject(retData, _cmd, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return retData;
}

- (nullable NSData *)tip_safeSubdataNoCopyWithRange:(NSRange)subRange error:(out NSError * __nullable * __nullable)outError
{
    NSData *data = nil;
    @try {

        data = [self tip_safeSubdataNoCopyWithRange:subRange];

    } @catch (NSException *e) {

        // convert the exception to an error (then return nil)
        if (outError) {
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                            code:[e.name isEqualToString:NSRangeException] ? ERANGE : EBADMSG
                                        userInfo:@{ @"exception" : e }];
        }

    }

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

