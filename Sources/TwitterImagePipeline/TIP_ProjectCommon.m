//
//  TIP_ProjectCommon.m
//  TwitterImagePipeline
//
//  Created on 3/5/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TIP_ProjectCommon.h"

#if DEBUG
#include <assert.h>
#include <stdbool.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/sysctl.h>
#endif


NS_ASSUME_NONNULL_BEGIN

BOOL gTwitterImagePipelineAssertEnabled = YES;
id<TIPLogger> __nullable gTIPLogger = nil;

BOOL TIPIsExtension()
{
    // Per Apple, an extension will have a top level NSExtension dictionary in the info.plist
    // https://developer.apple.com/library/ios/documentation/General/Reference/InfoPlistKeyReference/Articles/SystemExtensionKeys.html

    static BOOL sIsExtension;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSDictionary *infoDictionary = mainBundle.infoDictionary;
        NSDictionary *extensionDictionary = infoDictionary[@"NSExtension"];
        sIsExtension = [extensionDictionary isKindOfClass:[NSDictionary class]];
    });
    return sIsExtension;
}

BOOL TIPAmIBeingUnitTested(void)
{
    // Look for a "SenTest" (legacy) or "XCTest" class. If we switch unit test frameworks we need to update this.
    static BOOL sAmIBeingUnitTested = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sAmIBeingUnitTested = (NSClassFromString(@"SenTest") != Nil || NSClassFromString(@"XCTest") != Nil);
    });
    return sAmIBeingUnitTested;
}

#if DEBUG

// https://developer.apple.com/library/mac/qa/qa1361/_index.html
// Returns true if the current process is being debugged (either
// running under the debugger or has a debugger attached post facto).
BOOL TIPIsDebuggerAttached()
{
    int                 junk;
    int                 mib[4];
    struct kinfo_proc   info;
    size_t              size;

    // Initialize the flags so that, if sysctl fails for some bizarre
    // reason, we get a predictable result.

    info.kp_proc.p_flag = 0;

    // Initialize mib, which tells sysctl the info we want, in this case
    // we're looking for information about a specific process ID.

    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_PID;
    mib[3] = getpid();

    // Call sysctl.

    size = sizeof(info);
    junk = sysctl(mib, sizeof(mib) / sizeof(*mib), &info, &size, NULL, 0);
    assert(junk == 0);

    // We're being debugged if the P_TRACED flag is set.

    return TIP_BITMASK_INTERSECTS_FLAGS(info.kp_proc.p_flag, P_TRACED);
}

void TIPTriggerDebugSTOP()
{
    kill(getpid(), SIGSTOP);
}

static volatile BOOL sIsDebugSTOPEnabled = YES;
static dispatch_once_t sIsDebugSTOPEnabledOnceToken = 0;

NS_INLINE void TIPPrepDebugSTOPOnAssert()
{
    dispatch_once(&sIsDebugSTOPEnabledOnceToken, ^{
        sIsDebugSTOPEnabled = !TIPAmIBeingUnitTested();
    });
}

BOOL TIPIsDebugSTOPOnAssertEnabled()
{
    TIPPrepDebugSTOPOnAssert();
    return sIsDebugSTOPEnabled;
}

void TIPSetDebugSTOPOnAssertEnabled(BOOL stopOnAssert)
{
    TIPPrepDebugSTOPOnAssert();
    sIsDebugSTOPEnabled = stopOnAssert;
}

void __TIPAssertTriggering()
{
    if (TIPIsDebugSTOPOnAssertEnabled() && TIPIsDebuggerAttached()) {
        TIPTriggerDebugSTOP(); // trigger debug stop
    }
}

#endif // DEBUG

NS_ASSUME_NONNULL_END

