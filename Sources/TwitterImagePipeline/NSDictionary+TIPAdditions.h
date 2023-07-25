//
//  NSDictionary+TIPAdditions.h
//  TwitterImagePipeline
//
//  Created on 9/9/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSDictionary (TIPAdditions)

- (nullable NSArray *)tip_objectsForCaseInsensitiveKey:(NSString *)key;
- (nullable id)tip_objectForCaseInsensitiveKey:(NSString *)key;
- (nullable NSSet<NSString *> *)tip_keysMatchingCaseInsensitiveKey:(NSString *)key;
- (id)tip_copyWithLowercaseKeys;
- (id)tip_copyWithUppercaseKeys;
- (id)tip_mutableCopyWithLowercaseKeys;
- (id)tip_mutableCopyWithUppercaseKeys;

@end

@interface NSMutableDictionary (TIPAdditions)

- (void)tip_removeObjectsForCaseInsensitiveKey:(NSString *)key;
- (void)tip_setObject:(id)object forCaseInsensitiveKey:(NSString *)key;
- (void)tip_makeAllKeysLowercase;
- (void)tip_makeAllKeysUppercase;

@end

NS_ASSUME_NONNULL_END

