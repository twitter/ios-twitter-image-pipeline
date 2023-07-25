//
//  AppDelegate.m
//  ImageSpeedComparison
//
//  Created on 9/4/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <TwitterImagePipeline.h>

#import "AppDelegate.h"
#import "TIPXWebPCodec.h"

@interface AppDelegate ()
@end

@interface AppDelegate (Logger) <TIPLogger>
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [TIPGlobalConfiguration sharedInstance].logger = self;
    [[TIPImageCodecCatalogue sharedInstance] replaceCodecForImageType:TIPImageTypeWEBP usingBlock:^id<TIPImageCodec> _Nonnull(id<TIPImageCodec>  _Nullable existingCodec) {
        return [[TIPXWebPCodec alloc] initWithPreferredCodec:nil];//existingCodec];
    }];
    return YES;
}

- (void)tip_logWithLevel:(TIPLogLevel)level file:(NSString *)file function:(NSString *)function line:(int)line message:(NSString *)message
{
    NSString *levelString = nil;
    switch (level) {
        case TIPLogLevelEmergency:
        case TIPLogLevelAlert:
        case TIPLogLevelCritical:
        case TIPLogLevelError:
            levelString = @"ERR";
            break;
        case TIPLogLevelWarning:
            levelString = @"WRN";
            break;
        case TIPLogLevelNotice:
        case TIPLogLevelInformation:
            levelString = @"INF";
            break;
        case TIPLogLevelDebug:
            levelString = @"DBG";
            break;
    }

    NSLog(@"[%@]: %@", levelString, message);
}

@end
