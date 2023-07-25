//
//  SettingsViewController.m
//  TIP Sample App
//
//  Created on 2/3/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterImagePipeline.h>

#import "AppDelegate.h"
#import "SettingsViewController.h"

@interface SettingsViewController ()
@end

@implementation SettingsViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.navigationItem.title = @"Settings";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrollView.backgroundColor = [UIColor whiteColor];
    scrollView.contentSize = self.view.bounds.size;
    [self.view addSubview:scrollView];

    CGFloat yProgress = 0;
    CGRect viewBounds = self.view.bounds;
    UILabel *label = nil;

    yProgress += 3;
    label = [[UILabel alloc] initWithFrame:CGRectMake(5, yProgress, viewBounds.size.width - 10, 30)];
    label.tag = 'cntL';
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [scrollView addSubview:label];
    yProgress += label.frame.size.height;

    yProgress += 3;
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(5, yProgress, viewBounds.size.width - 10, 56)];
    slider.tag = 'cnt#';
    [slider addTarget:self action:@selector(didUpdateValue:) forControlEvents:UIControlEventValueChanged];
    slider.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    slider.tintColor = self.view.tintColor;
    slider.minimumTrackTintColor = self.view.tintColor;
    slider.value = (MIN(MAX(APP_DELEGATE.searchCount, (NSUInteger)10), (NSUInteger)1000) - 10) / 990.f;
    [self didUpdateValue:slider];
    [scrollView addSubview:slider];
    yProgress += slider.frame.size.height;

    yProgress += 3;
    label = [[UILabel alloc] initWithFrame:CGRectMake(5, yProgress, viewBounds.size.width - 10, 30)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.text = @"WebP Tweet Images";
    [scrollView addSubview:label];
    UISwitch *webpSwitch = [[UISwitch alloc] init];
    webpSwitch.on = APP_DELEGATE.searchWebP;
    webpSwitch.tag = 'webp';
    CGRect webpFrame = webpSwitch.frame;
    webpFrame.origin.y = yProgress;
    webpFrame.origin.x = (viewBounds.size.width - 5) - webpFrame.size.width;
    webpSwitch.frame = webpFrame;
    webpSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [webpSwitch addTarget:self action:@selector(didUpdateValue:) forControlEvents:UIControlEventValueChanged];
    [scrollView addSubview:webpSwitch];
    yProgress += label.frame.size.height;

    yProgress += 3;
    label = [[UILabel alloc] initWithFrame:CGRectMake(5, yProgress, viewBounds.size.width - 10, 30)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.text = @"Debug Overlay";
    [scrollView addSubview:label];
    UISwitch *debugSwitch = [[UISwitch alloc] init];
    debugSwitch.on = [TIPImageViewFetchHelper isDebugInfoVisible];
    debugSwitch.tag = 'dbg.';
    CGRect debugFrame = debugSwitch.frame;
    debugFrame.origin.y = yProgress;
    debugFrame.origin.x = (viewBounds.size.width - 5) - debugFrame.size.width;
    debugSwitch.frame = debugFrame;
    debugSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [debugSwitch addTarget:self action:@selector(didUpdateValue:) forControlEvents:UIControlEventValueChanged];
    [scrollView addSubview:debugSwitch];
    yProgress += label.frame.size.height;

    yProgress += 3;
    label = [[UILabel alloc] initWithFrame:CGRectMake(5, yProgress, viewBounds.size.width - 10, 30)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.text = @"Placeholder Images";
    [scrollView addSubview:label];
    UISwitch *placeholderSwitch = [[UISwitch alloc] init];
    placeholderSwitch.on = [TIPImageViewFetchHelper isDebugInfoVisible];
    placeholderSwitch.tag = 'hldr';
    CGRect placeholderFrame = placeholderSwitch.frame;
    placeholderFrame.origin.y = yProgress;
    placeholderFrame.origin.x = (viewBounds.size.width - 5) - placeholderFrame.size.width;
    placeholderSwitch.frame = placeholderFrame;
    placeholderSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [placeholderSwitch addTarget:self action:@selector(didUpdateValue:) forControlEvents:UIControlEventValueChanged];
    [scrollView addSubview:placeholderSwitch];
    yProgress += label.frame.size.height;
}

- (void)didUpdateValue:(UIControl *)sender
{
    switch (sender.tag) {
        case 'cnt#':
        {
            UISlider *slider = (id)sender;
            APP_DELEGATE.searchCount = (NSUInteger)(slider.value * 990.) + (NSUInteger)10;
            UILabel *label = (id)[self.view viewWithTag:'cntL'];
            label.text = [NSString stringWithFormat:@"Search Count (%tu)", APP_DELEGATE.searchCount];
            break;
        }
        case 'webp':
        {
            UISwitch *s = (id)sender;
            APP_DELEGATE.searchWebP = s.on;
            break;
        }
        case 'dbg.':
        {
            UISwitch *s = (id)sender;
            APP_DELEGATE.debugInfoVisible = s.on;
            break;
        }
        case 'hldr':
        {
            UISwitch *s = (id)sender;
            APP_DELEGATE.usePlaceholder = s.on;
            break;
        }
    }
}

@end
