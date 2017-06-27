//
//  NSOperationQueue+TIPSafety.m
//  TwitterImagePipeline
//
//  Created on 8/14/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "NSOperationQueue+TIPSafety.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const TIPOperationSafetyGuardRemoveOperationAfterFinishedDelay = 2.0;
static NSTimeInterval const TIPOperationSafetyGuardCheckForAlreadyFinishedOperationDelay = 1.0;

@interface TIPOperationSafetyGuard : NSObject
- (void)addOperation:(nonnull NSOperation *)op;
- (NSSet *)operations;
+ (nullable instancetype)operationSafetyGuard;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)new NS_UNAVAILABLE;
@end

@implementation NSOperationQueue (TIPSafety)

- (void)tip_safeAddOperation:(NSOperation *)op
{
    TIPOperationSafetyGuard *guard = [TIPOperationSafetyGuard operationSafetyGuard];
    if (guard) {
        [guard addOperation:op];
    }
    [self addOperation:op];
}

@end

@implementation TIPOperationSafetyGuard
{
    dispatch_queue_t _queue;
    NSMutableSet *_operations;
}

+ (nullable instancetype)operationSafetyGuard
{
    static TIPOperationSafetyGuard *sGuard = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSOperatingSystemVersion version = { 7, 0, 0 }; /* arbitrarily default as iOS 7 (minimum version for TIP) */
        if ([[NSProcessInfo processInfo] respondsToSelector:@selector(operatingSystemVersion)]) {
            version = [NSProcessInfo processInfo].operatingSystemVersion;
        }
        if (version.majorVersion < 9) {
            sGuard = [[TIPOperationSafetyGuard alloc] initWithOperationSystemVersion:version];
        }
    });
    return sGuard;
}

- (instancetype)initWithOperationSystemVersion:(NSOperatingSystemVersion)version
{
    if (self = [super init]) {
        _operations = [[NSMutableSet alloc] init];
        dispatch_queue_attr_t queueAttr = DISPATCH_QUEUE_SERIAL;
        if (version.majorVersion >= 8) {
            queueAttr = dispatch_queue_attr_make_with_qos_class(queueAttr, QOS_CLASS_BACKGROUND, 0);
        }
        _queue = dispatch_queue_create("NSOperationQueue.tip.safety", queueAttr);
    }
    return self;
}

- (void)dealloc
{
    for (NSOperation *op in _operations) {
        [op removeObserver:self forKeyPath:@"isFinished"];
    }
}

- (NSSet *)operations
{
    __block NSSet *operations;
    dispatch_sync(_queue, ^{
        operations = [self->_operations copy];
    });
    return operations;
}

- (void)addOperation:(NSOperation *)op
{
    if (!op.isAsynchronous || op.isFinished) {
        return;
    }

    dispatch_async(_queue, ^{
        [self->_operations addObject:op];
        [op addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:NULL];

        // There are race conditions where the isFinished KVO may never be observed.
        // Use this async check to weed out any early finishing operations that we didn't observe finishing.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TIPOperationSafetyGuardCheckForAlreadyFinishedOperationDelay * NSEC_PER_SEC)), self->_queue, ^{
            if (op.isFinished) {
                // Call our KVO observer to unify the code path for removing the observer
                [self observeValueForKeyPath:@"isFinished" ofObject:op change:@{ NSKeyValueChangeNewKey : @YES } context:NULL];
            }
        });
    });
}

- (void)_tip_background_removeOperation:(NSOperation *)op
{
    // protect against redundant observer removal
    if ([self->_operations containsObject:op]) {
        [op removeObserver:self forKeyPath:@"isFinished"];
        [self->_operations removeObject:op];
    }
}

/**
 We use KVO to determine when an operation is finished because:

 1) we cannot force all implementations of NSOperation to implement code that needs to execute when finishing
 2) swizzling -didChangeValueForKey: would lead to a MAJOR performance degredation (confirmed by Apple)
 */
- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey,id> *)change context:(void * __nullable)context
{
    if ([keyPath isEqualToString:@"isFinished"] && [change[NSKeyValueChangeNewKey] boolValue]) {
        NSOperation *op = object;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TIPOperationSafetyGuardRemoveOperationAfterFinishedDelay * NSEC_PER_SEC)), _queue, ^{
            [self _tip_background_removeOperation:op];
        });
    }
}

@end

NS_ASSUME_NONNULL_END
