//
//  NSDictionary+TIPAdditions.h
//  TwitterImagePipeline
//
//  Created on 9/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSDictionary (TIPAdditions)

- (nullable NSArray *)tip_objectsForCaseInsensitiveKey:(nonnull NSString *)key;
- (nullable NSSet<NSString *> *)tip_keysMatchingCaseInsensitiveKey:(nonnull NSString *)key;
- (nonnull id)tip_copyWithLowercaseKeys;
- (nonnull id)tip_copyWithUppercaseKeys;
- (nonnull id)tip_mutableCopyWithLowercaseKeys;
- (nonnull id)tip_mutableCopyWithUppercaseKeys;

@end

@interface NSMutableDictionary (TIPAdditions)

- (void)tip_removeObjectsForCaseInsensitiveKey:(nonnull NSString *)key;
- (void)tip_setObject:(nonnull id)object forCaseInsensitiveKey:(nonnull NSString *)key;
- (void)tip_makeAllKeysLowercase;
- (void)tip_makeAllKeysUppercase;

@end
