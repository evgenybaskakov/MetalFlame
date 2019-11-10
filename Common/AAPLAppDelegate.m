/*
Copyright © 2017 Evgeny Baskakov. All Rights Reserved.
*/

#import "AAPLAppDelegate.h"

#if TARGET_OS_IOS || TARGET_OS_TV
@import Firebase;
#endif

@implementation AAPLAppDelegate

#if TARGET_OS_IOS || TARGET_OS_TV

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [FIRApp configure];
    [GADMobileAds configureWithApplicationID:@""];
    return YES;
}

#else

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

#endif

@end
