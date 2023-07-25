//
//  PipelineInspectorViewController.m
//  TwitterImagePipeline
//
//  Created on 2/21/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterImagePipeline.h>

#import "PipelineCacheInspectionResultsViewController.h"
#import "PipelineInspectorViewController.h"

@interface PipelineInspectorViewController () <UITableViewDelegate, UITableViewDataSource>
{
    TIPImagePipelineInspectionResult *_result;
    UITableView *_tableView;
    BOOL _shouldAutoPop;

    PipelineCacheInspectionResultsViewController *_presentedResults;
}

@end

@implementation PipelineInspectorViewController

- (instancetype)initWithPipelineInspectionResult:(TIPImagePipelineInspectionResult *)result
{
    if (self = [self init]) {
        _result = result;
        self.navigationItem.title = result.imagePipeline.identifier;
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (_presentedResults) {
        _shouldAutoPop = _presentedResults.didClearAnyEntries;
        _presentedResults = nil;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (_shouldAutoPop) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }
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

#pragma mark Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 4;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"EntryGroupCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"EntryGroupCell"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    switch (indexPath.row) {
        case 0:
            cell.textLabel.text = [NSString stringWithFormat:@"Rendered Entries (%tu)", _result.completeRenderedEntries.count];
            break;
        case 1:
            cell.textLabel.text = [NSString stringWithFormat:@"Memory Entries (%tu)", _result.completeMemoryEntries.count];
            break;
        case 2:
            cell.textLabel.text = [NSString stringWithFormat:@"Incomplete Disk Entries (%tu)", _result.partialDiskEntries.count];
            break;
        case 3:
        default:
            cell.textLabel.text = [NSString stringWithFormat:@"Complete Disk Entries (%tu)", _result.completeDiskEntries.count];
            break;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSArray<id<TIPImagePipelineInspectionResultEntry>> *entries = nil;
    NSString *name = nil;
    switch (indexPath.row) {
        case 0:
            entries = _result.completeRenderedEntries;
            name = @"Rendered";
            break;
        case 1:
            entries = _result.completeMemoryEntries;
            name = @"Memory";
            break;
        case 2:
            entries = _result.partialDiskEntries;
            name = @"Incomplete Disk";
            break;
        case 3:
        default:
            entries = _result.completeDiskEntries;
            name = @"Complete Disk";
            break;
    }

    _presentedResults = [[PipelineCacheInspectionResultsViewController alloc] initWithResults:entries pipeline:_result.imagePipeline];
    _presentedResults.navigationItem.title = name;
    [self.navigationController pushViewController:_presentedResults animated:YES];
}

@end
