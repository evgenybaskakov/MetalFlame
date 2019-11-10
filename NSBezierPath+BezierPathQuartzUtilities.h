//
//  NSBezierPath+BezierPathQuartzUtilities.h
//  MetalFlame
//
//  Created by Evgeny Baskakov on 7/14/17.
//  Copyright © 2017 Apple, Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSBezierPath (BezierPathQuartzUtilities)

- (CGPathRef)quartzPath;

@end
