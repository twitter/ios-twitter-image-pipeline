//
//  InspectorViewController.m
//  TwitterImagePipeline
//
//  Created on 2/20/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterImagePipeline.h>

#import "InspectorViewController.h"
#import "PipelineInspectorViewController.h"

@interface InspectorViewController () <UITableViewDelegate, UITableViewDataSource>
{
    UITableView *_tableView;

    NSUUID *_inspectionUUID;
    NSDictionary<NSString *, TIPImagePipelineInspectionResult *> *_results;
    NSArray<NSString *> *_pipelines;
}

@end

@implementation InspectorViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.navigationItem.title = @"Cache Inspector";
    }
    return self;
}

- (void)dealloc
{
    _tableView.dataSource = nil;
    _tableView.delegate = nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.delegate = self;
    _tableView.dataSource = self;

    [self.view addSubview:_tableView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    NSUUID *inspectionUUID = [NSUUID UUID];
    _inspectionUUID = inspectionUUID;
    _results = nil;
    [_tableView reloadData];

    [[TIPGlobalConfiguration sharedInstance] inspect:^(NSDictionary<NSString *, TIPImagePipelineInspectionResult *> *results) {
        [self _private_completeInspectionWithResults:results UUID:inspectionUUID];
    }];
}

#pragma mark Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2; // 1 for the pipelines, 1 for the data usages
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (0 == section) {
        const NSUInteger count = _results.count;
        return (count > 0) ? (NSInteger)count : 1;
    } else {
        return 3; // disk, memory, rendered
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return (0 == section) ? @"Pipelines" : @"Cache usage";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (0 == indexPath.section) {
        if (!_results) {
            return [self _private_plainTextCellForTableView:tableView text:@"Loading..."];
        } else if (_results.count == 0) {
            return [self _private_plainTextCellForTableView:tableView text:@"No Pipelines"];
        } else {
            return [self _private_pipelineCellForTableView:tableView atIndex:(NSUInteger)indexPath.row];
        }
    } else {
        return [self _private_cacheCellForTableView:tableView atIndex:(NSUInteger)indexPath.row];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (0 == indexPath.section) {
        if (_results.count > 0) {
            [self _private_didSelectPipelineAtIndex:(NSUInteger)indexPath.row];
        }
    } else {
        [self _private_didSelectCacheTypeAtIndex:(NSUInteger)indexPath.row];
    }
}

#pragma mark Private

- (UITableViewCell *)_private_plainTextCellForTableView:(UITableView *)tableView text:(NSString *)text
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TextCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TextCell"];
    }
    cell.textLabel.text = text;
    return cell;
}

- (UITableViewCell *)_private_chevronTextCellForTableView:(UITableView *)tableView text:(NSString *)text
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ChevronCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ChevronCell"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.textLabel.text = text;
    return cell;
}

- (UITableViewCell *)_private_pipelineCellForTableView:(UITableView *)tableView atIndex:(NSUInteger)index
{
    return [self _private_chevronTextCellForTableView:tableView text:_pipelines[index]];
}

- (UITableViewCell *)_private_cacheCellForTableView:(UITableView *)tableView atIndex:(NSUInteger)index
{
    NSString *text = nil;
    if (0 == index) {
        text = [NSString stringWithFormat:@"Rendered Cache: %@ / %@", [NSByteCountFormatter stringFromByteCount:[TIPGlobalConfiguration sharedInstance].totalBytesForAllRenderedCaches countStyle:NSByteCountFormatterCountStyleBinary], [NSByteCountFormatter stringFromByteCount:[TIPGlobalConfiguration sharedInstance].maxBytesForAllRenderedCaches countStyle:NSByteCountFormatterCountStyleBinary]];
    } else if (1 == index) {
        text = [NSString stringWithFormat:@"Memory Cache: %@ / %@", [NSByteCountFormatter stringFromByteCount:[TIPGlobalConfiguration sharedInstance].totalBytesForAllMemoryCaches countStyle:NSByteCountFormatterCountStyleBinary], [NSByteCountFormatter stringFromByteCount:[TIPGlobalConfiguration sharedInstance].maxBytesForAllMemoryCaches countStyle:NSByteCountFormatterCountStyleBinary]];
    } else {
        text = [NSString stringWithFormat:@"Disk Cache: %@ / %@", [NSByteCountFormatter stringFromByteCount:[TIPGlobalConfiguration sharedInstance].totalBytesForAllDiskCaches countStyle:NSByteCountFormatterCountStyleBinary], [NSByteCountFormatter stringFromByteCount:[TIPGlobalConfiguration sharedInstance].maxBytesForAllDiskCaches countStyle:NSByteCountFormatterCountStyleBinary]];
    }

    return [self _private_chevronTextCellForTableView:tableView text:text];
}

- (void)_private_didSelectCacheTypeAtIndex:(NSUInteger)index
{
    NSString *cacheTypeName = nil;
    if (0 == index || 1 == index) {
        cacheTypeName = @"rendered & memory";
    } else {
        cacheTypeName = @"disk";
    }

    UIAlertController *alertVC = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Clear %@ caches?", cacheTypeName]
                                                                     message:[NSString stringWithFormat:@"Would you like to remove all cached entries from all %@ caches?", cacheTypeName]
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    [alertVC addAction:[UIAlertAction actionWithTitle:@"Clear them!" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if (0 == index || 1 == index) {
            [[TIPGlobalConfiguration sharedInstance] clearAllMemoryCaches];
        } else {
            [[TIPGlobalConfiguration sharedInstance] clearAllDiskCaches];
        }
    }]];
    [alertVC addAction:[UIAlertAction actionWithTitle:@"Nevermind" style:UIAlertActionStyleCancel handler:NULL]];

    [self presentViewController:alertVC animated:YES completion:NULL];
}

- (void)_private_didSelectPipelineAtIndex:(NSUInteger)index
{
    TIPImagePipelineInspectionResult *result = _results[_pipelines[index]];
    if (!result) {
        return;
    }

    PipelineInspectorViewController *vc = [[PipelineInspectorViewController alloc] initWithPipelineInspectionResult:result];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)_private_completeInspectionWithResults:(NSDictionary<NSString *, TIPImagePipelineInspectionResult *> *)results UUID:(NSUUID *)UUID
{
    if ([_inspectionUUID isEqual:UUID]) {
        _inspectionUUID = nil;
        _results = results;
        _pipelines = [results keysSortedByValueUsingSelector:@selector(compare:)];
        [_tableView reloadData];
    }
}

@end
