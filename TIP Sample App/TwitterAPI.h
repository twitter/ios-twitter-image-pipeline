//
//  TwitterAPI.h
//  TwitterImagePipeline
//
//  Created on 2/3/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIView.h>

NS_ASSUME_NONNULL_BEGIN

@interface TweetImageInfo : NSObject

@property (nonatomic, readonly, copy) NSString *baseURLString;
@property (nonatomic, readonly, copy) NSString *format;
@property (nonatomic, readonly) CGSize originalDimensions;

@end

@interface TweetInfo : NSObject

@property (nonatomic, readonly, copy) NSString *handle;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSArray<TweetImageInfo *> *images;

@end

@protocol TwitterAPIDelegate;

@interface TwitterAPI : NSObject

@property (nonatomic, weak) id<TwitterAPIDelegate> delegate;

+ (instancetype)sharedInstance;

- (void)searchForTerm:(NSString *)term count:(NSUInteger)count complete:(void (^)(NSArray<TweetInfo *> *, NSError *))complete;

@end

@protocol TwitterAPIDelegate <NSObject>

@optional
- (void)APIWorkStarted:(TwitterAPI *)api;
- (void)APIWorkFinished:(TwitterAPI *)api;

@end

FOUNDATION_EXTERN NSString *TweetImageDetermineVariant(CGSize aspectRatio, const CGSize targetDimensions, UIViewContentMode targetContentMode);

NS_ASSUME_NONNULL_END
