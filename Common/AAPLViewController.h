/*
Copyright © 2017 Evgeny Baskakov. All Rights Reserved.
*/

@import Foundation;

#if TARGET_OS_IOS || TARGET_OS_TV
@import UIKit;
@interface AAPLViewController : UIViewController
#else
@import Cocoa;
@interface AAPLViewController : NSViewController
#endif

- (void)show:(bool)persistentDraw;
- (void)hide;

#if TARGET_OS_IOS || TARGET_OS_TV
- (void)enableUndo;
- (void)enableRedo;

- (void)disableUndo;
- (void)disableRedo;
#endif

- (void)stopCurrentDrawing;

@end
