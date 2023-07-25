//
//  AppDelegate.m
//  TIP Sample App
//
//  Created on 2/3/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterImagePipeline.h>

#import "AppDelegate.h"
#import "InspectorViewController.h"
#import "SettingsViewController.h"
#import "TIPXWebPCodec.h"
#import "TwitterAPI.h"
#import "TwitterSearchViewController.h"


@interface AppDelegate () <TIPLogger, TIPImagePipelineObserver, TwitterAPIDelegate, TIPImageAdditionalCache>
{
    NSInteger _opCount;
}
@end

@implementation AppDelegate

- (BOOL)isDebugInfoVisible
{
    return [TIPImageViewFetchHelper isDebugInfoVisible];
}

- (void)setDebugInfoVisible:(BOOL)debugInfoVisible
{
    [TIPImageViewFetchHelper setDebugInfoVisible:debugInfoVisible];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [TIPGlobalConfiguration sharedInstance].logger = self;
    [TIPGlobalConfiguration sharedInstance].serializeCGContextAccess = YES;
    [TIPGlobalConfiguration sharedInstance].clearMemoryCachesOnApplicationBackgroundEnabled = YES;
    [[TIPGlobalConfiguration sharedInstance] addImagePipelineObserver:self];
    [[TIPImageCodecCatalogue sharedInstance] setCodec:[[TIPXWebPCodec alloc] initWithPreferredCodec:nil] forImageType:TIPImageTypeWEBP];
    _imagePipeline = [[TIPImagePipeline alloc] initWithIdentifier:@"Twitter.Example"];
    _imagePipeline.additionalCaches = @[self];
    [TwitterAPI sharedInstance].delegate = self;

    _searchCount = 100;



    UIColor *lightBlueColor = [UIColor colorWithRed:(CGFloat)(150./255.) green:(CGFloat)(215./255.) blue:1 alpha:0];
    [UISearchBar appearance].barTintColor = lightBlueColor;
    [UISearchBar appearance].tintColor = [UIColor whiteColor];
    [UITextField appearanceWhenContainedInInstancesOfClasses:@[[UISearchBar class]]].tintColor = lightBlueColor;
    [UINavigationBar appearance].barTintColor = lightBlueColor;
    [UINavigationBar appearance].tintColor = [UIColor whiteColor];
    [[UINavigationBar appearance] setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor whiteColor]
                                                           }];
    [UITabBar appearance].barTintColor = lightBlueColor;
    [UITabBar appearance].tintColor = [UIColor whiteColor];
    [UISlider appearance].minimumTrackTintColor = lightBlueColor;
    [UISlider appearance].tintColor = lightBlueColor;
    [UIWindow appearance].tintColor = lightBlueColor;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    UINavigationController *firstNavController = [[UINavigationController alloc] initWithRootViewController:[[TwitterSearchViewController alloc] init]];
    firstNavController.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Search" image:[UIImage imageNamed:@"first"] tag:1];
    UINavigationController *secondNavController = [[UINavigationController alloc] initWithRootViewController:[[SettingsViewController alloc] init]];
    secondNavController.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings" image:[UIImage imageNamed:@"second"] tag:2];
    UINavigationController *thirdNavController = [[UINavigationController alloc] initWithRootViewController:[[InspectorViewController alloc] init]];
    thirdNavController.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Inspector" image:[UIImage imageNamed:@"first"] tag:3];

    self.tabBarController = [[UITabBarController alloc] init];
    self.tabBarController.viewControllers = @[ firstNavController,
                                               secondNavController,
                                               thirdNavController ];

    self.window.rootViewController = self.tabBarController;
    self.window.backgroundColor = [UIColor orangeColor];
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)_private_incrementNetworkOperations
{
    if ((++_opCount) > 0) {
#if !TARGET_OS_MACCATALYST
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
#endif
    }
}

- (void)_private_decrementNetworkOperations
{
    if ((--_opCount) <= 0) {
#if !TARGET_OS_MACCATALYST
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
#endif
    }
}

- (void)incrementNetworkOperations
{
    if ([NSThread isMainThread]) {
        [self _private_incrementNetworkOperations];
    } else {
        [self performSelectorOnMainThread:@selector(_private_incrementNetworkOperations) withObject:nil waitUntilDone:NO];
    }
}

- (void)decrementNetworkOperations
{
    if ([NSThread isMainThread]) {
        [self _private_decrementNetworkOperations];
    } else {
        [self performSelectorOnMainThread:@selector(_private_decrementNetworkOperations) withObject:nil waitUntilDone:NO];
    }
}

#pragma mark API Delegate

- (void)APIWorkStarted:(TwitterAPI *)api
{
    [self incrementNetworkOperations];
}

- (void)APIWorkFinished:(TwitterAPI *)api
{
    [self decrementNetworkOperations];
}

#pragma mark Observer

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didStartDownloadingImageAtURL:(NSURL *)URL
{
    [self incrementNetworkOperations];
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op didFinishDownloadingImageAtURL:(NSURL *)URL imageType:(NSString *)type sizeInBytes:(NSUInteger)byteSize dimensions:(CGSize)dimensions wasResumed:(BOOL)wasResumed
{
    [self decrementNetworkOperations];
}

#pragma mark Logger

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

#pragma mark Additional Cache

- (void)tip_retrieveImageForURL:(NSURL *)URL completion:(TIPImageAdditionalCacheFetchCompletion)completion
{
    UIImage *image = nil;
    if ([URL.scheme isEqualToString:@"placeholder"]) {
        if ([URL.host isEqualToString:@"placeholder.com"]) {
            if ([URL.lastPathComponent isEqualToString:@"placeholder.jpg"]) {
                static UIImage *placeholderImage = nil;
                if (!placeholderImage) {
                    placeholderImage = [UIImage imageNamed:@"placeholder.jpg"];
                }
                image = placeholderImage;
            }
        }
    }
    completion(image);
}

@end
