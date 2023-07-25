//
//  TIPFileUtilsTest.m
//  TwitterImagePipelineTests
//
//  Created on 5/3/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <XCTest/XCTest.h>

#include <sys/xattr.h>

@interface TIPFileUtilsTest : XCTestCase

@end

@implementation TIPFileUtilsTest

// Our use of getxattr relies on this property
- (void)testLargerThanDoubleXAttrReturnsErrorCode
{
    XCTSkipIf(sizeof(long double) <= sizeof(double)); //the test is invalid otherwise
    long double ldNumber = 1.23456;

    NSError *error = nil;
    NSString *tmpDir = NSTemporaryDirectory();
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:tmpDir isDirectory:NULL]);

    NSString *tmpFile = [tmpDir stringByAppendingPathComponent:@"tip_xattr_test"];
    [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:nil];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:tmpFile isDirectory:NULL]);

    [@"testFile" writeToFile:tmpFile atomically:YES encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);

    char *xAttrName = "tip_xattr_test_attr_name";
    const char *cStringPath = [tmpFile cStringUsingEncoding:NSUTF8StringEncoding];

    int writeReturnCode = setxattr(cStringPath, xAttrName, &ldNumber, sizeof(long double), 0, 0);
    XCTAssertEqual(writeReturnCode, 0);

    double readValue;
    ssize_t getReturnCode = getxattr(cStringPath, xAttrName, &readValue, sizeof(double), 0, 0);
    XCTAssertLessThan(getReturnCode, (ssize_t)0);
    XCTAssertEqual(errno, ERANGE);

    //Make sure tmpFile doesn't get deallocated before cStringUsingEncoding can be used
    NSLog(@"%@", tmpFile);

    [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:&error];
}

@end
