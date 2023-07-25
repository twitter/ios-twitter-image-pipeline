//
//  TwitterAPI.m
//  TwitterImagePipeline
//
//  Created on 2/3/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TwitterAPI.h"

@import Accounts;
@import Social;
@import TwitterImagePipeline;

FOUNDATION_EXTERN NSString *TIPURLEncodeString(NSString *string);

@interface TweetImageInfo ()
- (instancetype)initWithBaseURLString:(NSString *)baseURLString format:(NSString *)format originalDimensions:(CGSize)originalDimensions;
@end

@interface TweetInfo ()
- (instancetype)initWithHandle:(NSString *)handle text:(NSString *)text images:(NSArray<TweetImageInfo *> *)images;
@end

@interface TwitterAPI ()
- (void)loadAccount;
@end

@implementation TwitterAPI
{
    NSMutableArray *_accountLoadBlocks;
    ACAccount *_account;
    ACAccountStore *_accountStore;
    BOOL _loadingAccount;
    dispatch_queue_t _apiQueue;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _accountStore = [[ACAccountStore alloc] init];
        _apiQueue = dispatch_queue_create("Twitter.API.queue", DISPATCH_QUEUE_SERIAL);
        _accountLoadBlocks = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (instancetype)sharedInstance
{
    static TwitterAPI *sAPI = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sAPI = [[TwitterAPI alloc] init];
        [sAPI loadAccount];
    });
    return sAPI;
}

- (void)loadAccount
{
    dispatch_async(_apiQueue, ^{
        [self _api_loadAccount:NULL];
    });
}

- (void)_api_loadAccount:(dispatch_block_t)complete
{
    if (_account) {
        if (complete) {
            complete();
        }
        return;
    }

    if (complete) {
        [_accountLoadBlocks addObject:complete];
    }
    if (_loadingAccount) {
        return;
    }

    if (@available(iOS 11, *)) { // for when assertions are disabled
        NSString *reason = @"\n\n=== Current iOS not supported ==="
                            "\nThis TIP Sample App has not yet been upgraded to run on iOS 11 or later;"
                            "\nit requires iOS Accounts.framework access, which was removed in iOS 11."
                            "\n===\n\n";
        @throw [NSException exceptionWithName:@"TIPSampleAppRunningOnUnsupportedOSVersion"
                                       reason:reason
                                     userInfo:@{@"OSVersion": NSProcessInfo.processInfo.operatingSystemVersionString}];
    }
#if __IPHONE_11_0 > __IPHONE_OS_VERSION_MIN_REQUIRED
    NSLog(@"Accessing Twitter Account...");
    id<TwitterAPIDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(APIWorkStarted:)]) {
        [delegate APIWorkStarted:self];
    }

    _loadingAccount = YES;
    ACAccountType *type = [_accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    [_accountStore requestAccessToAccountsWithType:type options:nil completion:^(BOOL granted, NSError *error) {
        dispatch_async(self->_apiQueue, ^{
            if (granted) {
                self->_account = self->_accountStore.accounts.firstObject;
                NSLog(@"Access granted: %@", self->_account.username);
            } else {
                NSLog(@"Access denied!");
            }

            if ([delegate respondsToSelector:@selector(APIWorkFinished:)]) {
                [delegate APIWorkFinished:self];
            }

            self->_loadingAccount = NO;
            NSArray *completionBlocks = [self->_accountLoadBlocks copy];
            [self->_accountLoadBlocks removeAllObjects];
            for (dispatch_block_t block in completionBlocks) {
                block();
            }
        });
    }];
#endif
}

- (void)searchForTerm:(NSString *)term count:(NSUInteger)count complete:(void (^)(NSArray<TweetInfo *> *, NSError *))complete
{
    dispatch_async(_apiQueue, ^{
        [self _api_loadAccount:^{
            [self _api_searchForTerm:term count:count complete:complete];
        }];
    });
}

- (void)_api_searchForTerm:(NSString *)term count:(NSUInteger)count complete:(void (^)(NSArray<TweetInfo *> *, NSError *))complete
{
    NSLog(@"Searching for '%@'", term);

    NSError *error = nil;
    NSURLRequest *preparedRequest = nil;

    if (!_account) {
        error = [NSError errorWithDomain:@"Twitter.API" code:0 userInfo:@{ @"message" : @"couldn't open Twitter account!"}];
    } else if (!term) {
        error = [NSError errorWithDomain:@"Twitter.API" code:1 userInfo:@{ @"message" : @"nil search term!" }];
    } else {
        NSURL *requestURL = [NSURL URLWithString:@"https://api.twitter.com/1.1/search/tweets.json"];
        NSDictionary *params = @{
                                 @"count" : @(count).stringValue,
                                 @"adc" : @"phone",
                                 @"q" : term,
                                 };
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        SLRequest *request = [SLRequest requestForServiceType:SLServiceTypeTwitter requestMethod:SLRequestMethodGET URL:requestURL parameters:params];
#pragma clang diagnostic pop
        request.account = _account;
        preparedRequest = request.preparedURLRequest;
    }

    if (!error && !preparedRequest) {
        error = [NSError errorWithDomain:@"Twitter.API" code:2 userInfo:@{ @"message" : @"couldn't construct request!" }];
    }

    if (preparedRequest) {
        id<TwitterAPIDelegate> delegate = self.delegate;
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:preparedRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *theError) {
            dispatch_async(self->_apiQueue, ^{
                NSError *blockError = theError;
                NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
                if (!blockError && statusCode != 200) {
                    blockError = [NSError errorWithDomain:@"Twitter.API" code:3 userInfo:@{ @"statusCode" : @(statusCode), @"message" : [NSString stringWithFormat:@"HTTP %zi", statusCode] }];
                }

                NSArray<TweetInfo *> *parsedResponse = (error) ? nil : [self _api_parseResponse:data];
                if (!parsedResponse) {
                    blockError = [NSError errorWithDomain:@"Twitter.API" code:4 userInfo:@{ @"message" : @"failed to parse response!" }];
                }

                if ([delegate respondsToSelector:@selector(APIWorkFinished:)]) {
                    [delegate APIWorkFinished:self];
                }
                if (complete) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (error) {
                            NSLog(@"Search failed: %@", blockError);
                        } else {
                            NSLog(@"Search completed!");
                        }
                        complete(parsedResponse, blockError);
                    });
                }
            });
        }];

        if ([delegate respondsToSelector:@selector(APIWorkStarted:)]) {
            [delegate APIWorkStarted:self];
        }
        [task resume];
    }

    if (error && complete) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"Search failed: %@", error);
            complete(nil, error);
        });
    }
}

- (NSArray<TweetInfo *> *)_api_parseResponse:(NSData *)data
{
    NSMutableArray<TweetInfo *> *tweets = nil;

    @try {
        NSDictionary *JSONObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSArray *statuses = JSONObject[@"statuses"];
        tweets = [[NSMutableArray alloc] initWithCapacity:statuses.count];
        for (NSDictionary *status in statuses) {
            NSDictionary *user = status[@"user"];
            NSString *handle = user[@"screen_name"];
            if (handle) {
                NSString *text = status[@"text"];

                NSMutableArray<TweetImageInfo *> *images = nil;
                NSDictionary *entities = status[@"entities"];
                const BOOL sensitive = [status[@"possibly_sensitive"] boolValue];
                if (!sensitive) {
                    NSArray *media = entities[@"media"];
                    images = [[NSMutableArray alloc] initWithCapacity:4];
                    for (NSDictionary *mediaItem in media) {
                        NSString *type = mediaItem[@"type"];
                        if ([type isEqual:@"photo"]) {
                            NSString *imageURLString = mediaItem[@"media_url_https"];
                            if (imageURLString) {
                                NSString *format = imageURLString.pathExtension;
                                NSString *baseURLString = [imageURLString substringToIndex:imageURLString.length - (format.length + 1)];
                                NSDictionary *sizes = mediaItem[@"sizes"];
                                NSDictionary *largeVariant = sizes[@"large"];
                                NSInteger w = [largeVariant[@"w"] integerValue];
                                NSInteger h = [largeVariant[@"h"] integerValue];
                                if (0 != w && 0 != h) {
                                    TweetImageInfo *image = [[TweetImageInfo alloc] initWithBaseURLString:baseURLString format:format originalDimensions:CGSizeMake(w, h)];
                                    [images addObject:image];
                                }
                            }
                        }
                    }
                }

                TweetInfo *tweet = [[TweetInfo alloc] initWithHandle:handle text:text images:(images.count > 0) ? images : nil];
                [tweets addObject:tweet];
            }
        }
    } @catch (NSException *exception) {
        // in case we access something unexpected
        NSLog(@"Exception! %@", exception);
    }

    return (tweets.count > 0) ? tweets : nil;
}

@end

@implementation TweetImageInfo

- (instancetype)initWithBaseURLString:(NSString *)baseURLString format:(NSString *)format originalDimensions:(CGSize)originalDimensions
{
    if (self = [super init]) {
        _baseURLString = [baseURLString copy];
        _format = [format copy];
        _originalDimensions = originalDimensions;
    }
    return self;
}

- (NSString *)description
{
    return [@{ @"URL" : _baseURLString, @"format" : _format, @"dimensions" : [NSValue valueWithCGSize:_originalDimensions] } description];
}

@end

@implementation TweetInfo

- (instancetype)initWithHandle:(NSString *)handle text:(NSString *)text images:(NSArray<TweetImageInfo *> *)images
{
    if (self = [super init]) {
        _handle = [@"@" stringByAppendingString:handle];
        _text = [text copy];
        _images = [images copy];
    }
    return self;
}

-(NSString *)description
{
    return [@{ @"handle" : _handle, @"text" : _text, @"images" : (_images ?: [NSNull null]) } description];
}

@end

#define kSMALL  @"small"
#define kMEDIUM @"medium"
#define kLARGE  @"large"

typedef struct {
    void * const name;
    CGFloat const dim;
} VariantInfo;

static VariantInfo const sVariantSizeMap[] = {
    { .name = kSMALL,   .dim = 680 },
    { .name = kMEDIUM,  .dim = 1200 },
    { .name = kLARGE,   .dim = 2048 },
};


NSString *TweetImageDetermineVariant(CGSize aspectRatio, const CGSize dimensions, UIViewContentMode contentMode)
{
    if (aspectRatio.height <= 0 || aspectRatio.width <= 0) {
        aspectRatio = CGSizeMake(1, 1);
    }

    const BOOL scaleToFit = (UIViewContentModeScaleAspectFit == contentMode);
    const CGSize scaledToTargetDimensions = TIPDimensionsScaledToTargetSizing(aspectRatio, dimensions, (scaleToFit ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill));

    NSString * selectedVariantName = nil;
    for (size_t i = 0; i < (sizeof(sVariantSizeMap) / sizeof(sVariantSizeMap[0])); i++) {
        const CGSize variantSize = CGSizeMake(sVariantSizeMap[i].dim, sVariantSizeMap[i].dim);
        const CGSize scaledToVariantDimensions = TIPDimensionsScaledToTargetSizing(aspectRatio, variantSize, UIViewContentModeScaleAspectFit);
        if (scaledToVariantDimensions.width >= scaledToTargetDimensions.width && scaledToVariantDimensions.height >= scaledToTargetDimensions.height) {
            selectedVariantName = (__bridge NSString *)sVariantSizeMap[i].name;
            break;
        }
    }

    if (!selectedVariantName) {
        selectedVariantName = kLARGE;
    }

    return selectedVariantName;
}
