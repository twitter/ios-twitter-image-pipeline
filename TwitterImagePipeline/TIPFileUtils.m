//
//  TIPFileUtils.m
//  TwitterImagePipeline
//
//  Created on 7/14/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#include <dirent.h>
#include <sys/stat.h>
#include <sys/xattr.h>

#import "TIP_Project.h"
#import "TIPFileUtils.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - File Helpers

NSArray<NSString *> * __nullable TIPContentsAtPath(NSString *path,
                                                   NSError * __nullable * __nullable outError)
{
    DIR *dir = opendir(path.UTF8String);
    if (!dir) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                            code:errno
                                        userInfo:nil];
        }
        return nil;
    }

    NSMutableArray *entries = [[NSMutableArray alloc] init];
    struct dirent *dirEntity = NULL;
    while ((dirEntity = readdir(dir)) != NULL) {
        if (0 == strcmp(".", dirEntity->d_name) || 0 == strcmp("..", dirEntity->d_name)) {
            continue;
        }

        @autoreleasepool {
            NSString *fileName = [[NSString alloc] initWithUTF8String:dirEntity->d_name];
            if (fileName) {
                [entries addObject:fileName];
            }
        }
    }
    closedir(dir);
    return entries;
}

NSUInteger TIPFileSizeAtPath(NSString *path,
                             NSError * __nullable * __nullable outError)
{
    NSUInteger size = 0;
    if (path.length > 0) {
        struct stat fileStatStruct;
        if (0 != stat(path.UTF8String, &fileStatStruct)) {
            if (outError) {
                *outError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                code:errno
                                            userInfo:nil];
            }
        } else {
            if (fileStatStruct.st_size < 0) {
                if (outError) {
                    *outError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                    code:EBADF
                                                userInfo:nil];
                }
            } else {
                size = (NSUInteger)fileStatStruct.st_size;
            }
        }
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
    [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate : date}
                                     ofItemAtPath:path
                                            error:NULL];
}

void TIPSetLastModifiedDateAtPathURL(NSURL *pathURL, NSDate *date)
{
    TIPSetLastModifiedDateAtPath(pathURL.path, date);
}

#pragma mark - File Extended Attribute Helpers

NSArray<NSString *> * __nullable TIPListXAttributesForFile(NSString *filePath)
{
    const char *cFilePath = filePath.fileSystemRepresentation;
    const ssize_t listStringSize = listxattr(cFilePath, NULL, 0, 0);
    if (listStringSize < 0) {
        return nil;
    }

    char listBuff[listStringSize + 1];
    listBuff[listStringSize] = '\0';

    if (listxattr(cFilePath, listBuff, (size_t)listStringSize, 0) < 0) {
        return nil;
    }

    NSMutableArray<NSString *> *attributeNames = [[NSMutableArray alloc] init];
    char *head = listBuff;
    char *cur = listBuff;
    char *end = listBuff + listStringSize;
    for (; cur < end; cur++) {
        if (*cur == '\0') {
            NSString *attributeName = [[NSString alloc] initWithBytes:head
                                                               length:(NSUInteger)(cur - head)
                                                             encoding:NSUTF8StringEncoding];
            if (attributeName) {
                [attributeNames addObject:attributeName];
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
    ssize_t bufferLength = getxattr(filePath, name, NULL, 0, 0, 0);
    if (bufferLength <= 0) {
        return nil;
    }

    char *buffer = (char *)malloc((size_t)bufferLength);
    if (getxattr(filePath, name, buffer, (size_t)bufferLength, 0, 0) <= 0) {
        free(buffer);
        return nil;
    }

    return [[NSString alloc] initWithBytesNoCopy:buffer
                                          length:(NSUInteger)bufferLength
                                        encoding:NSUTF8StringEncoding
                                    freeWhenDone:YES];
}

NSNumber * __nullable TIPGetXAttributeNumberFromFile(const char *name, const char *filePath)
{
    ssize_t bufferLength = getxattr(filePath, name, NULL, 0, 0, 0);
    if (bufferLength != sizeof(double)) {
        return nil;
    }

    double number;
    if (getxattr(filePath, name, &number, sizeof(double), 0, 0) <= 0) {
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
