//
//  TIP_ProjectCommon.h
//  TwitterImagePipeline
//
//  Created on 3/5/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

// This header is kept in sync with other *_Common.h headers from sibling projects.
// This header is separate from TIP_Project.h which has TIP specific helper code.

#import <Foundation/Foundation.h>

#import "TIPLogger.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Binary

FOUNDATION_EXTERN BOOL TIPIsExtension(void);

#pragma mark - Bitmask Helpers

/** Does the `mask` have at least 1 of the bits in `flags` set */
#define TIP_BITMASK_INTERSECTS_FLAGS(mask, flags)   (((mask) & (flags)) != 0)
/** Does the `mask` have all of the bits in `flags` set */
#define TIP_BITMASK_HAS_SUBSET_FLAGS(mask, flags)   (((mask) & (flags)) == (flags))
/** Does the `mask` have none of the bits in `flags` set */
#define TIP_BITMASK_EXCLUDES_FLAGS(mask, flags)     (((mask) & (flags)) == 0)

#pragma mark - Assert

FOUNDATION_EXTERN BOOL gTwitterImagePipelineAssertEnabled;

#define TIPAssert(expression) \
if (gTwitterImagePipelineAssertEnabled) { \
    const BOOL __expressionValue = !!(expression); \
    (void)__expressionValue; \
    __TIPAssert(__expressionValue); \
    NSCAssert(__expressionValue, @"assertion failed: (" #expression ")"); \
}

#define TIPAssertMessage(expression, format, ...) \
if (gTwitterImagePipelineAssertEnabled) { \
    const BOOL __expressionValue = !!(expression); \
    (void)__expressionValue; \
    __TIPAssert(__expressionValue); \
    NSCAssert(__expressionValue, @"assertion failed: (" #expression ") message: %@", [NSString stringWithFormat:format, ##__VA_ARGS__]); \
} while (0)

#define TIPAssertNever()      TIPAssert(0 && "this line should never get executed" )

#pragma twitter startignoreformatting

// NOTE: TIPStaticAssert's msg argument should be valid as a variable.  That is, composed of ASCII letters, numbers and underscore characters only.
#define __TIPStaticAssert(line, msg) TIPStaticAssert_##line##_##msg
#define _TIPStaticAssert(line, msg) __TIPStaticAssert( line , msg )
#define TIPStaticAssert(condition, msg) typedef char _TIPStaticAssert( __LINE__ , msg ) [ (condition) ? 1 : -1 ]

#pragma twitter endignoreformatting

#pragma mark - Logging

FOUNDATION_EXTERN id<TIPLogger> __nullable gTIPLogger;

#pragma twitter startignorestylecheck

#define TIPLog(level, ...) \
do { \
    id<TIPLogger> const __logger = gTIPLogger; \
    TIPLogLevel const __level = (level); \
    if (__logger && (![__logger respondsToSelector:@selector(tip_canLogWithLevel:)] || [__logger tip_canLogWithLevel:__level])) { \
        [__logger tip_logWithLevel:__level file:@(__FILE__) function:@(__FUNCTION__) line:__LINE__ message:[NSString stringWithFormat: __VA_ARGS__ ]]; \
    } \
} while (0)

#define TIPLogError(...)        TIPLog(TIPLogLevelError, __VA_ARGS__)
#define TIPLogWarning(...)      TIPLog(TIPLogLevelWarning, __VA_ARGS__)
#define TIPLogInformation(...)  TIPLog(TIPLogLevelInformation, __VA_ARGS__)
#define TIPLogDebug(...)        TIPLog(TIPLogLevelDebug, __VA_ARGS__)

#pragma twitter endignorestylecheck

#pragma mark - Debugging Tools

#if DEBUG
FOUNDATION_EXTERN void __TIPAssert(BOOL expression);
FOUNDATION_EXTERN BOOL TIPIsDebuggerAttached(void);
FOUNDATION_EXTERN void TIPTriggerDebugSTOP(void);
FOUNDATION_EXTERN BOOL TIPIsDebugSTOPOnAssertEnabled(void);
FOUNDATION_EXTERN void TIPSetDebugSTOPOnAssertEnabled(BOOL stopOnAssert);
#else
#define __TIPAssert(exp) ((void)0)
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

#pragma twitter stopignorestylecheck

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

NS_INLINE void tip_dispatch_async_autoreleasing(dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_async(queue, ^{
        @autoreleasepool {
            block();
        }
    });
}

NS_INLINE void tip_dispatch_sync_autoreleasing(dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_sync(queue, ^{
        @autoreleasepool {
            block();
        }
    });
}

NS_ASSUME_NONNULL_END
