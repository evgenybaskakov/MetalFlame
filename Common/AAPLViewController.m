/*
Copyright © 2017 Evgeny Baskakov. All Rights Reserved.
*/

#import "AAPLViewController.h"
#import "AAPLTopViewController.h"
#import "AAPLRenderer.h"

#if TARGET_OS_IOS || TARGET_OS_TV
#import "DRColorPicker.h"
#endif

@import Metal;
@import simd;
@import MetalKit;

#if TARGET_OS_IOS || TARGET_OS_TV
@interface AAPLViewController () <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *space1;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *backButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *space2;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *saveButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *space3;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *undoButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *space4;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *redoButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *space5;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *paletteButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *space6;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *flameButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *space7;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *sparkButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *space8;
@property (nonatomic, strong) DRColorPickerColor* color;
@property (nonatomic, weak) DRColorPickerViewController* colorPickerVC;
#else
@interface AAPLViewController ()
#endif
@property (nonatomic, weak) MTKView *metalView;
@property (nonatomic, strong) AAPLRenderer *renderer;
@end

@implementation AAPLViewController {
#if TARGET_OS_IOS || TARGET_OS_TV
    UIImage *_backImage;
    UIImage *_saveImage;
    UIImage *_undoImage;
    UIImage *_disabledUndoImage;
    UIImage *_redoImage;
    UIImage *_disabledRedoImage;
    UIImage *_pencilImage;
    UIImage *_flameImage;
    UIImage *_sparkImage;
    UIImage *_paletteImage;
    UIImage *_disabledPaletteImage;
#endif
    NSMutableArray *_createToolbarItems;
    NSMutableArray *_playToolbarItems;
    bool _persistentDraw;
}

#pragma mark - View Controller Methods

- (void)viewDidLoad
{
    [super viewDidLoad];
    
#if TARGET_OS_IOS || TARGET_OS_TV
    _backImage = [[UIImage imageNamed:@"back"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    _saveImage = [[UIImage imageNamed:@"save"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    _undoImage = [[UIImage imageNamed:@"undo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    _disabledUndoImage = [UIImage imageNamed:@"undo"];
    _redoImage = [[UIImage imageNamed:@"redo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    _disabledRedoImage = [UIImage imageNamed:@"redo"];
    _pencilImage = [[UIImage imageNamed:@"pencil"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    _flameImage = [[UIImage imageNamed:@"flame"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    _sparkImage = [[UIImage imageNamed:@"spark"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    _paletteImage = [[UIImage imageNamed:@"palette"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    _disabledPaletteImage = [UIImage imageNamed:@"palette"];
    
    _createToolbarItems = [NSMutableArray arrayWithCapacity:15];
    
    [_createToolbarItems addObject:_space1];
    [_createToolbarItems addObject:_backButton];
    [_createToolbarItems addObject:_space2];
    [_createToolbarItems addObject:_saveButton];
    [_createToolbarItems addObject:_space3];
    [_createToolbarItems addObject:_undoButton];
    [_createToolbarItems addObject:_space4];
    [_createToolbarItems addObject:_redoButton];
    [_createToolbarItems addObject:_space5];
    [_createToolbarItems addObject:_paletteButton];
    [_createToolbarItems addObject:_space6];
    [_createToolbarItems addObject:_flameButton];
    [_createToolbarItems addObject:_space7];
    [_createToolbarItems addObject:_sparkButton];
    [_createToolbarItems addObject:_space8];

    _playToolbarItems = [NSMutableArray arrayWithCapacity:5];
    
    [_playToolbarItems addObject:_space1];
    [_playToolbarItems addObject:_backButton];
    [_playToolbarItems addObject:_space2];
    [_playToolbarItems addObject:_sparkButton];
    [_playToolbarItems addObject:_space3];

    _backButton.image = _backImage;
    _saveButton.image = _saveImage;
    _undoButton.image = _undoImage;
    _redoButton.image = _redoImage;
    _flameButton.image = _flameImage;
    _sparkButton.image = _sparkImage;
    _paletteButton.image = _disabledPaletteImage;
    _paletteButton.tintColor = [UIColor grayColor];

    _toolbar.hidden = YES;
    
    [self disableRedo];
    [self disableUndo];
#endif
}

- (void)show:(bool)persistentDraw {
    if(_metalView == nil) {
        _metalView = (MTKView *)self.view;
        [self setupView];
    }
    else {
        // TODO: clear and reuse the existing metal view
    }
    
    _persistentDraw = persistentDraw;
    
#if TARGET_OS_IOS || TARGET_OS_TV
    self.metalView.multipleTouchEnabled = _persistentDraw ? NO : YES;

    [self configureToolbar];
    
    [_renderer show:_persistentDraw];
    
    _toolbar.hidden = NO;
    _metalView.hidden = NO;
    
    _paletteButton.enabled = (_renderer.pencilMode ? true : false);
#endif
}

- (void)hide {
#if TARGET_OS_IOS || TARGET_OS_TV
    [_renderer hide];

    _toolbar.hidden = YES;
    _metalView.hidden = YES;
#endif
}

#if TARGET_OS_IOS || TARGET_OS_TV
- (void)configureToolbar {
    NSArray *items;
    
    if(_persistentDraw) {
        items = _createToolbarItems;
    }
    else {
        items = _playToolbarItems;
    }

    [_toolbar setItems:items animated:NO];
}

- (void)enableUndo {
    _undoButton.image = _undoImage;
    _undoButton.enabled = true;
}

- (void)enableRedo {
    _redoButton.image = _redoImage;
    _redoButton.enabled = true;
}

- (void)disableUndo {
    _undoButton.image = _disabledUndoImage;
    _undoButton.tintColor = [UIColor grayColor];
    _undoButton.enabled = false;
}

- (void)disableRedo {
    _redoButton.image = _disabledRedoImage;
    _redoButton.tintColor = [UIColor grayColor];
    _redoButton.enabled = false;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}
#endif

#pragma mark - Setup Methods

- (void)setupView
{
    _metalView.device = MTLCreateSystemDefaultDevice();
    NSAssert(_metalView.device, @"no default metal device");
    
    _metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalView.clearColor = MTLClearColorMake(0, 0, 0, 1);

#if TARGET_OS_IOS || TARGET_OS_TV
    _renderer = [[AAPLRenderer alloc] initWithView:_metalView viewController:(AAPLTopViewController*)self.parentViewController];
#else
    _renderer = [[AAPLRenderer alloc] initWithView:_metalView];
#endif

#if TARGET_OS_IOS || TARGET_OS_TV
    self.metalView.userInteractionEnabled = YES;
    
    [self becomeFirstResponder];
#else
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^(NSEvent *event) {
        [self keyDown:event];
        return event;
    }];
#endif
}

#if TARGET_OS_IOS || TARGET_OS_TV

#pragma mark - Toolbar controls

- (IBAction)backAction:(id)sender {
    [self hide];
    
    [(AAPLTopViewController*)self.parentViewController showMainMenu];
}

- (IBAction)saveAction:(id)sender {
    _toolbar.hidden = YES;
    
    [_renderer saveImage];
    
    _toolbar.hidden = NO;
}

- (IBAction)undoAction:(id)sender {
    [_renderer undo];
}

- (IBAction)redoAction:(id)sender {
    [_renderer redo];
}

- (IBAction)paletteAction:(id)sender {
    [self showColorPicker];
}

- (IBAction)flameAction:(id)sender {
    NSAssert(_persistentDraw, @"only can change flame mode in persistent mode");
    
    if(_renderer.pencilMode) {
        _flameButton.image = _flameImage;
        _paletteButton.image = _disabledPaletteImage;
        _paletteButton.tintColor = [UIColor grayColor];
        _renderer.pencilMode = false;
        _paletteButton.enabled = false;
    }
    else {
        _flameButton.image = _pencilImage;
        _paletteButton.image = _paletteImage;
        _renderer.pencilMode = true;
        _paletteButton.enabled = true;
    }
}

- (IBAction)sparkAction:(id)sender {
    [_renderer shakeFlame];
}

#endif

#pragma mark - Interaction (Touch / Mouse) Handling

- (void)stopCurrentDrawing {
    [_renderer stopCurrentDrawing];
}

- (CGPoint)locationInGridForLocationInView:(CGPoint)point
{
    CGSize viewSize = self.view.frame.size;
    CGFloat normalizedWidth = point.x / viewSize.width;
    CGFloat normalizedHeight = point.y / viewSize.height;
    CGFloat gridX = round(normalizedWidth * self.renderer.gridSize.width);
    CGFloat gridY = round(normalizedHeight * self.renderer.gridSize.height);
    return CGPointMake(gridX, gridY);
}

- (void)activateRandomCellsForPoint:(CGPoint)point
{
    // Translate between the coordinate space of the view and the game grid,
    // then forward the request to the compute phase to do the real work
    CGPoint gridLocation = _persistentDraw ? point : [self locationInGridForLocationInView:point];
    [self.renderer activateRandomCellsInNeighborhoodOfCell:gridLocation];
}

#if TARGET_OS_IPHONE
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        CGPoint location = [touch locationInView:self.view];
        [self activateRandomCellsForPoint:location];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        CGPoint location = [touch locationInView:self.view];
        [self activateRandomCellsForPoint:location];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self.renderer stopPointActivation];
}

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    if (motion == UIEventSubtypeMotionShake ) {
        [_renderer shakeFlame];
    }
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
}
#else
- (void)mouseDown:(NSEvent *)event {
    // Translate the cursor position into view coordinates, accounting for the fact that
    // App Kit's default window coordinate space has its origin in the bottom left
    CGPoint location = [self.view convertPoint:[event locationInWindow] fromView:nil];
    location.y = self.view.bounds.size.height - location.y;
    [self activateRandomCellsForPoint:location];
}

- (void)mouseDragged:(NSEvent *)event {
    // Translate the cursor position into view coordinates, accounting for the fact that
    // App Kit's default window coordinate space has its origin in the bottom left
    CGPoint location = [self.view convertPoint:[event locationInWindow] fromView:nil];
    location.y = self.view.bounds.size.height - location.y;
    [self activateRandomCellsForPoint:location];
}

- (void)mouseUp:(NSEvent *)event {
    [self.renderer stopPointActivation];
}

- (void)keyDown:(NSEvent *)event {
    [super keyDown:event];

    if(event.keyCode == 49) {
        [_renderer shakeFlame];
    }
}
#endif

#if TARGET_OS_IOS || TARGET_OS_TV

#pragma mark - Color picker interaction

- (void)showColorPicker
{
    // Setup the color picker - this only has to be done once, but can be called again and again if the values need to change while the app runs
    //    DRColorPickerThumbnailSizeInPointsPhone = 44.0f; // default is 42
    //    DRColorPickerThumbnailSizeInPointsPad = 44.0f; // default is 54
    
    // REQUIRED SETUP....................
    // background color of each view
    DRColorPickerBackgroundColor = [UIColor colorWithWhite:1.0f alpha:1.0f];
    
    // border color of the color thumbnails
    DRColorPickerBorderColor = [UIColor blackColor];
    
    // font for any labels in the color picker
    DRColorPickerFont = [UIFont systemFontOfSize:16.0f];
    
    // font color for labels in the color picker
    DRColorPickerLabelColor = [UIColor blackColor];
    // END REQUIRED SETUP
    
    // OPTIONAL SETUP....................
    // max number of colors in the recent and favorites - default is 200
    DRColorPickerStoreMaxColors = 200;
    
    // show a saturation bar in the color wheel view - default is NO
    DRColorPickerShowSaturationBar = YES;
    
    // highlight the last hue in the hue view - default is NO
    DRColorPickerHighlightLastHue = YES;
    
    // use JPEG2000, not PNG which is the default
    // *** WARNING - NEVER CHANGE THIS ONCE YOU RELEASE YOUR APP!!! ***
    DRColorPickerUsePNG = NO;
    
    // JPEG2000 quality default is 0.9, which really reduces the file size but still keeps a nice looking image
    // *** WARNING - NEVER CHANGE THIS ONCE YOU RELEASE YOUR APP!!! ***
    DRColorPickerJPEG2000Quality = 0.9f;
    
    // set to your shared app group to use the same color picker settings with multiple apps and extensions
    DRColorPickerSharedAppGroup = nil;
    // END OPTIONAL SETUP
    
    // Set initial color.
    if(self.color == nil) {
        self.color = [[DRColorPickerColor alloc] initWithColor:[UIColor whiteColor]];
    }
    
    // create the color picker
    DRColorPickerViewController* vc = [DRColorPickerViewController newColorPickerWithColor:self.color];
    vc.modalPresentationStyle = UIModalPresentationFormSheet;
    vc.rootViewController.showAlphaSlider = YES; // default is YES, set to NO to hide the alpha slider
    
    NSInteger theme = 0; // 0 = default, 1 = dark, 2 = light
    
    // in addition to the default images, you can set the images for a light or dark navigation bar / toolbar theme, these are built-in to the color picker bundle
    if (theme == 0)
    {
        // setting these to nil (the default) tells it to use the built-in default images
        vc.rootViewController.addToFavoritesImage = nil;
        vc.rootViewController.favoritesImage = nil;
        vc.rootViewController.hueImage = nil;
        vc.rootViewController.wheelImage = nil;
        vc.rootViewController.importImage = nil;
    }
    else if (theme == 1)
    {
        vc.rootViewController.addToFavoritesImage = DRColorPickerImage(@"images/dark/drcolorpicker-addtofavorites-dark.png");
        vc.rootViewController.favoritesImage = DRColorPickerImage(@"images/dark/drcolorpicker-favorites-dark.png");
        vc.rootViewController.hueImage = DRColorPickerImage(@"images/dark/drcolorpicker-hue-v3-dark.png");
        vc.rootViewController.wheelImage = DRColorPickerImage(@"images/dark/drcolorpicker-wheel-dark.png");
        vc.rootViewController.importImage = DRColorPickerImage(@"images/dark/drcolorpicker-import-dark.png");
    }
    else if (theme == 2)
    {
        vc.rootViewController.addToFavoritesImage = DRColorPickerImage(@"images/light/drcolorpicker-addtofavorites-light.png");
        vc.rootViewController.favoritesImage = DRColorPickerImage(@"images/light/drcolorpicker-favorites-light.png");
        vc.rootViewController.hueImage = DRColorPickerImage(@"images/light/drcolorpicker-hue-v3-light.png");
        vc.rootViewController.wheelImage = DRColorPickerImage(@"images/light/drcolorpicker-wheel-light.png");
        vc.rootViewController.importImage = DRColorPickerImage(@"images/light/drcolorpicker-import-light.png");
    }
    
    // assign a weak reference to the color picker, need this for UIImagePickerController delegate
    self.colorPickerVC = vc;
    
    // make an import block, this allows using images as colors, this import block uses the UIImagePickerController,
    // but in You Doodle for iOS, I have a more complex import that allows importing from many different sources
    // *** Leave this as nil to not allowing import of textures ***//    vc.rootViewController.importBlock = ^(UINavigationController* navVC, DRColorPickerHomeViewController* rootVC, NSString* title)
//    {
//        UIImagePickerController* p = [[UIImagePickerController alloc] init];
//        p.delegate = self;
//        p.modalPresentationStyle = UIModalPresentationCurrentContext;
//        [self.colorPickerVC presentViewController:p animated:YES completion:nil];
//    };
    
    // dismiss the color picker
    vc.rootViewController.dismissBlock = ^(BOOL cancel)
    {
        [self dismissViewControllerAnimated:YES completion:nil];
    };
    
    // a color was selected, do something with it, but do NOT dismiss the color picker, that happens in the dismissBlock
    vc.rootViewController.colorSelectedBlock = ^(DRColorPickerColor* color, DRColorPickerBaseViewController* vc)
    {
        self.color = color;
        
        if (color.rgbColor == nil)
        {
            _renderer.pencilColor = [UIColor colorWithPatternImage:color.image];
        }
        else
        {
            _renderer.pencilColor = color.rgbColor;
        }
    };
    
    // finally, present the color picker
    [self presentViewController:vc animated:YES completion:nil];
}

- (void) imagePickerController:(UIImagePickerController*)picker didFinishPickingMediaWithInfo:(NSDictionary*)info
{
    // get the image
    UIImage *img = [info objectForKey:UIImagePickerControllerEditedImage];
    if(!img) img = [info objectForKey:UIImagePickerControllerOriginalImage];
    
    // tell the color picker to finish importing
    [self.colorPickerVC.rootViewController finishImport:img];
    
    // dismiss the image picker
    [self.colorPickerVC dismissViewControllerAnimated:YES completion:nil];
}

- (void) imagePickerControllerDidCancel:(UIImagePickerController*)picker
{
    // image picker cancel, just dismiss it
    [self.colorPickerVC dismissViewControllerAnimated:YES completion:nil];
}

#endif

@end
