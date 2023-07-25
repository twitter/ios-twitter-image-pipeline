//
//  PipelineCacheInspectionResultsViewController.m
//  TwitterImagePipeline
//
//  Created on 2/21/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterImagePipeline.h>

#import "PipelineCacheInspectionResultsViewController.h"

@interface PipelineCacheInspectionResultsViewController () <UITableViewDelegate, UITableViewDataSource>
{
    NSMutableArray<id<TIPImagePipelineInspectionResultEntry>> *_results;
    TIPImagePipeline *_pipeline;
    UITableView *_tableView;
}

@end

@implementation PipelineCacheInspectionResultsViewController

- (instancetype)initWithResults:(NSArray<id<TIPImagePipelineInspectionResultEntry>> *)results pipeline:(TIPImagePipeline *)pipeline
{
    if (self = [self init]) {
        _pipeline = pipeline;
        _results = [results mutableCopy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    [self.view addSubview:_tableView];
}

#pragma mark Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)_results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"EntryCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"EntryCell"];
        cell.textLabel.numberOfLines = 3;
        cell.textLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    }

    id<TIPImagePipelineInspectionResultEntry> entry = _results[(NSUInteger)indexPath.row];
    cell.imageView.image = entry.image;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    if (entry.progress < 1.f) {
        cell.textLabel.text = [NSString stringWithFormat:@"(%tu%%) %@\n%@\n%@", (NSUInteger)(entry.progress * 100.f), [NSByteCountFormatter stringFromByteCount:(long long)entry.bytesUsed countStyle:NSByteCountFormatterCountStyleBinary], NSStringFromCGSize(entry.dimensions), entry.identifier];
    } else {
        cell.textLabel.text = [NSString stringWithFormat:@"%@\n%@\n%@", [NSByteCountFormatter stringFromByteCount:(long long)entry.bytesUsed countStyle:NSByteCountFormatterCountStyleBinary], NSStringFromCGSize(entry.dimensions), entry.identifier];
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 100;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    const NSUInteger index = (NSUInteger)indexPath.row;
    id<TIPImagePipelineInspectionResultEntry> entry = _results[index];
    UIAlertController *alertVC = [UIAlertController alertControllerWithTitle:@"Clear entry?" message:entry.identifier preferredStyle:UIAlertControllerStyleActionSheet];
    [alertVC addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self _private_clearEntryAtIndexPath:indexPath];
    }]];
    [alertVC addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:NULL]];

    [self presentViewController:alertVC animated:YES completion:NULL];
}

#pragma mark Private

- (void)_private_clearEntryAtIndexPath:(NSIndexPath *)indexPath
{
    const NSUInteger index = (NSUInteger)indexPath.row;
    _didClearAnyEntries = YES;
    id<TIPImagePipelineInspectionResultEntry> entry = _results[index];
    [_pipeline clearImageWithIdentifier:entry.identifier];
    [_results removeObjectAtIndex:index];
    [_tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
