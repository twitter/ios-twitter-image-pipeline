//
//  TIPXUtils.h
//  TwitterImagePipeline
//
//  Created on 7/6/20.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Objective-C Direct Support

#if defined(__has_attribute) && (defined(__IPHONE_14_0) || defined(__MAC_10_16) || defined(__MAC_11_0) || defined(__TVOS_14_0) || defined(__WATCHOS_7_0))
# define TIPX_SUPPORTS_OBJC_DIRECT __has_attribute(objc_direct)
#else
# define TIPX_SUPPORTS_OBJC_DIRECT 0
#endif

#if defined(__has_attribute)
# define TIPX_SUPPORTS_OBJC_FINAL  __has_attribute(objc_subclassing_restricted)
#else
# define TIPX_SUPPORTS_OBJC_FINAL  0
#endif

#if TIPX_SUPPORTS_OBJC_DIRECT
# define tipx_nonatomic_direct     nonatomic,direct
# define tipx_atomic_direct        atomic,direct
# define TIPX_OBJC_DIRECT          __attribute__((objc_direct))
# define TIPX_OBJC_DIRECT_MEMBERS  __attribute__((objc_direct_members))
#else
# define tipx_nonatomic_direct     nonatomic
# define tipx_atomic_direct        atomic
# define TIPX_OBJC_DIRECT
# define TIPX_OBJC_DIRECT_MEMBERS
#endif // #if TIPX_SUPPORTS_OBJC_DIRECT

#pragma mark - Defer support

typedef void(^tipx_defer_block_t)(void);
NS_INLINE void tipx_deferFunc(__strong tipx_defer_block_t __nonnull * __nonnull blockRef)
{
    tipx_defer_block_t actualBlock = *blockRef;
    actualBlock();
}

#define _tipx_macro_concat(a, b) a##b
#define tipx_macro_concat(a, b) _tipx_macro_concat(a, b)

#pragma twitter startignorestylecheck

#define tipx_defer(deferBlock) \
__strong tipx_defer_block_t tipx_macro_concat(tipx_stack_defer_block_, __LINE__) __attribute__((cleanup(tipx_deferFunc), unused)) = deferBlock

#define TIPXDeferRelease(ref) tipx_defer(^{ if (ref) { CFRelease(ref); } })

#pragma twitter endignorestylecheck

NS_ASSUME_NONNULL_END
