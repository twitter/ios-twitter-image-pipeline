//
//  TIPLRUCache.h
//  TwitterImagePipeline
//
//  Created on 10/27/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol TIPLRUCacheDelegate;
@protocol TIPLRUEntry;

@interface TIPLRUCache : NSObject <NSFastEnumeration>

@property (nonatomic, weak, nullable) id<TIPLRUCacheDelegate> delegate;
@property (nonatomic, readonly, nullable) id<TIPLRUEntry> headEntry;
@property (nonatomic, readonly, nullable) id<TIPLRUEntry> tailEntry;

- (NSUInteger)numberOfEntries;

- (nonnull instancetype)initWithEntries:(nullable NSArray<id<TIPLRUEntry>> *)arrayOfLRUEntries delegate:(nullable id<TIPLRUCacheDelegate>)delegate NS_DESIGNATED_INITIALIZER;

- (nullable id<TIPLRUEntry>)entryWithIdentifier:(nonnull NSString *)identifier canMutate:(BOOL)moveToHead;

- (nullable id<TIPLRUEntry>)entryWithIdentifier:(nonnull NSString *)identifier;

- (nonnull NSArray<id<TIPLRUEntry>> *)allEntries;

- (void)addEntry:(nonnull id<TIPLRUEntry>)entry;

- (void)appendEntry:(nonnull id<TIPLRUEntry>)entry;

- (void)removeEntry:(nonnull id<TIPLRUEntry>)entry;

- (nullable id<TIPLRUEntry>)removeTailEntry;

- (void)clearAllEntries;

@end

@protocol TIPLRUCacheDelegate <NSObject>

@optional
- (void)tip_cache:(nonnull TIPLRUCache *)cache didEvictEntry:(nonnull id<TIPLRUEntry>)entry;

@end


@protocol TIPLRUEntry <NSObject>

@required

- (nonnull NSString *)LRUEntryIdentifier;
- (BOOL)shouldAccessMoveLRUEntryToHead;
@property (nonatomic, nullable) id<TIPLRUEntry> nextLRUEntry;
@property (nonatomic, nullable, weak) id<TIPLRUEntry> previousLRUEntry;

@end
