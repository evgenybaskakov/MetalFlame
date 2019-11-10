/*
Copyright © 2017 Evgeny Baskakov. All Rights Reserved.
*/

#include <TargetConditionals.h>

#if TARGET_OS_IOS || TARGET_OS_TV

@import UIKit;

@interface AAPLAppDelegate : UIResponder <UIApplicationDelegate>

@property (nullable, nonatomic, strong) UIWindow *window;

@end

#elif TARGET_OS_MAC

@import Cocoa;

@interface AAPLAppDelegate : NSObject <NSApplicationDelegate>

@end

#endif
