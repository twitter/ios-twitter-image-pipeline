//
//  NSDictionary+TIPAdditions.m
//  TwitterImagePipeline
//
//  Created on 9/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import "NSDictionary+TIPAdditions.h"
#import "TIP_Project.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSDictionary (TIPAdditions)

- (nullable NSSet *)tip_keysMatchingCaseInsensitiveKey:(NSString *)key
{
    NSMutableSet *keys = nil;
    TIPAssert([key isKindOfClass:[NSString class]]);
    if ([key isKindOfClass:[NSString class]]) {
        for (NSString *otherKey in self.allKeys) {
            TIPAssert([key isKindOfClass:[NSString class]]);
            if ([otherKey caseInsensitiveCompare:key] == NSOrderedSame) { // TWITTER_STYLE_CASE_INSENSITIVE_COMPARE_NIL_PRECHECKED
                if (!keys) {
                    keys = [NSMutableSet set];
                }
                [keys addObject:otherKey];
            }
        }
    }
    return keys;
}

- (nullable NSArray *)tip_objectsForCaseInsensitiveKey:(NSString *)key
{
    TIPAssert(key);
    NSSet *keys = [self tip_keysMatchingCaseInsensitiveKey:key];
    NSMutableArray *objects = (keys.count > 0) ? [NSMutableArray array] : nil;
    for (NSString *otherKey in keys) {
        [objects addObject:self[otherKey]];
    }
    return objects;
}

- (id)tip_copyWithLowercaseKeys
{
    return [self tip_copyToMutable:NO uppercase:NO];
}

- (id)tip_copyWithUppercaseKeys
{
    return [self tip_copyToMutable:NO uppercase:YES];
}

- (id)tip_mutableCopyWithLowercaseKeys
{
    return [self tip_copyToMutable:YES uppercase:NO];
}

- (id)tip_mutableCopyWithUppercaseKeys
{
    return [self tip_copyToMutable:YES uppercase:YES];
}

- (id)tip_copyToMutable:(BOOL)mutable uppercase:(BOOL)uppercase
{
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    for (NSString *key in self) {
        d[(uppercase) ? key.uppercaseString : key.lowercaseString] = self[key];
    }
    return (mutable) ? d : [d copy];
}

@end

@implementation NSMutableDictionary (TIPAdditions)

- (void)tip_removeObjectsForCaseInsensitiveKey:(NSString *)key
{
    TIPAssert(key);
    NSArray *keys = [[self tip_keysMatchingCaseInsensitiveKey:key] allObjects];
    if (keys) {
        [self removeObjectsForKeys:keys];
    }
}

- (void)tip_setObject:(id)object forCaseInsensitiveKey:(NSString *)key
{
    TIPAssert(key);
    [self tip_removeObjectsForCaseInsensitiveKey:key];
    self[key] = object;
}

- (void)tip_makeAllKeysLowercase
{
    NSDictionary *d = [self tip_mutableCopyWithLowercaseKeys];
    [self removeAllObjects];
    [self addEntriesFromDictionary:d];
}

- (void)tip_makeAllKeysUppercase
{
    NSDictionary *d = [self tip_mutableCopyWithUppercaseKeys];
    [self removeAllObjects];
    [self addEntriesFromDictionary:d];
}

@end

NS_ASSUME_NONNULL_END

