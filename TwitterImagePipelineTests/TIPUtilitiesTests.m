//
//  TIPUtilitiesTests.m
//  TwitterImagePipeline
//
//  Created on 5/12/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "TIP_Project.h"
#import "TIPImageContainer.h"
#import "TIPTests.h"
#import "UIImage+TIPAdditions.h"

@interface TIPUtilitiesTests : XCTestCase

@end

@implementation TIPUtilitiesTests

- (void)testHash
{
    NSArray *entries = @[
                        @[ @"Twitter", @"5392c950bdde4be7e5f5b8fdc6a1ca5f21e905cf" ],
                        @[ @"", @"da39a3ee5e6b4b0d3255bfef95601890afd80709" ],
                        @[ @" ", @"b858cb282617fb0956d960215c8e84d1ccf909c6" ],
                        @[ @"Atticus was feeble: he was nearly fifty. When Jem and I asked him why he was so old, he said he got started late, which we felt reflected upon his abilities and manliness. He was much older than the parents of our school contemporaries, and there was nothing Jem or I could say about him when our classmates said, 'My father – ' Jem was football crazy. Atticus was never too tired to play keep-away, but when Jem wanted to tackle him Atticus would say, 'I'm too old for that, son.' Our father didn't do anything. He worked in an office, not in a drugstore. Atticus did not drive a dump-truck for the county, he was not the sheriff, he did not farm, work in a garage, or do anything that could possibly arouse the admiration of anyone. Besides that, he wore glasses. He was nearly blind in his left eye, and said left eyes were the tribal curse of the Finches. Whenever he wanted to see something well, he turned his head and looked from his right eye. He did not do the things our schoolmates' fathers did; he never went hunting, he did not play poker or fish or drink or smoke. He sat in the living-room and read. With these attributes, however, he would not remain as inconspicuous as we wished him to; that year, the school buzzed with talk about him defending Tom Robinson, none of which was complimentary. After my bout with Cecil Jacobs when I committed myself to a policy of cowardice, word got around that Scout Finch wouldn't fight any more, her daddy wouldn't let her. This was not entirely correct: I wouldn't fight publicly for Atticus, but the family was private ground. I would fight anyone from a third cousin upwards tooth and nail. Francis Hancock, for example, knew that.                            When he gave us our air-rifles Atticus wouldn't teach us to shoot. Uncle Jack instructed us in the rudiments thereof; he said Atticus wasn't interested in guns, Atticus said to Jem one day, 'I'd rather you shot at tin cans in the back yard, but I know you'll go after birds. Shoot all the bluejays you want, if you can hit 'em, but remember it's a sin to kill a mockingbird.' That was the only time I heard Atticus say it was a sin to do something, and I asked Miss Maudie about it. 'Your father's right,' she said. 'Mockingbirds don't do one thing but make music for us to enjoy. They don't eat up people's gardens, don't nest in corncribs, they don't do one thing but sing their hearts out for us. That's why it's a sin to kill a mockingbird.'", @"57f12ff9069cc7438bd94dfb13b13f306fde2c5e" ],
                        @[ @"https%3A%2F%2Fo.twimg.com%2F2%2Fproxy.jpg%3Ft%3DHBiTAWh0dHBzOi8vdi5jZG4udmluZS5jby9yL3ZpZGVvcy82RjdBMzc5MjUyMTIwOTk5NDE4NTE5ODIxMTA3Ml8zOWM4YmY1NDVlNS4yLjEuMjMyMzYwNjUzOTk1MjIzNTMxMC5tcDQuanBnP3ZlcnNpb25JZD00Q2lTMXlxcjJKcXQxZTZxYjRJRFFFWDJQVFhNZF9hehTABxTABwAWABIA%26s%3D4ctujPcHgNhgqjzTJTUYntGpWnKhQgxk3rfO72jnzIw%26m%3D2", @"c34553b3af5b028595b03e3b74bcad0e35b4e87c" ]
                        ];

    for (NSArray *entry in entries) {
        NSString *string = entry.firstObject;
        NSString *hash = entry.lastObject;
        XCTAssertEqualObjects(hash, TIPHash(string));
    }
}

- (void)testSafeFromRaw
{
    NSArray *entries = @[
                         // Short, no hash
                         @[ @"Twitter", @"Twitter", @NO ],

                         // Short URL, no hash
                         @[ @"https://www.twitter.com/image/192.jpg", @"https%3A%2F%2Fwww.twitter.com%2Fimage%2F192.jpg", @NO ],

                         // Max length, no hash
                         @[ @"https://o.twimg.com/2/proxy.jpg?t=HBiTAWh0dHBzOi8vdi5jZG4udmluZS5jby9yL3ZpZGVvcy82RjdBMzc5MjUyMTIwOTk5NDE4NTE5ODIxMTA3Ml8zOWM4YmY1NDVlNS4yLjEuMjMyMzYwNjUzOTk1MjIzNTMxMC5tcDQuanBnP3ZlcnNpbKcXQxZTZxYjRJRFFFWDJQVFhNZF9hehTABxTABwIA&s=4c", @"https%3A%2F%2Fo.twimg.com%2F2%2Fproxy.jpg%3Ft%3DHBiTAWh0dHBzOi8vdi5jZG4udmluZS5jby9yL3ZpZGVvcy82RjdBMzc5MjUyMTIwOTk5NDE4NTE5ODIxMTA3Ml8zOWM4YmY1NDVlNS4yLjEuMjMyMzYwNjUzOTk1MjIzNTMxMC5tcDQuanBnP3ZlcnNpbKcXQxZTZxYjRJRFFFWDJQVFhNZF9hehTABxTABwIA%26s%3D4c", @NO ],

                         // Max length + 1, hash
                         @[ @"https://o.twimg.com/2/proxy.jpg?t=HBiTAWh0dHBzOi8vdi5jZG4udmluZS5jby9yL3ZpZGVvcy82RjdBMzc5MjUyMTIwOTk5NDE4NTE5ODIxMTA3Ml8zOWM4YmY1NDVlNS4yLjEuMjMyMzYwNjUzOTk1MjIzNTMxMC5tcDQuanBnP3ZlcnNpbJKcXQxZTZxYjRJRFFFWDJQVFhNZF9hehTABxTABwBIA&s=4ct", @"2940de9921a9c5b785d1aadf229f469b7b898602", @YES ],

                         // Way too long, hash
                         @[ @"https://o.twimg.com/2/proxy.jpg?t=HBiTAWh0dHBzOi8vdi5jZG4udmluZS5jby9yL3ZpZGVvcy82RjdBMzc5MjUyMTIwOTk5NDE4NTE5ODIxMTA3Ml8zOWM4YmY1NDVlNS4yLjEuMjMyMzYwNjUzOTk1MjIzNTMxMC5tcDQuanBnP3ZlcnNpb25JZD00Q2lTMXlxcjJKcXQxZTZxYjRJRFFFWDJQVFhNZF9hehTABxTABwAWABIA&s=4ctujPcHgNhgqjzTJTUYntGpWnKhQgxk3rfO72jnzIw&m=2", @"c34553b3af5b028595b03e3b74bcad0e35b4e87c", @YES ],
                        ];

    for (NSArray *entry in entries) {
        NSString *string = entry[0];
        NSString *safeString = entry[1];
        BOOL shouldBeHashed = [entry[2] boolValue];
        NSString *computedSafeString = TIPSafeFromRaw(string);
        NSString *computedRawString = TIPRawFromSafe(computedSafeString);
        XCTAssertEqualObjects(computedSafeString, safeString);
        if (shouldBeHashed) {
            XCTAssertEqualObjects(computedRawString, safeString);
        } else {
            XCTAssertEqualObjects(computedRawString, string);
        }
    }
}

- (void)testOddBoundaryScaling
{
    // We see lots of problems like this:
    /*
     <TIPProblemImageFailedToScale {
        animated = 0;
        dimensions = "NSSize: {1538, 2048}";
        scaledDimensions = "NSSize: {1243, 1656}";
        targetContentMode = 2;
        targetDimensions = "NSSize: {1242, 1656}";
     }>
     */
    // This unit test tries to catch that issue.
    // As of yet, it does not repro with unit test :(

    NSString *imagePath = [TIPTestsResourceBundle() pathForResource:@"1538x2048" ofType:@"jpg"];
    TIPImageContainer *originalImage = [TIPImageContainer imageContainerWithFilePath:imagePath decoderConfigMap:nil codecCatalogue:nil memoryMap:NO];
    XCTAssertNotNil(originalImage);
    XCTAssertEqual(originalImage.dimensions.width, (CGFloat)1538.0);
    XCTAssertEqual(originalImage.dimensions.height, (CGFloat)2048.0);

    TIPImageContainer *scaledImage;
    scaledImage = [originalImage scaleToTargetDimensions:CGSizeMake(1243, 1656) contentMode:UIViewContentModeScaleAspectFill];
    XCTAssertNotNil(scaledImage);
    scaledImage = nil;

    scaledImage = [originalImage scaleToTargetDimensions:CGSizeMake(1242, 1656) contentMode:UIViewContentModeScaleAspectFill];
    XCTAssertNotNil(scaledImage);
    scaledImage = nil;
}

- (void)testScalingWithOrientation
{
    NSString *imagePath = [TIPTestsResourceBundle() pathForResource:@"twitterfied" ofType:@"png"];
    TIPImageContainer *originalContainer = [TIPImageContainer imageContainerWithFilePath:imagePath decoderConfigMap:nil codecCatalogue:nil memoryMap:NO];
    XCTAssertEqual(originalContainer.dimensions.width, 1024);
    XCTAssertEqual(originalContainer.dimensions.height, 576);

    UIImage *leftyImage = [UIImage imageWithCGImage:originalContainer.image.CGImage scale:originalContainer.image.scale orientation:UIImageOrientationLeft];
    XCTAssertEqual(leftyImage.tip_dimensions.width, 576);
    XCTAssertEqual(leftyImage.tip_dimensions.height, 1024);

    UIImage *scaledLeftyImage1 = [leftyImage tip_scaledImageWithTargetDimensions:CGSizeMake(288, 512) contentMode:UIViewContentModeScaleAspectFit];
    XCTAssertEqual(scaledLeftyImage1.imageOrientation, UIImageOrientationUp);
    XCTAssertEqual(scaledLeftyImage1.tip_dimensions.width, 288);
    XCTAssertEqual(scaledLeftyImage1.tip_dimensions.height, 512);
}

#if 0
- (void)testScalingSpeed
{
    NSString *imagePath = [TIPTestsResourceBundle() pathForResource:@"1538x2048" ofType:@"jpg"];
    TIPImageContainer *originalImageContainer = [TIPImageContainer imageContainerWithFilePath:imagePath codecCatalogue:nil];
    XCTAssertNotNil(originalImageContainer);
    XCTAssertEqual(originalImageContainer.dimensions.width, (CGFloat)1538.0);
    XCTAssertEqual(originalImageContainer.dimensions.height, (CGFloat)2048.0);

    const CGSize scaledSize = CGSizeMake(1243, 1656);
    UIImage *originalImage = originalImageContainer.image;
    double count = 10;

    CFAbsoluteTime startUIKit = CFAbsoluteTimeGetCurrent();
    for (NSUInteger i = 0; i < count; i++) {
        @autoreleasepool {
            UIImage *scaledImage = [originalImage _tip_UIKit_scaleImageToSpecificDimensions:scaledSize scale:0.0];
            XCTAssertNotNil(scaledImage);
        }
    }
    CFAbsoluteTime endUIKit = CFAbsoluteTimeGetCurrent();

    CFAbsoluteTime startCoreGraphics = CFAbsoluteTimeGetCurrent();
    for (NSUInteger i = 0; i < count; i++) {
        @autoreleasepool {
            UIImage *scaledImage = [originalImage _tip_CoreGraphics_scaleImageToSpecificDimensions:scaledSize scale:0.0];
            XCTAssertNotNil(scaledImage);
        }
    }
    CFAbsoluteTime endCoreGraphics = CFAbsoluteTimeGetCurrent();

    NSLog(@"Tested Scaling Perf:\n"\
          @"UIKit:        %fs\n"\
          @"CoreGraphics: %fs\n", (endUIKit - startUIKit) / count, (endCoreGraphics - startCoreGraphics) / count);
}
#endif

@end
