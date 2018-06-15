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

#import <TwitterImagePipeline/TIPLogger.h>


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
({ if (gTwitterImagePipelineAssertEnabled) { \
    const BOOL __expressionValue = !!(expression); (void)__expressionValue; \
    __TIPAssert(__expressionValue); \
    NSCAssert(__expressionValue, @"assertion failed: (" #expression ")"); \
} })

#define TIPAssertMessage(expression, format, ...) \
({ if (gTwitterImagePipelineAssertEnabled) { \
    const BOOL __expressionValue = !!(expression); (void)__expressionValue; \
    __TIPAssert(__expressionValue); \
    NSCAssert(__expressionValue, @"assertion failed: (" #expression ") message: %@", [NSString stringWithFormat:format, ##__VA_ARGS__]); \
} })

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

NS_INLINE void tip_dispatch_sync_autoreleasing(dispatch_queue_t queue, dispatch_block_t __attribute__((noescape)) block)
{
    dispatch_sync(queue, ^{
        @autoreleasepool {
            block();
        }
    });
}

#pragma mark - Private Method C Functions Support

/**
 Macro to help with implementing static C-functions instead of private methods

    static NSString *_extendedDescription(PRIVATE_SELF(type))
    {
        if (!self) { // ALWAYS perform the `self` nil-check first
            return nil;
        }
        return [[self description] stringByAppendingFormat:@" %@", self->_extendedInfo];
    }

 Can be helpful to define a macro at the top of a .m file for the primary class' `PRIVATE_SELF`.
 Then, that macro can be used in all private function declarations/implementations
 For example:

    // in TIPImagePipeline.m
    #define SELF_ARG PRIVATE_SELF(TIPImagePipeline)

    static NSString *_extendedDescription(SELF_ARG)
    {
        if (!self) { // ALWAYS perform the `self` nil-check first
            return nil;
        }
        return [[self description] stringByAppendingFormat:@" %@", self->_extendedInfo];
    }

 Calling:

    // private method
    NSString *description = [self _tip_extendedDescription];

    // static function
    NSString *description = _extendedDescription(self);

 Provide context:

    // Don't just pass ambiguous values to arguments, provide context

    UIImage *nilOverlayImage = nil;
    UIImage *image = _renderImage(self,
                                  nilOverlayImage,
                                  self.textOverlayString,
                                  [UIColor yellow], // tintColor
                                  UIImageOrientationUp,
                                  CGSizeZero, // zero size to render without scaling
                                  0, // options
                                  NO); // opaque

 Note the context is clear for each:

    1. self is self, of course
    2. nilOverlayImage: we set up a local variable so we can provide context instead of passing `nil` without context
    3. self.textOverlayString: variable is descriptive of what it is, enough context on its own
    4. [UIColor yellow]: it's a color, sure, but what for?  Provide a comment that it is for the `tintColor`
    5. UIImageOrientationUp: clear that this is the orientation to provide to the render function
    6. CGSizeZero: it's a size, but what does it mean for a special case value of zero and what's the size for?  Extra context with a descriptive comment.
    7. 0: provides no insight, commenting that it is for `options` is sufficient at specifying that no options were selected.
    8. NO: provides no insight, commenting that it is for `opaque` indicates the image render will be non-opaque (and probably have an alpha channel).

 Why `__nullable` instead of `__nonnull`?

 As it stands, we are defining `PRIVATE_SELF` to be `__nullable` and having all implementations encapsulate the `nil` check on `self`.
 Ideally, we would actually want `self` to be `__nonnull` so that the compiler enforces that the caller must pass a non-null argument.
 This would be a safer solution, however, clang (nor the static analyzer) catch the case where a `weak` argument is passed to a `nonnull`
 C function as an argument.  This means having `weakSelf` passed directly to the static C function could end up passing `nil`, and likely
 lead to a crash when the ivar is accessed, such as `self->_ivar`.

 A radar has been filed against Apple to remedy this in the compiler, but until then, it is safer to enforce the pattern using `__nullable`
 with a `nil` check.

 https://openradar.appspot.com/40129673

 */

#ifndef PRIVATE_SELF
#define PRIVATE_SELF(type) type * __nullable const self
#endif

NS_ASSUME_NONNULL_END

