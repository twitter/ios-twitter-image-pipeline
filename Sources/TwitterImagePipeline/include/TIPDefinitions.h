//
//  TIPDefinitions.h
//  TwitterImagePipeline
//
//  Created on 2/18/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 The source that an image was loaded from
 */
typedef NS_ENUM(NSInteger, TIPImageLoadSource) {
    /** Unknown */
    TIPImageLoadSourceUnknown = 0,
    /** The in memory cache */
    TIPImageLoadSourceMemoryCache,
    /** The on disk cache */
    TIPImageLoadSourceDiskCache,
    /** The additional cache */
    TIPImageLoadSourceAdditionalCache,
    /** The _Network_ */
    TIPImageLoadSourceNetwork,
    /** The _Network_, but was resumed from a disk cache entry */
    TIPImageLoadSourceNetworkResumed,
};

static const TIPImageLoadSource TIPImageLoadSourceMaxValue = TIPImageLoadSourceNetworkResumed;

/**
 Target loading sources values for the loading sources mask
 */
typedef NS_OPTIONS(NSInteger, TIPImageFetchLoadingSources) {
    /** Load from Memory Cache(s) */
    TIPImageFetchLoadingSourceMemoryCache = (1 << TIPImageLoadSourceMemoryCache),
    /** Load from Disk Cache */
    TIPImageFetchLoadingSourceDiskCache = (1 << TIPImageLoadSourceDiskCache),
    /** Load from Additional Cache(s) */
    TIPImageFetchLoadingSourceAdditionalCache = (1 << TIPImageLoadSourceAdditionalCache),
    /** Load from Network */
    TIPImageFetchLoadingSourceNetwork = (1 << TIPImageLoadSourceNetwork),
    /** Load from Network Resumption */
    TIPImageFetchLoadingSourceNetworkResumed = (1 << TIPImageLoadSourceNetworkResumed),
};

static const TIPImageFetchLoadingSources TIPImageFetchLoadingSourcesNone = (TIPImageFetchLoadingSources)0;
static const TIPImageFetchLoadingSources TIPImageFetchLoadingSourcesAll = (TIPImageFetchLoadingSources)0xFF;

/**
 An interface for an operation-like object.

 Supports being a dependency of other `NSOperation` objects, `waitUntilFinished` and KVO observing
 of `isFinished` and `isExecuting`
 */
@protocol TIPDependencyOperation <NSObject>

@required

/**
 Same effect as `[op addDependency:self]`, if the `TIPDependencyOperation` was an `NSOperation`
 (which it is not...really...it is not an `NSOperation`...)
 */
- (void)makeDependencyOfTargetOperation:(nonnull NSOperation *)op;

/**
 See `[NSOperation waitUntilFinished]`
 */
- (void)waitUntilFinished;

/**
 See `[NSOperation isFinished]`.
 KVO Compliant.
 */
- (BOOL)isFinished;

/**
 See `[NSOperation isExecuting]`.
 KVO Compliant.
 */
- (BOOL)isExecuting;

@end


