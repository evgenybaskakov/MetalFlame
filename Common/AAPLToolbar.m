//
//  AAPLToolbar.m
//  MetalFlame
//
//  Created by Evgeny Baskakov on 8/9/17.
//  Copyright © 2017 Evgeny Baskakov. All rights reserved.
//

#import "AAPLToolbar.h"

@implementation AAPLToolbar

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [event touchesForView: self];

    // This way we drop any touches within the toolbar.
    // So taps on disabled buttons don't to anything.
    // See https://stackoverflow.com/questions/18965643/ios-prevent-tapping-through-a-disabled-toolbar-button
}

@end
