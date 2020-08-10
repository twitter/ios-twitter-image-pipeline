//
//  TIPFileUtils.h
//  TwitterImagePipeline
//
//  Created on 7/14/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - File Helpers

//! Return the files (and directories) within the directory at the given _path_
FOUNDATION_EXTERN NSArray<NSURL *> * __nullable TIPContentsAtPath(NSString *dirPath,
                                                                  NSError * __nullable * __nullable outError);
//! Return the size of the file at the given path
FOUNDATION_EXTERN NSUInteger TIPFileSizeAtPath(NSString *filePath,
                                               NSError * __nullable * __nullable outError);

//! Return the last modified date of the file at the given _path_
FOUNDATION_EXTERN NSDate * __nullable TIPLastModifiedDateAtPath(NSString *path);
//! Return the last modified date of the file at the given _pathURL_
FOUNDATION_EXTERN NSDate * __nullable TIPLastModifiedDateAtPathURL(NSURL *pathURL);

//! Set the last modified _date_ of the file at the given _path_
FOUNDATION_EXTERN void TIPSetLastModifiedDateAtPath(NSString *path,
                                                    NSDate *date);
//! Set the last modified _date_ of the file at the given _pathURL_
FOUNDATION_EXTERN void TIPSetLastModifiedDateAtPathURL(NSURL *pathURL,
                                                       NSDate *date);

#pragma mark - File Extended Attribute Helpers

/**
 keys to pull out of xattrs and kind is the object to store it as.
 Example: `@{ @"timestamp" : [NSDate class] }`.
 Supports `NSNumber<double>`, `NSString`, `NSDate` and `NSURL`.
 Anything unsupported will not be retrieved.
 */
FOUNDATION_EXTERN NSDictionary<NSString *, id> * __nullable TIPGetXAttributesForFile(NSString *filePath,
                                                                                     NSDictionary<NSString *, Class> *keyKindMap);

/**
 Supports objects that are `NSNumber<double>`, `NSString`, `NSDate` and `NSURL`
 Returns the number of entries that succeeded.
 If returned count != xattrs.count, you know there was an error.
 */
FOUNDATION_EXTERN NSUInteger TIPSetXAttributesForFile(NSDictionary<NSString *, id> *xattrs,
                                                      NSString *filePath);

//! Returns an array of xattr names for the file at the given _filePath_
FOUNDATION_EXTERN NSArray<NSString *> * __nullable TIPListXAttributesForFile(NSString *filePath);

/** Below functions return `0` on success, otherwise `errno` will be set with the error */

//! Set _number_ as the attribute with the given _name_ for _filePath_
FOUNDATION_EXTERN int TIPSetXAttributeNumberForFile(const char *name,
                                                    NSNumber *number,
                                                    const char *filePath);
//! Set _string_ as the attribute with the given _name_ for _filePath_
FOUNDATION_EXTERN int TIPSetXAttributeStringForFile(const char *name,
                                                    NSString *string,
                                                    const char *filePath);
//! Set _date_ as the attribute with the given _name_ for _filePath_
FOUNDATION_EXTERN int TIPSetXAttributeDateForFile(const char *name,
                                                  NSDate *date,
                                                  const char *filePath);
//! Set _url_ as the attribute with the given _name_ for _filePath_
FOUNDATION_EXTERN int TIPSetXAttributeURLForFile(const char *name,
                                                 NSURL *url,
                                                 const char *filePath);

//! Return the `NSString` for the attribute with the given _name_ for _filePath_ (or `nil`)
FOUNDATION_EXTERN NSString * __nullable TIPGetXAttributeStringFromFile(const char *name,
                                                                       const char *filePath);
//! Return the `NSNumber` for the attribute with the given _name_ for _filePath_ (or `nil`)
FOUNDATION_EXTERN NSNumber * __nullable TIPGetXAttributeNumberFromFile(const char *name,
                                                                       const char *filePath);
//! Return the `NSDate` for the attribute with the given _name_ for _filePath_ (or `nil`)
FOUNDATION_EXTERN NSDate * __nullable TIPGetXAttributeDateFromFile(const char *name,
                                                                   const char *filePath);
//! Return the `NSURL` for the attribute with the given _name_ for _filePath_ (or `nil`)
FOUNDATION_EXTERN NSURL * __nullable TIPGetXAttributeURLFromFile(const char *name,
                                                                 const char *filePath);

NS_ASSUME_NONNULL_END
