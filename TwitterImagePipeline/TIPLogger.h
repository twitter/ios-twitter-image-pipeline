//
//  TIPLogger.h
//  TwitterImagePipeline
//
//  Created on 7/14/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 Syslog compatible log levels for use with *TIPLogger*.
 */
typedef NS_ENUM(NSInteger, TIPLogLevel)
{
    /** Present for syslog compatability */
    TIPLogLevelEmergency,
    /** Present for syslog compatability */
    TIPLogLevelAlert,
    /** Present for syslog compatability */
    TIPLogLevelCritical,
    /** The _ERROR_ log level */
    TIPLogLevelError,
    /** The _WARNING_ log level */
    TIPLogLevelWarning,
    /** Present for syslog compatability */
    TIPLogLevelNotice,
    /** The _INFORMATION_ log level */
    TIPLogLevelInformation,
    /** The _DEBUG_ log level */
    TIPLogLevelDebug
};

/**
 Protocol for supporting log statements from *TwitterImagePipeline*
 See `[TIPGlobalConfiguration logger]`
 */
@protocol TIPLogger <NSObject>

@required

/**
 Method called when logging a message from *TwitterImagePipeline*
 */
- (void)tip_logWithLevel:(TIPLogLevel)level file:(nonnull NSString *)file function:(nonnull NSString *)function line:(int)line message:(nonnull NSString *)message;

@optional

/**
 Optional method to determine if a message should be logged as an optimization to avoid argument
 execution of the log message.

 Default == `YES`
 */
- (BOOL)tip_canLogWithLevel:(TIPLogLevel)level;

@end
