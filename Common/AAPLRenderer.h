/*
Copyright © 2017 Evgeny Baskakov. All Rights Reserved.
*/

@import Foundation;
@import MetalKit;

@class AAPLTopViewController;

@interface AAPLRenderer : NSObject <MTKViewDelegate>

@property (nonatomic, readonly) MTLSize gridSize;

@property (nonatomic) bool pencilMode;

#if TARGET_OS_IOS || TARGET_OS_TV
@property (nonatomic) UIColor *pencilColor;
#endif

/// Creates a new renderer and makes it the delegate of the view.
/// The grid size of the simulation is derived from the current
/// drawableSize of the view
- (instancetype)initWithView:(MTKView *)view
#if TARGET_OS_IOS || TARGET_OS_TV
              viewController:(AAPLTopViewController*)viewController;
#else
;
#endif

/// Brings random cells in the neighborhood of the provided cell
/// coordinates to life. Can be used with touch or mouse inputs
/// to add interactivity to the simulation.
- (void)activateRandomCellsInNeighborhoodOfCell:(CGPoint)cell;

- (void)stopPointActivation;
- (void)stopCurrentDrawing;
- (void)shakeFlame;

#if TARGET_OS_IOS || TARGET_OS_TV
- (void)saveImage;
- (void)undo;
- (void)redo;
- (void)show:(bool)persistentDraw;
- (void)hide;
#endif

@end
