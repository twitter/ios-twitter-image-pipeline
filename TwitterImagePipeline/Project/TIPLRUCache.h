//
//  TIPLRUCache.h
//  TwitterImagePipeline
//
//  Created on 10/27/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol TIPLRUCacheDelegate;
@protocol TIPLRUEntry;

NS_ASSUME_NONNULL_BEGIN

@interface TIPLRUCache : NSObject <NSFastEnumeration>

@property (nonatomic, weak, nullable) id<TIPLRUCacheDelegate> delegate;
@property (nonatomic, readonly, nullable) id<TIPLRUEntry> headEntry;
@property (nonatomic, readonly, nullable) id<TIPLRUEntry> tailEntry;

- (NSUInteger)numberOfEntries;

- (instancetype)initWithEntries:(nullable NSArray<id<TIPLRUEntry>> *)arrayOfLRUEntries delegate:(nullable id<TIPLRUCacheDelegate>)delegate NS_DESIGNATED_INITIALIZER;

- (nullable id<TIPLRUEntry>)entryWithIdentifier:(NSString *)identifier canMutate:(BOOL)moveToHead;

- (nullable id<TIPLRUEntry>)entryWithIdentifier:(NSString *)identifier;

- (NSArray<id<TIPLRUEntry>> *)allEntries;

- (void)addEntry:(id<TIPLRUEntry>)entry;

- (void)appendEntry:(id<TIPLRUEntry>)entry;

- (void)removeEntry:(nullable id<TIPLRUEntry>)entry;

- (nullable id<TIPLRUEntry>)removeTailEntry;

- (void)clearAllEntries;

@end

@protocol TIPLRUCacheDelegate <NSObject>

@optional
- (void)tip_cache:(TIPLRUCache *)cache didEvictEntry:(id<TIPLRUEntry>)entry;
- (BOOL)tip_cache:(TIPLRUCache *)cache canEvictEntry:(id<TIPLRUEntry>)entry;

@end


@protocol TIPLRUEntry <NSObject>

@required

- (NSString *)LRUEntryIdentifier;
- (BOOL)shouldAccessMoveLRUEntryToHead;
@property (nonatomic, nullable) id<TIPLRUEntry> nextLRUEntry;
@property (nonatomic, nullable, weak) id<TIPLRUEntry> previousLRUEntry;

@end

NS_ASSUME_NONNULL_END

