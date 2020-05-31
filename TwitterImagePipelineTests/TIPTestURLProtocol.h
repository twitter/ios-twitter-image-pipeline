//
//  TIPTestURLProtocol.h
//  TwitterImagePipeline
//
//  Created on 9/9/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString * const TIPTestURLProtocolErrorDomain;

@class TIPTestURLProtocolResponseConfig;

@interface TIPTestURLProtocol : NSURLProtocol

+ (void)registerURLResponse:(NSHTTPURLResponse *)response
                       body:(nullable NSData *)body
                     config:(nullable TIPTestURLProtocolResponseConfig *)config
               withEndpoint:(NSURL *)endpoint;
+ (void)registerURLResponse:(NSHTTPURLResponse *)response
                       body:(nullable NSData *)body
               withEndpoint:(NSURL *)endpoint;

+ (void)unregisterEndpoint:(NSURL *)endpoint;
+ (void)unregisterAllEndpoints;

+ (BOOL)isEndpointRegistered:(NSURL *)endpoint;

@end

typedef NS_ENUM(NSUInteger, TIPTestURLProtocolRedirectBehavior) {
    TIPTestURLProtocolRedirectBehaviorFollowLocation = 0,
    TIPTestURLProtocolRedirectBehaviorDontFollowLocation = 1,
    TIPTestURLProtocolRedirectBehaviorFollowLocationIfRedirectResponseIsRegistered = 2,
};

@interface TIPTestURLProtocolResponseConfig : NSObject <NSCopying>

@property (nonatomic) uint64_t bps; // bits per second, 0 == unlimited
@property (nonatomic) uint64_t latency; // in milliseconds
@property (nonatomic) uint64_t delay; // in milliseconds
@property (nonatomic, nullable) NSError *failureError; // nil == no error
@property (nonatomic) NSInteger statusCode; // 0 == don't override
@property (nonatomic) BOOL canProvideRange; // default == YES
@property (nonatomic, copy, nullable) NSString *stringForIfRange; // default == nil, nil == match any, @"" == match nothing
@property (nonatomic) TIPTestURLProtocolRedirectBehavior redirectBehavior; // default == .FollowLocation

@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *extraRequestHeaders;

@end

NS_ASSUME_NONNULL_END
