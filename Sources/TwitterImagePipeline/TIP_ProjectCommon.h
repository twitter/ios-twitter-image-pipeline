//
//  TIP_ProjectCommon.h
//  TwitterImagePipeline
//
//  Created on 3/5/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

// This header is kept in sync with other *_Common.h headers from sibling projects.
// This header is separate from TIP_Project.h which has TIP specific helper code.

#import <Foundation/Foundation.h>

#import <TIPLogger.h>


NS_ASSUME_NONNULL_BEGIN


#pragma mark - File Name macro

/**
 Helper macro for the file name macro.

 `__FILE__` is the historical C macro that is replaced with the full file path of the current file being compiled (e.g. `/Users/username/workspace/project/source/subfolder/anotherfolder/implementation/file.c`)
 `__FILE_NAME__` is the new C macro in clang that is replaced with the file name of the current file being compiled (e.g. `file.c`)

 By default, if `__FILE_NAME__` is availble with the current compiler, it will be used.
 This behavior can be overridden by providing a value for `TIP_FILE_NAME` to the compiler, like `-DTIP_FILE_NAME=__FILE__` or `-DTIP_FILE_NAME=\"redacted\"`
 */
#if !defined(TIP_FILE_NAME)
#ifdef __FILE_NAME__
#define TIP_FILE_NAME __FILE_NAME__
#else
#define TIP_FILE_NAME __FILE__
#endif
#endif

#pragma mark - Binary

FOUNDATION_EXTERN BOOL TIPIsExtension(void);

#pragma mark - Availability

// macros helpers to match against specific iOS versions and their mapped non-iOS platform versions

#define tip_available_ios_11    @available(iOS 11, tvOS 11, macOS 10.13, watchOS 4, *)
#define tip_available_ios_12    @available(iOS 12, tvOS 12, macOS 10.14, watchOS 5, *)
#define tip_available_ios_13    @available(iOS 13, tvOS 13, macOS 10.15, watchOS 6, *)
#define tip_available_ios_14    @available(iOS 14, tvOS 14, macOS 11.0, watchOS 7, *)

#if TARGET_OS_IOS
#define TIP_OS_VERSION_MAX_ALLOWED_IOS_14 (__IPHONE_OS_VERSION_MAX_ALLOWED >= 140000)
#elif TARGET_OS_MACCATALYST
#define TIP_OS_VERSION_MAX_ALLOWED_IOS_14 (__IPHONE_OS_VERSION_MAX_ALLOWED >= 140000)
#elif TARGET_OS_TV
#define TIP_OS_VERSION_MAX_ALLOWED_IOS_14 (__TV_OS_VERSION_MAX_ALLOWED >= 140000)
#elif TARGET_OS_WATCH
#define TIP_OS_VERSION_MAX_ALLOWED_IOS_14 (__WATCH_OS_VERSION_MAX_ALLOWED >= 70000)
#elif TARGET_OS_OSX
#define TGF_OS_VERSION_MAX_ALLOWED_IOS_14 (__MAC_OS_X_VERSION_MAX_ALLOWED >= 110000)
#else
#warning Unexpected Target Platform
#define TIP_OS_VERSION_MAX_ALLOWED_IOS_14 (0)
#endif

#pragma mark - Bitmask Helpers

/** Does the `mask` have at least 1 of the bits in `flags` set */
#define TIP_BITMASK_INTERSECTS_FLAGS(mask, flags)   (((mask) & (flags)) != 0)
/** Does the `mask` have all of the bits in `flags` set */
#define TIP_BITMASK_HAS_SUBSET_FLAGS(mask, flags)   (((mask) & (flags)) == (flags))
/** Does the `mask` have none of the bits in `flags` set */
#define TIP_BITMASK_EXCLUDES_FLAGS(mask, flags)     (((mask) & (flags)) == 0)

#pragma mark - Assert

FOUNDATION_EXTERN BOOL gTwitterImagePipelineAssertEnabled;

#if !defined(NS_BLOCK_ASSERTIONS)

#define TIPCAssert(condition, desc, ...) \
do {                \
    __PRAGMA_PUSH_NO_EXTRA_ARG_WARNINGS \
    if (__builtin_expect(!(condition), 0)) { \
        __TIPAssertTriggering(); \
        NSString *__assert_fn__ = [NSString stringWithUTF8String:__PRETTY_FUNCTION__]; \
        __assert_fn__ = __assert_fn__ ? __assert_fn__ : @"<Unknown Function>"; \
        NSString *__assert_file__ = [NSString stringWithUTF8String:TIP_FILE_NAME]; \
        __assert_file__ = __assert_file__ ? __assert_file__ : @"<Unknown File>"; \
        [[NSAssertionHandler currentHandler] handleFailureInFunction:__assert_fn__ \
                                                                file:__assert_file__ \
                                                          lineNumber:__LINE__ \
                                                         description:(desc), ##__VA_ARGS__]; \
    } \
    __PRAGMA_POP_NO_EXTRA_ARG_WARNINGS \
} while(0)

#else // NS_BLOCK_ASSERTIONS defined

#define TIPCAssert(condition, desc, ...) do {} while (0)

#endif // NS_BLOCK_ASSERTIONS not defined

#define TIPAssert(expression) \
({ if (gTwitterImagePipelineAssertEnabled) { \
    const BOOL __expressionValue = !!(expression); (void)__expressionValue; \
    TIPCAssert(__expressionValue, @"assertion failed: (" #expression ")"); \
} })

#define TIPAssertMessage(expression, format, ...) \
({ if (gTwitterImagePipelineAssertEnabled) { \
    const BOOL __expressionValue = !!(expression); (void)__expressionValue; \
    TIPCAssert(__expressionValue, @"assertion failed: (" #expression ") message: %@", [NSString stringWithFormat:format, ##__VA_ARGS__]); \
} })

#define TIPAssertNever()      TIPAssert(0 && "this line should never get executed" )

#pragma twitter startignoreformatting

// NOTE: TIPStaticAssert's msg argument should be valid as a variable.  That is, composed of ASCII letters, numbers and underscore characters only.
#define __TIPStaticAssert(line, msg) TIPStaticAssert_##line##_##msg
#define _TIPStaticAssert(line, msg) __TIPStaticAssert( line , msg )

#define TIPStaticAssert(condition, msg) \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Wunused\"") \
typedef char _TIPStaticAssert( __LINE__ , msg ) [ (condition) ? 1 : -1 ] \
_Pragma("clang diagnostic pop" )

#pragma twitter endignoreformatting

#pragma mark - Logging

FOUNDATION_EXTERN id<TIPLogger> __nullable gTIPLogger;

#pragma twitter startignorestylecheck

#define TIPLog(level, ...) \
do { \
    id<TIPLogger> const __logger = gTIPLogger; \
    TIPLogLevel const __level = (level); \
    if (__logger && (![__logger respondsToSelector:@selector(tip_canLogWithLevel:)] || [__logger tip_canLogWithLevel:__level])) { \
        [__logger tip_logWithLevel:__level file:@(TIP_FILE_NAME) function:@(__FUNCTION__) line:__LINE__ message:[NSString stringWithFormat: __VA_ARGS__ ]]; \
    } \
} while (0)

#define TIPLogError(...)        TIPLog(TIPLogLevelError, __VA_ARGS__)
#define TIPLogWarning(...)      TIPLog(TIPLogLevelWarning, __VA_ARGS__)
#define TIPLogInformation(...)  TIPLog(TIPLogLevelInformation, __VA_ARGS__)
#define TIPLogDebug(...)        TIPLog(TIPLogLevelDebug, __VA_ARGS__)

#pragma twitter endignorestylecheck

#pragma mark - Debugging Tools

#if DEBUG
FOUNDATION_EXTERN void __TIPAssertTriggering(void);
FOUNDATION_EXTERN BOOL TIPIsDebuggerAttached(void);
FOUNDATION_EXTERN void TIPTriggerDebugSTOP(void);
FOUNDATION_EXTERN BOOL TIPIsDebugSTOPOnAssertEnabled(void);
FOUNDATION_EXTERN void TIPSetDebugSTOPOnAssertEnabled(BOOL stopOnAssert);
#else
#define __TIPAssertTriggering() ((void)0)
#define TIPIsDebuggerAttached() (NO)
#define TIPTriggerDebugSTOP() ((void)0)
#define TIPIsDebugSTOPOnAssertEnabled() (NO)
#define TIPSetDebugSTOPOnAssertEnabled(stopOnAssert) ((void)0)
#endif

FOUNDATION_EXTERN BOOL TIPAmIBeingUnitTested(void);

#pragma mark - Style Check support


#pragma mark - Thread Sanitizer

// Macro to disable the thread-sanitizer for a particular method or function

#if defined(__has_feature)
# if __has_feature(thread_sanitizer)
#  define TIP_THREAD_SANITIZER_DISABLED __attribute__((no_sanitize("thread")))
# else
#  define TIP_THREAD_SANITIZER_DISABLED
# endif
#else
# define TIP_THREAD_SANITIZER_DISABLED
#endif

#pragma mark - Objective-C attribute support

#if defined(__has_attribute) && (defined(__IPHONE_14_0) || defined(__MAC_10_16) || defined(__MAC_11_0) || defined(__TVOS_14_0) || defined(__WATCHOS_7_0))
# define TIP_SUPPORTS_OBJC_DIRECT __has_attribute(objc_direct)
#else
# define TIP_SUPPORTS_OBJC_DIRECT 0
#endif

#if defined(__has_attribute)
# define TIP_SUPPORTS_OBJC_FINAL  __has_attribute(objc_subclassing_restricted)
#else
# define TIP_SUPPORTS_OBJC_FINAL  0
#endif

#pragma mark - Objective-C Direct Support

#if TIP_SUPPORTS_OBJC_DIRECT
# define tip_nonatomic_direct     nonatomic,direct
# define tip_atomic_direct        atomic,direct
# define TIP_OBJC_DIRECT          __attribute__((objc_direct))
# define TIP_OBJC_DIRECT_MEMBERS  __attribute__((objc_direct_members))
#else
# define tip_nonatomic_direct     nonatomic
# define tip_atomic_direct        atomic
# define TIP_OBJC_DIRECT
# define TIP_OBJC_DIRECT_MEMBERS
#endif // #if TIP_SUPPORTS_OBJC_DIRECT

#pragma mark - Objective-C Final Support

#if TIP_SUPPORTS_OBJC_FINAL
# define TIP_OBJC_FINAL   __attribute__((objc_subclassing_restricted))
#else
# define TIP_OBJC_FINAL
#endif // #if TIP_SUPPORTS_OBJC_FINAL

#pragma mark - tip_defer support

typedef void(^tip_defer_block_t)(void);
NS_INLINE void tip_deferFunc(__strong tip_defer_block_t __nonnull * __nonnull blockRef)
{
    tip_defer_block_t actualBlock = *blockRef;
    actualBlock();
}

#define _tip_macro_concat(a, b) a##b
#define tip_macro_concat(a, b) _tip_macro_concat(a, b)

#pragma twitter startignorestylecheck

#define tip_defer(deferBlock) \
__strong tip_defer_block_t tip_macro_concat(tip_stack_defer_block_, __LINE__) __attribute__((cleanup(tip_deferFunc), unused)) = deferBlock

#define TIPDeferRelease(ref) tip_defer(^{ if (ref) { CFRelease(ref); } })

#pragma twitter endignorestylecheck

#pragma mark - GCD helpers

// Autoreleasing dispatch functions.
// callers cannot use autoreleasing passthrough
//
//  Example of what can't be done (autoreleasing passthrough):
//
//      - (void)deleteFile:(NSString *)fileToDelete
//                   error:(NSError * __autoreleasing *)error
//      {
//          tip_dispatch_sync_autoreleasing(_config.queueForDiskCaches, ^{
//              [[NSFileManager defaultFileManager] removeItemAtPath:fileToDelete
//       /* will lead to crash if set to non-nil value --> */  error:error];
//          });
//      }
//
//  Example of how to avoid passthrough crash:
//
//      - (void)deleteFile:(NSString *)fileToDelete
//                   error:(NSError * __autoreleasing *)error
//      {
//          __block NSError *outerError = nil;
//          tip_dispatch_sync_autoreleasing(_config.queueForDiskCaches, ^{
//              NSError *innerError = nil;
//              [[NSFileManager defaultFileManager] removeItemAtPath:fileToDelete
//                                                             error:&innerError];
//              outerError = innerError;
//          });
//          if (error) {
//              *error = outerError;
//          }
//      }

// Should pretty much ALWAYS use this for async dispatch
NS_INLINE void tip_dispatch_async_autoreleasing(dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_async(queue, ^{
        @autoreleasepool {
            block();
        }
    });
}

// Should pretty much ALWAYS use this for async barrier dispatch
NS_INLINE void tip_dispatch_barrier_async_autoreleasing(dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_barrier_async(queue, ^{
        @autoreleasepool {
            block();
        }
    });
}

// Only need this in a tight loop, existing autorelease pool will take effect for dispatch_sync
NS_INLINE void tip_dispatch_sync_autoreleasing(dispatch_queue_t __attribute__((noescape)) queue, dispatch_block_t block)
{
    dispatch_sync(queue, ^{
        @autoreleasepool {
            block();
        }
    });
}

NS_ASSUME_NONNULL_END


