//
//  TwitterSearchViewController.m
//  TIP Sample App
//
//  Created on 2/3/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterImagePipeline.h>

#import "AppDelegate.h"
#import "TweetImageFetchRequest.h"
#import "TwitterAPI.h"
#import "TwitterSearchViewController.h"
#import "ZoomingTweetImageViewController.h"

@interface TweetWithMediaTableViewCell : UITableViewCell <TIPImageViewFetchHelperDataSource, TIPImageViewFetchHelperDelegate>
@property (nonatomic) TweetInfo *tweet;
- (instancetype)init;
+ (NSString *)reuseIdentifier;
@end

@interface TwitterSearchViewController () <UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, readonly) UISearchController *searchController;
@property (nonatomic, readonly) UITableView *tableView;
@end

@implementation TwitterSearchViewController
{
    NSString *_term;
    NSArray<TweetInfo *> *_tweets;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.navigationItem.title = @"Twitter Search";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.definesPresentationContext = YES;

    _searchController.searchBar.delegate = self;
    [_searchController.searchBar sizeToFit];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.delegate = self;
    _tableView.dataSource = self;

    _tableView.tableHeaderView = _searchController.searchBar;

    [self.view addSubview:_tableView];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)_tweets.count;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    TweetImageInfo *imageInfo = _tweets[(NSUInteger)indexPath.row].images.firstObject;
    if (imageInfo) {
        ZoomingTweetImageViewController *vc = [[ZoomingTweetImageViewController alloc] initWithTweetImage:imageInfo];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TweetInfo *tweet = _tweets[(NSUInteger)indexPath.row];
    const BOOL hasImages = tweet.images.count > 0;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:(hasImages) ? [TweetWithMediaTableViewCell reuseIdentifier] : @"TweetNoMedia"];
    if (!cell) {
        if (hasImages) {
            cell = [[TweetWithMediaTableViewCell alloc] init];
        } else {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"TweetNoMedia"];
        }
    }

    cell.textLabel.text = tweet.handle;
    cell.detailTextLabel.text = tweet.text;
    if (hasImages) {
        [(TweetWithMediaTableViewCell *)cell setTweet:tweet];
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return (_tweets[(NSUInteger)indexPath.row].images.count > 0) ? 180 : 44;
}

//- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath
//{
//    return (_tweets[(NSUInteger)indexPath.row].images.count > 0) ? 180 : 44;
//}

#pragma mark - Search Controller

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
}

#if TARGET_OS_MACCATALYST
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self performSelector:@selector(_triggerSearch)
               withObject:nil
               afterDelay:0.5];
}
#endif

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [self _triggerSearch];
}

- (void)_triggerSearch
{
    UISearchBar *searchBar = self.searchController.searchBar;
    NSString *search = searchBar.text;
    _term = search;
    _searchController.active = NO;
    _searchController.searchBar.userInteractionEnabled = NO;
    searchBar.text = _term;

    [[TwitterAPI sharedInstance] searchForTerm:_term count:APP_DELEGATE.searchCount complete:^(NSArray<TweetInfo *> *tweets, NSError *error) {
        self->_tweets = [tweets copy];
        self->_searchController.searchBar.userInteractionEnabled = YES;
        [self->_tableView reloadData];
    }];
}

- (void)willPresentSearchController:(UISearchController *)searchController
{
    searchController.searchBar.text = _term;
}

@end

@implementation TweetWithMediaTableViewCell
{
    UIImageView *_tweetImageView;
    TIPImageViewFetchHelper *_tweetFetchHelper;
}

- (instancetype)init
{
    if (self = [self initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:[[self class] reuseIdentifier]]) {

        // logic is decoupled from the View via a "Helper" object

        // Create our helper
        _tweetFetchHelper = [[TIPImageViewFetchHelper alloc] initWithDelegate:self dataSource:self];

        // Create our image view
        _tweetImageView = [[UIImageView alloc] init];
        _tweetImageView.tip_fetchHelper = _tweetFetchHelper;
        _tweetImageView.contentMode = UIViewContentModeScaleAspectFill;
        _tweetImageView.clipsToBounds = YES;
        _tweetImageView.backgroundColor = [UIColor lightGrayColor];
        _tweetImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        // Add image view to content
        [self.contentView addSubview:_tweetImageView];
    }
    return self;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.tweet = nil;
}

- (void)setTweet:(TweetInfo *)info
{
    _tweet = info;
    [_tweetFetchHelper clearImage];
    [_tweetFetchHelper reload];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGRect detailRect = self.detailTextLabel.frame;
    CGRect textRect = self.textLabel.frame;
    CGFloat yDelta = detailRect.origin.y - textRect.origin.y;
    textRect.origin.y = 3;
    detailRect.origin.y = textRect.origin.y + yDelta;
    self.detailTextLabel.frame = detailRect;
    self.textLabel.frame = textRect;

    CGRect imageRect = _tweetImageView.frame;
    imageRect.origin.y = detailRect.origin.y + detailRect.size.height + 3;
    imageRect.origin.x = detailRect.origin.x;
    imageRect.size.width = self.contentView.bounds.size.width - (2 * imageRect.origin.x);
    imageRect.size.height = self.contentView.bounds.size.height - (imageRect.origin.y + 3);
    _tweetImageView.frame = imageRect;
}

+ (NSString *)reuseIdentifier
{
    return @"TweetWithMedia";
}

#pragma mark - data source

- (nullable TIPImagePipeline *)tip_imagePipelineForFetchHelper:(nonnull TIPImageViewFetchHelper *)helper
{
    return [APP_DELEGATE imagePipeline];
}

- (nullable id<TIPImageFetchRequest>)tip_imageFetchRequestForFetchHelper:(nonnull TIPImageViewFetchHelper *)helper
{
    TweetImageInfo *tweetImage = _tweet.images.firstObject;
    if (!tweetImage) {
        return nil;
    }

    TweetImageFetchRequest *request = [[TweetImageFetchRequest alloc] initWithTweetImage:tweetImage targetView:helper.fetchView];
    request.forcePlaceholder = APP_DELEGATE.usePlaceholder;
    return request;
}

#pragma mark - delegate

- (BOOL)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper shouldUpdateImageWithPreviewImageResult:(nonnull id<TIPImageFetchResult>)previewImageResult
{
    return YES;
}

- (BOOL)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper shouldContinueLoadingAfterFetchingPreviewImageResult:(nonnull id<TIPImageFetchResult>)previewImageResult
{
    if (previewImageResult.imageIsTreatedAsPlaceholder) {
        return YES;
    }

    id<TIPImageFetchRequest> request = helper.fetchRequest;
    if ([request respondsToSelector:@selector(options)] && (request.options & TIPImageFetchTreatAsPlaceholder)) {
        // would be a downgrade, stop
        return NO;
    }

    const CGSize originalDimensions = previewImageResult.imageOriginalDimensions;
    const CGSize viewDimensions = TIPDimensionsFromView(helper.fetchView);
    if (originalDimensions.height >= viewDimensions.height && originalDimensions.width >= viewDimensions.width) {
        return NO;
    }

    return YES;
}

- (BOOL)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper shouldLoadProgressivelyWithIdentifier:(nonnull NSString *)identifier URL:(nonnull NSURL *)URL imageType:(nonnull NSString *)imageType originalDimensions:(CGSize)originalDimensions
{
    return YES;
}

//- (BOOL)tip_fetchHelper:(nonnull TIPImageViewFetchHelper *)helper shouldReloadAfterDifferentFetchCompletedWithImageContainer:(nonnull TIPImageContainer *)imageContainer dimensions:(CGSize)dimensions identifier:(nonnull NSString *)identifier URL:(nonnull NSURL *)URL treatedAsPlaceholder:(BOOL)placeholder manuallyStored:(BOOL)manuallyStored
//{
//
//}

@end
