//
//  AAPLTopViewController.m
//  MetalFlame
//
//  Created by Evgeny Baskakov on 7/16/17.
//  Copyright © 2017 Evgeny Baskakov. All rights reserved.
//

#import "AAPLViewController.h"
#import "AAPLTopViewController.h"

#define kRealAdUnitID @""

#define kIPhone1 @""
#define kIPad1  @""

#define kAdShowShortInterval 10
#define kAdShowLongInterval (10 * 60)

@interface AAPLTopViewController ()
#if TARGET_OS_IOS || TARGET_OS_TV
@property(nonatomic, strong) GADInterstitial *interstitial;
#endif
@end

@implementation AAPLTopViewController {
#if TARGET_OS_IOS || TARGET_OS_TV
    __weak IBOutlet UIView *buttonBox;
    __weak IBOutlet UIButton *createButton;
    __weak IBOutlet UIButton *playButton;
    AAPLViewController *drawableViewController;
    NSTimer *_adTimer;
#endif
}

- (IBAction)createAction:(id)sender {
#if TARGET_OS_IOS || TARGET_OS_TV
    [self scheduleAd:kAdShowShortInterval];
    [drawableViewController show:YES];
    buttonBox.hidden = YES;
#endif
}

- (IBAction)playAction:(id)sender {
#if TARGET_OS_IOS || TARGET_OS_TV
    [self scheduleAd:kAdShowShortInterval];
    [drawableViewController show:NO];
    buttonBox.hidden = YES;
#endif
}

- (void)viewDidLoad
{
    [super viewDidLoad];

#if TARGET_OS_IOS || TARGET_OS_TV
    self.view.backgroundColor = [UIColor clearColor];

    for(UIViewController *child in self.childViewControllers) {
        if([child isKindOfClass:[AAPLViewController class]]) {
            drawableViewController = (AAPLViewController*)child;
            break;
        }
    }
#endif
}

#if TARGET_OS_IOS || TARGET_OS_TV

#pragma mark - undo redo

- (void)enableUndo {
    [drawableViewController enableUndo];
}

- (void)enableRedo {
    [drawableViewController enableRedo];
}

- (void)disableUndo {
    [drawableViewController disableUndo];
}

- (void)disableRedo {
    [drawableViewController disableRedo];
}

#pragma mark - Menu controls

- (void)showMainMenu {
    [_adTimer invalidate];
    buttonBox.hidden = NO;
}

#pragma mark - iOS properties

- (BOOL)prefersStatusBarHidden {
    return YES;
}

#pragma mark - Google ad support

- (void)scheduleAd:(NSTimeInterval)interval {
    [_adTimer invalidate];
    
    _adTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                               repeats:NO
                                                 block:^(NSTimer *timer) {
                                                     [self initializeAdScreen];
                                                 }];
}

- (void)initializeAdScreen {
    self.interstitial = [[GADInterstitial alloc] initWithAdUnitID:kRealAdUnitID];
    self.interstitial.delegate = self;
    GADRequest *request = [GADRequest request];
#ifdef DEBUG
    request.testDevices = @[ kIPhone1, kIPad1 ];
#endif
    [self.interstitial loadRequest:request];
}

- (void)interstitialDidReceiveAd:(GADInterstitial *)ad {
    if(self.interstitial.isReady) {
        [self.interstitial presentFromRootViewController:self];
    }
    else {
        NSLog(@"Ad wasn't ready");
    }
}

- (void)interstitialDidDismissScreen:(GADInterstitial *)ad {
    self.interstitial = nil;

    [self scheduleAd:kAdShowLongInterval];

    [drawableViewController stopCurrentDrawing];
}

#endif

@end
