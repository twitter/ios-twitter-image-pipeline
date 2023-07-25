//
//  AppDelegate.h
//  TIP Sample App
//
//  Created on 2/3/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <UIKit/UIKit.h>

@class TIPImagePipeline;

#define APP_DELEGATE ((AppDelegate *)[UIApplication sharedApplication].delegate)

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) UITabBarController *tabBarController;
@property (strong, nonatomic, readonly) TIPImagePipeline *imagePipeline;

// Mutable settings

@property (nonatomic) NSUInteger searchCount;
@property (nonatomic) BOOL searchWebP;
@property (nonatomic) BOOL usePlaceholder;
@property (nonatomic, getter=isDebugInfoVisible) BOOL debugInfoVisible;

// Methods

- (void)incrementNetworkOperations;
- (void)decrementNetworkOperations;

@end

