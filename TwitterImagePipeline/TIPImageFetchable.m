//
//  TIPImageFetchable.m
//  TwitterImagePipeline
//
//  Created on 09/03/18.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "TIP_Project.h"
#import "TIPImageContainer.h"
#import "TIPImageFetchable.h"

NS_ASSUME_NONNULL_BEGIN

BOOL TIPImageFetchableHasImage(id<TIPImageFetchable> __nullable fetchable)
{
    if (!fetchable) {
        return NO;
    }

    if ([fetchable respondsToSelector:@selector(tip_fetchedImageContainer)]) {
        return (fetchable.tip_fetchedImageContainer != nil);
    }

    if ([fetchable respondsToSelector:@selector(tip_fetchedImage)]) {
        return (fetchable.tip_fetchedImage != nil);
    }

    TIPAssertNever();
    return NO;
}

UIImage * __nullable TIPImageFetchableGetImage(id<TIPImageFetchable> __nullable fetchable)
{
    if (!fetchable) {
        return nil;
    }

    if ([fetchable respondsToSelector:@selector(tip_fetchedImageContainer)]) {
        return fetchable.tip_fetchedImageContainer.image;
    }

    if ([fetchable respondsToSelector:@selector(tip_fetchedImage)]) {
        return fetchable.tip_fetchedImage;
    }

    TIPAssertNever();
    return nil;
}

TIPImageContainer * __nullable TIPImageFetchableGetImageContainer(id<TIPImageFetchable> __nullable fetchable)
{
    if (!fetchable) {
        return nil;
    }

    if ([fetchable respondsToSelector:@selector(tip_fetchedImageContainer)]) {
        return fetchable.tip_fetchedImageContainer;
    }

    if ([fetchable respondsToSelector:@selector(tip_fetchedImage)]) {
        UIImage *image = fetchable.tip_fetchedImage;
        return (image) ? [[TIPImageContainer alloc] initWithImage:image] : nil;
    }

    TIPAssertNever();
    return nil;
}

void TIPImageFetchableSetImage(id<TIPImageFetchable> __nullable fetchable, UIImage * __nullable image)
{
    if (!fetchable) {
        return;
    }

    if ([fetchable respondsToSelector:@selector(setTip_fetchedImageContainer:)]) {
        TIPImageContainer *container = (image) ? [[TIPImageContainer alloc] initWithImage:image] : nil;
        fetchable.tip_fetchedImageContainer = container;
        return;
    }

    if ([fetchable respondsToSelector:@selector(setTip_fetchedImage:)]) {
        fetchable.tip_fetchedImage = image;
        return;
    }

    TIPAssertNever();
}

void TIPImageFetchableSetImageContainer(id<TIPImageFetchable> __nullable fetchable, TIPImageContainer * __nullable imageContainer)
{
    if (!fetchable) {
        return;
    }

    if ([fetchable respondsToSelector:@selector(setTip_fetchedImageContainer:)]) {
        fetchable.tip_fetchedImageContainer = imageContainer;
        return;
    }

    if ([fetchable respondsToSelector:@selector(setTip_fetchedImage:)]) {
        fetchable.tip_fetchedImage = imageContainer.image;
        return;
    }

    TIPAssertNever();
}

NS_ASSUME_NONNULL_END
