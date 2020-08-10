//
//  TIPFileUtils.m
//  TwitterImagePipeline
//
//  Created on 7/14/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#include <dirent.h>
#include <objc/runtime.h>
#include <sys/stat.h>
#include <sys/xattr.h>

#import "TIP_Project.h"
#import "TIPFileUtils.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - File Helpers

NSArray<NSURL *> * __nullable TIPContentsAtPath(NSString *path,
                                                NSError * __nullable * __nullable outError)
{
    NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSError *error = nil;
    NSArray<NSURL *> *paths = [fm contentsOfDirectoryAtURL:url includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLContentModificationDateKey, NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsSubdirectoryDescendants error:&error];
    if (outError) {
        *outError = error;
    }

    return paths;
}

NSUInteger TIPFileSizeAtPath(NSString *path,
                             NSError * __nullable * __nullable outError)
{
    NSError *error = nil;
    NSUInteger size = 0;
    if (path.length > 0) {
        struct stat fileStatStruct;
        if (0 != stat(path.UTF8String, &fileStatStruct)) {
            error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                        code:errno
                                    userInfo:nil];
        } else if (fileStatStruct.st_size < 0) {
            error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                        code:EBADF
                                    userInfo:nil];
        } else {
            size = (NSUInteger)fileStatStruct.st_size;
        }
    }

    if (error && outError) {
        *outError = error;
    }
    return size;
}

NSDate * __nullable TIPLastModifiedDateAtPath(NSString *path)
{
    return TIPLastModifiedDateAtPathURL([NSURL fileURLWithPath:path]);
}

NSDate * __nullable TIPLastModifiedDateAtPathURL(NSURL *pathURL)
{
    NSDate *date = nil;
    [pathURL getResourceValue:&date
                       forKey:NSURLContentModificationDateKey
                        error:NULL];
    return date;
}

void TIPSetLastModifiedDateAtPath(NSString * path, NSDate *date)
{
    TIPSetLastModifiedDateAtPathURL([NSURL fileURLWithPath:path], date);
}

void TIPSetLastModifiedDateAtPathURL(NSURL *pathURL, NSDate *date)
{
    [pathURL setResourceValue:date
                       forKey:NSURLContentModificationDateKey
                        error:NULL];
}

#pragma mark - File Extended Attribute Helpers

NSArray<NSString *> * __nullable TIPListXAttributesForFile(NSString *filePath)
{
    const char *cFilePath = filePath.fileSystemRepresentation;
    const ssize_t listStringSize = listxattr(cFilePath, NULL, 0, 0);
    if (listStringSize < 0) {
        return nil;
    } else if (listStringSize == 0) {
        return @[];
    }

    char* listBuff = (char*)malloc((size_t)(listStringSize + 1));
    listBuff[listStringSize] = '\0';

    // make the buffer ARC controlled (freed when no longer used)
    NSData *listData = [NSData dataWithBytesNoCopy:listBuff
                                            length:(NSUInteger)(listStringSize + 1)
                                      freeWhenDone:YES];
    if (listxattr(cFilePath, listBuff, (size_t)listStringSize, 0) < 0) {
        return nil;
    }

    NSMutableArray<NSString *> *attributeNames = [[NSMutableArray alloc] init];
    char *head = listBuff;
    char *cur = listBuff;
    char *end = listBuff + listStringSize;
    for (; cur < end; cur++) {
        if (*cur == '\0') {
            NSString *attributeName = [[NSString alloc] initWithBytesNoCopy:head
                                                                     length:(NSUInteger)(cur - head)
                                                                   encoding:NSUTF8StringEncoding
                                                               freeWhenDone:NO];
            if (attributeName) {
                [attributeNames addObject:attributeName];

                // Associate the NSString with the source NSData to keep the data properly ref counted
                static const char kAssociatedDataKey[] = "data_ref";
                objc_setAssociatedObject(attributeName, &kAssociatedDataKey, listData, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }

            cur++;
            head = cur;
        }
    }

    return attributeNames;
}

NSDictionary *TIPGetXAttributesForFile(NSString *filePath, NSDictionary *keyKindMap)
{
    const char *cFilePath = filePath.fileSystemRepresentation;
    NSMutableDictionary *xattrs = [NSMutableDictionary dictionaryWithCapacity:keyKindMap.count];
    for (NSString *name in keyKindMap) {
        id value;
        const char *attrName = name.UTF8String;
        Class kind = keyKindMap[name];

        if ([kind isSubclassOfClass:[NSNumber class]]) {
            value = TIPGetXAttributeNumberFromFile(attrName, cFilePath);
        } else if ([kind isSubclassOfClass:[NSString class]]) {
            value = TIPGetXAttributeStringFromFile(attrName, cFilePath);
        } else if ([kind isSubclassOfClass:[NSDate class]]) {
            value = TIPGetXAttributeDateFromFile(attrName, cFilePath);
        } else if ([kind isSubclassOfClass:[NSURL class]]) {
            value = TIPGetXAttributeURLFromFile(attrName, cFilePath);
        }

        if (value) {
            xattrs[name] = value;
        }
    }
    return xattrs;
}

NSUInteger TIPSetXAttributesForFile(NSDictionary *xattrs, NSString *filePath)
{
    NSUInteger setCount = 0;
    const char *cFilePath = filePath.fileSystemRepresentation;
    for (NSString *name in xattrs) {
        int result = -1;
        const char *attrName = name.UTF8String;

        id value = xattrs[name];
        if ([value isKindOfClass:[NSNumber class]]) {
            result = TIPSetXAttributeNumberForFile(attrName, value, cFilePath);
        } else if ([value isKindOfClass:[NSString class]]) {
            result = TIPSetXAttributeStringForFile(attrName, value, cFilePath);
        } else if ([value isKindOfClass:[NSDate class]]) {
            result = TIPSetXAttributeDateForFile(attrName, value, cFilePath);
        } else if ([value isKindOfClass:[NSURL class]]) {
            result = TIPSetXAttributeURLForFile(attrName, value, cFilePath);
        }

        if (0 != result) {
            int errorInt = errno;
            TIPLogWarning(@"Failed to setxattr '%@' on '%@': %i", name, filePath, errorInt);
            if (ENOENT == errorInt) {
                // The file doesn't exist, bail early
                break;
            }
        } else {
            setCount++;
        }
    }

    return setCount;
}

int TIPSetXAttributeDateForFile(const char *name, NSDate *date, const char *filePath)
{
    NSTimeInterval ti = [date timeIntervalSinceReferenceDate];
    return TIPSetXAttributeNumberForFile(name, @(ti), filePath);
}

int TIPSetXAttributeStringForFile(const char *name, NSString *string, const char *filePath)
{
    const char *value = string.UTF8String;
    return setxattr(filePath, name, value, strlen(value), 0, 0);
}

int TIPSetXAttributeNumberForFile(const char *name, NSNumber *number, const char *filePath)
{
    double value = number.doubleValue;
    return setxattr(filePath, name, &value, sizeof(double), 0, 0);
}

int TIPSetXAttributeURLForFile(const char *name, NSURL *URL, const char *filePath)
{
    NSString *URLString = [URL absoluteString];
    return TIPSetXAttributeStringForFile(name, URLString, filePath);
}

NSString * __nullable TIPGetXAttributeStringFromFile(const char *name, const char *filePath)
{
    static const NSUInteger kStackBufferSize = 1024;
    char stackBuffer[kStackBufferSize];

    ssize_t bytesRead = getxattr(filePath, name, &stackBuffer, kStackBufferSize, 0, 0);
    if (bytesRead > 0) {
        // copy to heap in NSString
        return [[NSString alloc] initWithBytes:stackBuffer
                                        length:(NSUInteger)bytesRead
                                      encoding:NSUTF8StringEncoding];
    } else if (bytesRead == 0) {
        // no attribute
        return nil;
    } else if (errno != ERANGE) {
        // attribute access error is not recoverable
        return nil;
    }

    bytesRead = getxattr(filePath, name, NULL, 0, 0, 0);
    if (bytesRead <= 0) {
        // Failure to load attribute
        return nil;
    }

    char *buffer = (char *)malloc((size_t)bytesRead);
    if (getxattr(filePath, name, buffer, (size_t)bytesRead, 0, 0) <= 0) {
        // Failure to read attribute
        free(buffer);
        return nil;
    }

    // Return attribute as NSString on heap (use malloc'd buffer directly)
    return [[NSString alloc] initWithBytesNoCopy:buffer
                                          length:(NSUInteger)bytesRead
                                        encoding:NSUTF8StringEncoding
                                    freeWhenDone:YES];
}

NSNumber * __nullable TIPGetXAttributeNumberFromFile(const char *name, const char *filePath)
{
    double number;
    const ssize_t bufferLength = getxattr(filePath, name, &number, sizeof(double), 0, 0);
    if (bufferLength != sizeof(double)) {
        // failure to load attribute or failure to read attribute or incorrect format of attribute
        return nil;
    }
    return @(number);
}

NSDate * __nullable TIPGetXAttributeDateFromFile(const char *name, const char *filePath)
{
    NSNumber *number = TIPGetXAttributeNumberFromFile(name, filePath);
    if (!number) {
        return nil;
    }

    return [NSDate dateWithTimeIntervalSinceReferenceDate:[number doubleValue]];
}

NSURL * __nullable TIPGetXAttributeURLFromFile(const char *name, const char *filePath)
{
    NSString *URLString = TIPGetXAttributeStringFromFile(name, filePath);
    NSURL *URL = nil;
    @try {
        URL = [NSURL URLWithString:URLString];
    } @catch (NSException *) {
    }
    return URL;
}

NS_ASSUME_NONNULL_END
