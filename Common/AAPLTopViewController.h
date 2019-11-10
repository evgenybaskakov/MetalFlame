//
//  AAPLTopViewController.h
//  MetalFlame
//
//  Created by Evgeny Baskakov on 7/16/17.
//  Copyright © 2017 Evgeny Baskakov. All rights reserved.
//

@import Foundation;

#if TARGET_OS_IOS || TARGET_OS_TV
@import GoogleMobileAds;
@import UIKit;
@interface AAPLTopViewController : UIViewController<GADInterstitialDelegate>
- (void)showMainMenu;
- (void)enableUndo;
- (void)enableRedo;
- (void)disableUndo;
- (void)disableRedo;
@end
#else
@import Cocoa;
@interface AAPLTopViewController : NSViewController
@end
#endif
