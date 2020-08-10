//
//  TIPImagePipeline.m
//  TwitterImagePipeline
//
//  Created on 2/5/15.
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//

#import "TIP_Project.h"
#import "TIPError.h"
#import "TIPFileUtils.h"
#import "TIPGlobalConfiguration+Project.h"
#import "TIPImageDiskCache.h"
#import "TIPImageDownloader.h"
#import "TIPImageFetchDelegate.h"
#import "TIPImageFetchOperation+Project.h"
#import "TIPImageFetchRequest.h"
#import "TIPImageMemoryCache.h"
#import "TIPImagePipeline+Project.h"
#import "TIPImagePipelineInspectionResult+Project.h"
#import "TIPImageRenderedCache.h"
#import "TIPImageStoreAndMoveOperations.h"

NS_ASSUME_NONNULL_BEGIN

NSString * const TIPImagePipelineDidStoreCachedImageNotification = @"TIPImagePipelineDidStoreCachedImageNotification";
NSString * const TIPImagePipelineDidStandUpImagePipelineNotification = @"TIPImagePipelineDidStandUpImagePipelineNotification";
NSString * const TIPImagePipelineDidTearDownImagePipelineNotification = @"TIPImagePipelineDidTearDownImagePipelineNotification";

NSString * const TIPImagePipelineImageIdentifierNotificationKey = @"imageIdentifier";
NSString * const TIPImagePipelineImageURLNotificationKey = @"imageURL";
NSString * const TIPImagePipelineImageDimensionsNotificationKey = @"imageDimensions";
NSString * const TIPImagePipelineImageContainerNotificationKey = @"imageContainer";
NSString * const TIPImagePipelineImageWasManuallyStoredNotificationKey = @"wasManuallyStored";
NSString * const TIPImagePipelineImagePipelineIdentifierNotificationKey = @"imagePipelineId";
NSString * const TIPImagePipelineImageTreatAsPlaceholderNofiticationKey = @"treatAsPlaceholder";

static NSString * const kImagePipelineFolderName = @"TIPImagePipeline";

#define TIPRegisterAssertMessage(expression, format, ...) \
do { \
    if (TIPShouldAssertDuringPipelineRegistation()) { \
        TIPAssertMessage(expression, format, ##__VA_ARGS__); \
    } else { \
        TIPLogError(@"assertion failed: (" #expression ") message: %@", [NSString stringWithFormat:format, ##__VA_ARGS__]); \
    } \
} while (0)

@interface TIPSimpleImageFetchDelegate ()
@property (nonatomic, readonly, copy, nullable) TIPImagePipelineFetchCompletionBlock completion;
- (instancetype)initWithCompletion:(nullable TIPImagePipelineFetchCompletionBlock)completion;
@end

static NSMapTable *sStrongIdentifierToWeakImagePipelineMap;
static dispatch_queue_t sRegistrationQueue;
static dispatch_once_t sOnceToken = 0;

static void TIPEnsureStaticImagePipelineVariables(void);
static void TIPEnsureStaticImagePipelineVariables(void)
{
    dispatch_once(&sOnceToken, ^{
        sStrongIdentifierToWeakImagePipelineMap = [NSMapTable strongToWeakObjectsMapTable];
        sRegistrationQueue = dispatch_queue_create("TIPImagePipeline.registration.queue", DISPATCH_QUEUE_SERIAL);
    });
}

static BOOL TIPImagePipelineIdentifierIsValid(NSString * identifier);
static BOOL TIPRegisterImagePipelineWithIdentifier(TIPImagePipeline *pipeline, NSString *identifier);
static void TIPUnregisterImagePipelineWithIdentifier(NSString *identifier);
static NSString * TIPImagePipelinePath(void) __attribute__((const));
static NSString * __nullable TIPOpenImagePipelineWithIdentifier(NSString *identifier);
static NSDictionary *TIPCopyAllRegisteredImagePipelines(void);
static void TIPEnqueueOperation(TIPImageFetchOperation *operation);
static void TIPFireFetchCompletionBlock(TIPImagePipelineFetchCompletionBlock __nullable completion,
                                        id<TIPImageFetchResult> __nullable finalResult,
                                        NSError * __nullable error);

@implementation TIPImagePipeline
{
    NSString *_imagePipelinePath;
}

// the following getters may appear superfluous, and would be, if it weren't for the need to
// annotate them with __attribute__((no_sanitize("thread")).  the getters make the @synthesize
// lines necessary.
//
// the reason these are thread-safe is that the ivars are assigned at init time and never
// mutated afterwards making their access thread safe via nonatomic


@synthesize renderedCache = _renderedCache;
@synthesize memoryCache = _memoryCache;
@synthesize diskCache = _diskCache;

- (nullable TIPImageRenderedCache *)renderedCache TIP_THREAD_SANITIZER_DISABLED
{
    return _renderedCache;
}

- (nullable TIPImageMemoryCache *)memoryCache TIP_THREAD_SANITIZER_DISABLED
{
    return _memoryCache;
}

- (nullable TIPImageDiskCache *)diskCache TIP_THREAD_SANITIZER_DISABLED
{
    return _diskCache;
}

#pragma mark Class Methods

+ (NSDictionary<NSString *, TIPImagePipeline *> *)allRegisteredImagePipelines
{
    return TIPCopyAllRegisteredImagePipelines();
}

+ (void)getKnownImagePipelineIdentifiers:(void (^)(NSSet<NSString *> *identifiers))callback
{
    tip_dispatch_async_autoreleasing([TIPGlobalConfiguration sharedInstance].queueForDiskCaches, ^{
        NSMutableSet *identifiers = [[NSMutableSet alloc] init];
        NSString *pipelineDir = TIPImagePipelinePath();
        NSArray<NSURL *> *files = TIPContentsAtPath(pipelineDir, NULL);
        for (NSURL *subdir in files) {
            if ([[subdir resourceValuesForKeys:@[NSURLIsDirectoryKey] error:NULL][NSURLIsDirectoryKey] boolValue]) {
                [identifiers addObject:[subdir lastPathComponent]];
            }
        }

        tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            callback(identifiers);
        });
    });
}

#pragma mark init/dealloc

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort(); // will never be reached, but prevents compiler warning
}

- (void)dealloc
{
    if (_identifier) {
        TIPUnregisterImagePipelineWithIdentifier(_identifier);
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
        [nc postNotificationName:TIPImagePipelineDidTearDownImagePipelineNotification object:nil userInfo:@{ TIPImagePipelineImagePipelineIdentifierNotificationKey : _identifier }];
    }
}

- (nullable instancetype)initWithIdentifier:(NSString *)identifier
{
    identifier = [identifier copy];

    if (self = [super init]) {
        if (!TIPRegisterImagePipelineWithIdentifier(self, identifier)) {
            return nil;
        }

        _identifier = identifier;
        _imagePipelinePath = [TIPOpenImagePipelineWithIdentifier(identifier) copy];
        _diskCache = [[TIPImageDiskCache alloc] initWithPath:_imagePipelinePath];
        _memoryCache = [[TIPImageMemoryCache alloc] init];
        _renderedCache = [[TIPImageRenderedCache alloc] init];
        _downloader = [TIPImageDownloader sharedInstance];

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(_tip_applicationDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [nc postNotificationName:TIPImagePipelineDidStandUpImagePipelineNotification object:self userInfo:@{ TIPImagePipelineImagePipelineIdentifierNotificationKey : _identifier }];
    }

    return self;
}

#pragma mark Generate Operation

- (TIPImageFetchOperation *)operationWithRequest:(id<TIPImageFetchRequest>)request
                                         context:(nullable id)context
                                        delegate:(nullable id<TIPImageFetchDelegate>)delegate
{
    TIPImageFetchOperation *operation = [[TIPImageFetchOperation alloc] initWithImagePipeline:self
                                                                                      request:request
                                                                                     delegate:delegate];
    operation.context = context;
    return operation;
}

- (TIPImageFetchOperation *)operationWithRequest:(id<TIPImageFetchRequest>)request
                                         context:(nullable id)context
                                      completion:(nullable TIPImagePipelineFetchCompletionBlock)completion
{
    TIPSimpleImageFetchDelegate *delegate = [[TIPSimpleImageFetchDelegate alloc] initWithCompletion:completion];
    return [self operationWithRequest:request
                              context:context
                             delegate:delegate];
}

#pragma mark Fetch

- (void)fetchImageWithOperation:(TIPImageFetchOperation *)op
{
    if (!op) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Provided TIPImageFetchOperation is nil"
                                     userInfo:nil];
    }

    if (op.imagePipeline != self) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Provided TIPImageFetchOperation does not belong to the target TIPImagePipeline."
                                     userInfo:@{ @"operation" : op }];
    }

    TIPImageCacheEntry *entry = nil;
    id<TIPImageFetchRequest> request = op.request;

    // Validate the target dimensions
    const CGSize targetDimensions = [request respondsToSelector:@selector(targetDimensions)] ? request.targetDimensions : CGSizeZero;
    const UIViewContentMode targetContentMode = [request respondsToSelector:@selector(targetContentMode)] ? request.targetContentMode : UIViewContentModeCenter;
    if (!TIPSizeGreaterThanZero(targetDimensions) && !TIPSizeEqualToZero(targetDimensions)) {
        NSDictionary *userInfo = @{
                                   TIPProblemInfoKeyTargetDimensions : [NSValue valueWithCGSize:targetDimensions],
                                   TIPProblemInfoKeyTargetContentMode : @(targetContentMode),
                                   TIPProblemInfoKeyImageIdentifier : op.imageIdentifier ?: @"",
                                   TIPProblemInfoKeyImageURL : op.imageURL ?: @"",
                                   TIPProblemInfoKeyFetchRequest : request,
                                   };
        [[TIPGlobalConfiguration sharedInstance] postProblem:TIPProblemImageFetchHasInvalidTargetDimensions userInfo:userInfo];
    }

    // Perform synchronous access?
    NSString *imageId = op.imageIdentifier;
    NSString *transformerId = op.transformerIdentifier;
    CGSize sourceImageDimensions = CGSizeZero;
    BOOL isDirty = NO;
    if ([NSThread isMainThread] && [op supportsLoadingFromRenderedCache] && (imageId != nil)) {
        // Sync Access, for optimization
        entry = [_renderedCache imageEntryWithIdentifier:imageId
                                   transformerIdentifier:transformerId
                                        targetDimensions:targetDimensions
                                       targetContentMode:targetContentMode
                                   sourceImageDimensions:&sourceImageDimensions
                                                   dirty:&isDirty];
    }

    if (entry.completeImage) {
        if (!isDirty) {
            // Sync Completion
            [op completeOperationEarlyWithImageEntry:entry
                                         transformed:(transformerId != nil)
                               sourceImageDimensions:sourceImageDimensions];
            return;
        }

        // Sync early preview
        [op handleEarlyLoadOfDirtyImageEntry:entry
                                 transformed:(transformerId != nil)
                       sourceImageDimensions:sourceImageDimensions];
    }

    // Async Operation
    TIPEnqueueOperation(op);
}

#pragma mark Store / Move

- (NSObject<TIPDependencyOperation> *)changeIdentifierForImageWithIdentifier:(NSString *)currentIdentifier
                                                                toIdentifier:(NSString *)newIdentifier
                                                                  completion:(nullable TIPImagePipelineOperationCompletionBlock)completion
{
    TIPImageMoveOperation *moveOp = [[TIPImageMoveOperation alloc] initWithPipeline:self
                                                                 originalIdentifier:currentIdentifier
                                                                  updatedIdentifier:newIdentifier
                                                                         completion:completion];
    [[TIPGlobalConfiguration sharedInstance] enqueueImagePipelineOperation:moveOp];
    return moveOp;
}

- (NSObject<TIPDependencyOperation> *)storeImageWithRequest:(id<TIPImageStoreRequest>)request
                                                 completion:(nullable TIPImagePipelineOperationCompletionBlock)completion
{
    TIPImageStoreOperation *storeOp = [self storeOperationWithRequest:request
                                                           completion:completion];
    TIPImageStoreHydrationOperation *prepOp = [self _createHydrationOperationWithRequest:request];
    if (prepOp) {
        [storeOp setHydrationDependency:prepOp];
        [[TIPGlobalConfiguration sharedInstance] enqueueImagePipelineOperation:prepOp];
    }
    [[TIPGlobalConfiguration sharedInstance] enqueueImagePipelineOperation:storeOp];
    return storeOp;
}

- (TIPImageStoreOperation *)storeOperationWithRequest:(id<TIPImageStoreRequest>)request
                                           completion:(nullable TIPImagePipelineOperationCompletionBlock)completion
{
    return [[TIPImageStoreOperation alloc] initWithRequest:request
                                                  pipeline:self
                                                completion:completion];
}

- (nullable TIPImageStoreHydrationOperation *)_createHydrationOperationWithRequest:(id<TIPImageStoreRequest>)request TIP_OBJC_DIRECT
{
    id<TIPImageStoreRequestHydrater> hydrater = [request respondsToSelector:@selector(hydrater)] ? request.hydrater : nil;
    if (!hydrater) {
        return nil;
    }

    return [[TIPImageStoreHydrationOperation alloc] initWithRequest:request
                                                           pipeline:self
                                                           hydrater:hydrater];
}

#pragma mark Clear

- (void)clearImageWithIdentifier:(NSString *)imageIdentifier
{
    TIPAssert(imageIdentifier != nil);
    [_renderedCache clearImageWithIdentifier:imageIdentifier];
    [_memoryCache clearImageWithIdentifier:imageIdentifier];
    [_diskCache clearImageWithIdentifier:imageIdentifier];
}

- (void)clearRenderedMemoryCacheImageWithIdentifier:(NSString *)imageIdentifier
{
    TIPAssert(imageIdentifier != nil);
    [_renderedCache clearImageWithIdentifier:imageIdentifier];
}

- (void)dirtyRenderedMemoryCacheImageWithIdentifier:(NSString *)imageIdentifier
{
    TIPAssert(imageIdentifier != nil);
    [_renderedCache dirtyImageWithIdentifier:imageIdentifier];
}

- (void)clearMemoryCaches
{
    [_renderedCache clearAllImages:NULL];
    [_memoryCache clearAllImages:NULL];
}

- (void)clearDiskCache
{
    [_diskCache clearAllImages:NULL];
}

#pragma mark Copy Disk Cache File

- (void)copyDiskCacheFileWithIdentifier:(NSString *)imageIdentifier
                             completion:(nullable TIPImagePipelineCopyFileCompletionBlock)completion
{
    TIPAssert(imageIdentifier != nil);
    NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
        [self _background_copyDiskCacheFileWithIdentifier:imageIdentifier
                                               completion:completion];
    }];
    [[TIPGlobalConfiguration sharedInstance] enqueueImagePipelineOperation:op];
}

- (void)_background_copyDiskCacheFileWithIdentifier:(NSString *)imageIdentifier
                                         completion:(nullable TIPImagePipelineCopyFileCompletionBlock)completion TIP_OBJC_DIRECT
{
    // Copy to temp location
    NSString *temporaryFile = nil;
    NSError *error = nil;
    temporaryFile = [self.diskCache copyImageEntryFileForIdentifier:imageIdentifier
                                                              error:&error];

    // Indicate completion
    if (completion) {
        completion(temporaryFile, error);
    }

    // Clean up the temporary file
    if (temporaryFile) {
        [[NSFileManager defaultManager] removeItemAtPath:temporaryFile error:NULL];
    }
}

#pragma mark Post Completed

- (void)postCompletedEntry:(TIPImageCacheEntry *)entry manual:(BOOL)manual
{
    if (!entry.identifier || !entry.completeImageContext.URL) {
        return;
    }

    tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:6];
        if (entry.completeImage) {
            userInfo[TIPImagePipelineImageContainerNotificationKey] = entry.completeImage;
        }
        userInfo[TIPImagePipelineImageIdentifierNotificationKey] = entry.identifier;
        userInfo[TIPImagePipelineImageURLNotificationKey] = entry.completeImageContext.URL;
        userInfo[TIPImagePipelineImageDimensionsNotificationKey] = [NSValue valueWithCGSize:entry.completeImageContext.dimensions];
        userInfo[TIPImagePipelineImageWasManuallyStoredNotificationKey] = @(manual);
        userInfo[TIPImagePipelineImagePipelineIdentifierNotificationKey] = self.identifier;
        userInfo[TIPImagePipelineImageTreatAsPlaceholderNofiticationKey] = @(entry.completeImageContext.treatAsPlaceholder);

        [[NSNotificationCenter defaultCenter] postNotificationName:TIPImagePipelineDidStoreCachedImageNotification
                                                            object:self
                                                          userInfo:userInfo];
    });
}

#pragma mark Properties

- (nullable id<TIPImageCache>)cacheOfType:(TIPImageCacheType)type
{
    switch (type) {
        case TIPImageCacheTypeDisk:
            return self.diskCache;
        case TIPImageCacheTypeMemory:
            return self.memoryCache;
        case TIPImageCacheTypeRendered:
            return self.renderedCache;
    }
    return nil;
}

#pragma mark Private

- (void)_tip_applicationDidEnterBackground
{
    if ([TIPGlobalConfiguration sharedInstance].clearMemoryCachesOnApplicationBackgroundEnabled) {

        dispatch_block_t endBackgroundTaskBlock = TIPStartBackgroundTask([NSString stringWithFormat:@"[%@ %@]", NSStringFromClass([self class]), NSStringFromSelector(_cmd)]);
        [_renderedCache weakifyEntries];
        [_memoryCache clearAllImages:endBackgroundTaskBlock];

    }
}

@end

@implementation TIPImagePipeline (Inspect)

- (void)inspect:(TIPImagePipelineInspectionCallback)callback
{
    TIPImagePipelineInspectionResult *result = [[TIPImagePipelineInspectionResult alloc] initWithImagePipeline:self];
    [self.renderedCache inspect:^(NSArray *completedEntries, NSArray *partialEntries) {
        [result addEntries:completedEntries];
        [result addEntries:partialEntries];
        [self.memoryCache inspect:^(NSArray *memoryCachedCompletedEntries, NSArray *memoryCachePartialEntries) {
            [result addEntries:memoryCachedCompletedEntries];
            [result addEntries:memoryCachePartialEntries];
            [self.diskCache inspect:^(NSArray *diskCacheCompletedEntries, NSArray *diskCachePartialEntries) {
                [result addEntries:diskCacheCompletedEntries];
                [result addEntries:diskCachePartialEntries];
                tip_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
                    callback(result);
                });
            }];
        }];
    }];
}

@end

@implementation TIPSimpleImageFetchDelegate

- (instancetype)initWithCompletion:(nullable TIPImagePipelineFetchCompletionBlock)completion
{
    if (self = [super init]) {
        _completion = [completion copy];
    }
    return self;
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
              didLoadFinalImage:(id<TIPImageFetchResult>)finalResult
{
    TIPFireFetchCompletionBlock(self.completion, finalResult, nil);
}

- (void)tip_imageFetchOperation:(TIPImageFetchOperation *)op
        didFailToLoadFinalImage:(NSError *)error
{
    TIPFireFetchCompletionBlock(self.completion, nil, error);
}

@end

static BOOL TIPImagePipelineIdentifierIsValid(NSString *identifier)
{
    static NSCharacterSet *sCharSet = nil;
    if (!sCharSet) {
        NSRange r;
        r = NSMakeRange('0', '9'-'0' + 1);
        NSMutableCharacterSet *charSet = [NSMutableCharacterSet characterSetWithRange:r];
        r = NSMakeRange('a', 'z'-'a' + 1);
        [charSet addCharactersInRange:r];
        r = NSMakeRange('A', 'Z'-'A' + 1);
        [charSet addCharactersInRange:r];
        [charSet addCharactersInString:@"._-"];
        [charSet invert];
        sCharSet = [charSet copy];
    }
    if (identifier.length == 0) {
        return NO;
    }
    NSRange range = [identifier rangeOfCharacterFromSet:sCharSet];
    if (range.location != NSNotFound) {
        return NO;
    }
    return YES;
}

static BOOL TIPRegisterImagePipelineWithIdentifier(TIPImagePipeline *pipeline, NSString *identifier)
{
    if (!identifier) {
        TIPRegisterAssertMessage(identifier != nil, @"%@ cannot have a nil identifier!", NSStringFromClass([TIPImagePipeline class]));
        return NO;
    }

    if (!pipeline) {
        TIPRegisterAssertMessage(pipeline != nil, @"Cannot register nil pipeline!");
        return NO;
    }

    TIPEnsureStaticImagePipelineVariables();

    __block struct {
        BOOL didRegister:1;
        BOOL alreadyRegistered:1;
        BOOL isInvalidIdentifier:1;
    } flags;
    flags.didRegister = flags.alreadyRegistered = flags.isInvalidIdentifier = 0;

    dispatch_sync(sRegistrationQueue, ^{

        if (TIPImagePipelineIdentifierIsValid(identifier)) {

            if (![sStrongIdentifierToWeakImagePipelineMap objectForKey:identifier]) {
                [sStrongIdentifierToWeakImagePipelineMap setObject:pipeline forKey:identifier];
                flags.didRegister = 1;
            } else {
                flags.alreadyRegistered = 1;
            }

        } else {
            flags.isInvalidIdentifier = 1;
        }

    });

    TIPRegisterAssertMessage(!flags.alreadyRegistered, @"%@ already exists with identifier '%@'!", NSStringFromClass([TIPImagePipeline class]), identifier);
    TIPRegisterAssertMessage(!flags.isInvalidIdentifier, @"%@ cannot be created with identifier '%@'!", NSStringFromClass([TIPImagePipeline class]), identifier);
    if (flags.didRegister) {
        TIPLogDebug(@"<%@ '%@'> registered!", NSStringFromClass([pipeline class]), identifier);
    }

    return flags.didRegister;
}

static void TIPUnregisterImagePipelineWithIdentifier(NSString *identifier)
{
    if (!identifier) {
        TIPRegisterAssertMessage(identifier != nil, @"Cannot dealloc %@ with nil identifier!", NSStringFromClass([TIPImagePipeline class]));
        return;
    }

    TIPEnsureStaticImagePipelineVariables();

    tip_dispatch_async_autoreleasing(sRegistrationQueue, ^{
        TIPRegisterAssertMessage([sStrongIdentifierToWeakImagePipelineMap objectForKey:identifier] == nil, @"%@'s identifier (%@) still in use, should not unregister!", NSStringFromClass([TIPImagePipeline class]), identifier);
        TIPLogDebug(@"<%@ '%@'> unregistered!", NSStringFromClass([TIPImagePipeline class]), identifier);
        [sStrongIdentifierToWeakImagePipelineMap removeObjectForKey:identifier];
    });
}

static NSString *TIPImagePipelinePath(void)
{
    static NSString *sPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sPath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
#if !TARGET_OS_IPHONE || TARGET_OS_MACCATALYST
        // platform may be non-sandboxed, or "sandbox" may contain sym-links outside of expected sandbox
        // ensure unique path using bundle-id for safety (if possible)
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleId) {
            sPath = [sPath stringByResolvingSymlinksInPath];
            if (![sPath containsString:[NSString stringWithFormat:@"/%@/", bundleId]]) {
                sPath = [sPath stringByAppendingPathComponent:bundleId];
            }
        }
#endif
        sPath = [sPath stringByAppendingPathComponent:kImagePipelineFolderName];
    });
    return sPath;
}

static NSString * __nullable TIPOpenImagePipelineWithIdentifier(NSString *identifier)
{
    NSString *path = TIPImagePipelinePath();
    path = [path stringByAppendingPathComponent:identifier];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error;
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
        TIPLogError(@"Failed to open images store at path: %@\nContinuing without an on disk cache", path);
        path = nil;
    }
    return path;
}

static NSDictionary *TIPCopyAllRegisteredImagePipelines()
{
    TIPEnsureStaticImagePipelineVariables();

    __block NSDictionary *pipelines;
    tip_dispatch_sync_autoreleasing(sRegistrationQueue, ^{
        pipelines = sStrongIdentifierToWeakImagePipelineMap.dictionaryRepresentation;
    });
    return pipelines;
}

static void TIPEnqueueOperation(TIPImageFetchOperation *operation)
{
    [operation willEnqueue];
    [[TIPGlobalConfiguration sharedInstance] enqueueImagePipelineOperation:operation];
}

static void TIPFireFetchCompletionBlock(TIPImagePipelineFetchCompletionBlock __nullable completion,
                                        id<TIPImageFetchResult> __nullable finalResult,
                                        NSError * __nullable error)
{
    if (completion) {
        completion(finalResult, error);
    }
}

NS_ASSUME_NONNULL_END
