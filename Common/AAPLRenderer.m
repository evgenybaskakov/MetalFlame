/*
Copyright © 2017 Evgeny Baskakov. All Rights Reserved.
*/

#import <QuartzCore/CAShapeLayer.h>

#import "AAPLRenderer.h"
#import "AAPLTopViewController.h"

#if TARGET_OS_IOS || TARGET_OS_TV
#else
#import "NSBezierPath+BezierPathQuartzUtilities.h"
#endif

#define kDefaultPencilColor [UIColor whiteColor]

static const NSUInteger kTextureCount = 2;
static const NSUInteger kPencilLineWidth = 4;
static const NSInteger kMaxInflightBuffers = 3;

typedef struct {
    float ft;
    unsigned int frame;
    uint seed;
    bool warp;
    bool shake;
    bool persistentDraw;
} GameState;

typedef struct {
    float x, y, xv, yv;
} WarpOffset;

typedef struct {
    float x, y, xv, yv;
    float hot;
    float speed;
} Spark;

@interface PencilLine : NSObject
#if TARGET_OS_IOS || TARGET_OS_TV
@property UIBezierPath *path;
@property UIColor *color;
#else
@property NSBezierPath *path;
@property NSColor *color;
#endif
@property bool onePoint;
- (id)init;
@end

@implementation PencilLine
- (id)init {
    self = [super init];
    return self;
}
@end

@interface FlameLine : NSObject
@property NSUInteger persistentPointCount;
@property NSUInteger activationCellCount;
- (id)init;
@end

@implementation FlameLine
- (id)init {
    self = [super init];
    return self;
}
@end

#define kMaxCoolingValue 8
#define kWarpCoefficient 1.0
#define kWarpBlockSize 16
#define kWarpFrame 2
#define kLastActivationPointLivenessTime 0.4
#define kShakeDuration 1.0

static const packed_float4 colorMap[] = {
    {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0},
    {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0},
    {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0},
    {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0},
    {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0},
    {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0},
    {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0}, {0.00,0.00,0.00,1.0},
    {0.02,0.00,0.00,1.0}, {0.02,0.00,0.00,1.0}, {0.02,0.00,0.00,1.0}, {0.02,0.00,0.00,1.0},
    {0.02,0.00,0.00,1.0}, {0.02,0.00,0.00,1.0}, {0.02,0.00,0.00,1.0}, {0.03,0.00,0.00,1.0},
    {0.03,0.00,0.00,1.0}, {0.03,0.00,0.00,1.0}, {0.03,0.00,0.00,1.0}, {0.03,0.00,0.00,1.0},
    {0.05,0.00,0.00,1.0}, {0.05,0.00,0.00,1.0}, {0.05,0.00,0.00,1.0}, {0.05,0.00,0.00,1.0},
    {0.06,0.02,0.00,1.0}, {0.06,0.02,0.00,1.0}, {0.06,0.02,0.00,1.0}, {0.06,0.02,0.00,1.0},
    {0.08,0.02,0.00,1.0}, {0.08,0.02,0.00,1.0}, {0.08,0.02,0.00,1.0}, {0.09,0.02,0.00,1.0},
    {0.09,0.02,0.00,1.0}, {0.09,0.02,0.00,1.0}, {0.11,0.02,0.00,1.0}, {0.11,0.03,0.00,1.0},
    {0.12,0.03,0.00,1.0}, {0.12,0.03,0.00,1.0}, {0.12,0.03,0.00,1.0}, {0.14,0.03,0.00,1.0},
    {0.14,0.03,0.00,1.0}, {0.16,0.03,0.00,1.0}, {0.16,0.03,0.00,1.0}, {0.17,0.03,0.00,1.0},
    {0.17,0.05,0.00,1.0}, {0.19,0.05,0.00,1.0}, {0.19,0.05,0.00,1.0}, {0.20,0.05,0.00,1.0},
    {0.20,0.05,0.00,1.0}, {0.22,0.05,0.00,1.0}, {0.22,0.06,0.00,1.0}, {0.23,0.06,0.00,1.0},
    {0.23,0.06,0.00,1.0}, {0.25,0.06,0.00,1.0}, {0.27,0.06,0.00,1.0}, {0.27,0.06,0.00,1.0},
    {0.28,0.08,0.00,1.0}, {0.28,0.08,0.00,1.0}, {0.30,0.08,0.00,1.0}, {0.31,0.08,0.00,1.0},
    {0.31,0.08,0.00,1.0}, {0.33,0.09,0.00,1.0}, {0.34,0.09,0.00,1.0}, {0.34,0.09,0.00,1.0},
    {0.36,0.09,0.00,1.0}, {0.36,0.11,0.00,1.0}, {0.38,0.11,0.00,1.0}, {0.39,0.11,0.00,1.0},
    {0.39,0.11,0.00,1.0}, {0.41,0.12,0.00,1.0}, {0.42,0.12,0.00,1.0}, {0.42,0.12,0.00,1.0},
    {0.44,0.12,0.00,1.0}, {0.45,0.14,0.00,1.0}, {0.47,0.14,0.00,1.0}, {0.47,0.14,0.00,1.0},
    {0.48,0.14,0.00,1.0}, {0.50,0.16,0.00,1.0}, {0.50,0.16,0.00,1.0}, {0.52,0.16,0.00,1.0},
    {0.53,0.17,0.00,1.0}, {0.53,0.17,0.00,1.0}, {0.55,0.17,0.00,1.0}, {0.56,0.19,0.00,1.0},
    {0.56,0.19,0.00,1.0}, {0.58,0.19,0.00,1.0}, {0.59,0.20,0.00,1.0}, {0.59,0.20,0.00,1.0},
    {0.61,0.20,0.00,1.0}, {0.62,0.22,0.00,1.0}, {0.62,0.22,0.02,1.0}, {0.64,0.22,0.02,1.0},
    {0.64,0.23,0.02,1.0}, {0.66,0.23,0.02,1.0}, {0.67,0.23,0.02,1.0}, {0.67,0.25,0.02,1.0},
    {0.69,0.25,0.02,1.0}, {0.69,0.25,0.02,1.0}, {0.70,0.27,0.02,1.0}, {0.72,0.27,0.02,1.0},
    {0.72,0.28,0.02,1.0}, {0.73,0.28,0.02,1.0}, {0.73,0.28,0.02,1.0}, {0.75,0.30,0.02,1.0},
    {0.75,0.30,0.02,1.0}, {0.77,0.30,0.02,1.0}, {0.77,0.31,0.02,1.0}, {0.78,0.31,0.02,1.0},
    {0.78,0.33,0.02,1.0}, {0.80,0.33,0.02,1.0}, {0.80,0.33,0.02,1.0}, {0.81,0.34,0.02,1.0},
    {0.81,0.34,0.02,1.0}, {0.81,0.36,0.02,1.0}, {0.83,0.36,0.02,1.0}, {0.83,0.36,0.02,1.0},
    {0.84,0.38,0.02,1.0}, {0.84,0.38,0.02,1.0}, {0.84,0.39,0.02,1.0}, {0.86,0.39,0.03,1.0},
    {0.86,0.41,0.03,1.0}, {0.86,0.41,0.03,1.0}, {0.88,0.41,0.03,1.0}, {0.88,0.42,0.03,1.0},
    {0.88,0.42,0.03,1.0}, {0.89,0.44,0.03,1.0}, {0.89,0.44,0.03,1.0}, {0.89,0.45,0.03,1.0},
    {0.89,0.45,0.03,1.0}, {0.91,0.45,0.03,1.0}, {0.91,0.47,0.03,1.0}, {0.91,0.47,0.03,1.0},
    {0.91,0.48,0.03,1.0}, {0.92,0.48,0.03,1.0}, {0.92,0.50,0.03,1.0}, {0.92,0.50,0.03,1.0},
    {0.92,0.50,0.03,1.0}, {0.92,0.52,0.03,1.0}, {0.94,0.52,0.03,1.0}, {0.94,0.53,0.05,1.0},
    {0.94,0.53,0.05,1.0}, {0.94,0.55,0.05,1.0}, {0.94,0.55,0.05,1.0}, {0.94,0.55,0.05,1.0},
    {0.94,0.56,0.05,1.0}, {0.95,0.56,0.05,1.0}, {0.95,0.58,0.05,1.0}, {0.95,0.58,0.05,1.0},
    {0.95,0.58,0.05,1.0}, {0.95,0.59,0.05,1.0}, {0.95,0.59,0.05,1.0}, {0.95,0.61,0.05,1.0},
    {0.95,0.61,0.05,1.0}, {0.95,0.62,0.05,1.0}, {0.95,0.62,0.05,1.0}, {0.97,0.62,0.05,1.0},
    {0.97,0.64,0.06,1.0}, {0.97,0.64,0.06,1.0}, {0.97,0.66,0.06,1.0}, {0.97,0.66,0.06,1.0},
    {0.97,0.66,0.06,1.0}, {0.97,0.67,0.06,1.0}, {0.97,0.67,0.06,1.0}, {0.97,0.67,0.06,1.0},
    {0.97,0.69,0.06,1.0}, {0.97,0.69,0.06,1.0}, {0.97,0.70,0.06,1.0}, {0.97,0.70,0.06,1.0},
    {0.97,0.70,0.06,1.0}, {0.97,0.72,0.06,1.0}, {0.97,0.72,0.08,1.0}, {0.97,0.72,0.08,1.0},
    {0.97,0.73,0.08,1.0}, {0.97,0.73,0.08,1.0}, {0.97,0.73,0.08,1.0}, {0.97,0.75,0.08,1.0},
    {0.97,0.75,0.08,1.0}, {0.97,0.75,0.08,1.0}, {0.97,0.77,0.08,1.0}, {0.97,0.77,0.08,1.0},
    {0.97,0.77,0.08,1.0}, {0.97,0.78,0.08,1.0}, {0.97,0.78,0.09,1.0}, {0.97,0.78,0.09,1.0},
    {0.97,0.78,0.09,1.0}, {0.97,0.80,0.09,1.0}, {0.97,0.80,0.09,1.0}, {0.97,0.80,0.09,1.0},
    {0.97,0.81,0.09,1.0}, {0.97,0.81,0.09,1.0}, {0.97,0.81,0.09,1.0}, {0.97,0.81,0.09,1.0},
    {0.97,0.83,0.09,1.0}, {0.97,0.83,0.09,1.0}, {0.97,0.83,0.11,1.0}, {0.97,0.83,0.11,1.0},
    {0.97,0.84,0.11,1.0}, {0.97,0.84,0.11,1.0}, {0.97,0.84,0.11,1.0}, {0.97,0.84,0.11,1.0},
    {0.97,0.86,0.11,1.0}, {0.97,0.86,0.11,1.0}, {0.97,0.86,0.11,1.0}, {0.97,0.86,0.11,1.0},
    {0.97,0.86,0.12,1.0}, {0.97,0.88,0.12,1.0}, {0.97,0.88,0.12,1.0}, {0.97,0.88,0.12,1.0},
    {0.97,0.88,0.12,1.0}, {0.97,0.88,0.12,1.0}, {0.97,0.89,0.12,1.0}, {0.97,0.89,0.12,1.0},
    {0.97,0.89,0.12,1.0}, {0.97,0.89,0.12,1.0}, {0.97,0.89,0.14,1.0}, {0.97,0.89,0.14,1.0},
    {0.97,0.91,0.14,1.0}, {0.97,0.91,0.14,1.0}, {0.97,0.91,0.14,1.0}, {0.97,0.91,0.14,1.0},
    {0.97,0.91,0.14,1.0}, {0.97,0.91,0.14,1.0}, {0.97,0.92,0.14,1.0}, {0.97,0.92,0.16,1.0},
    {0.97,0.92,0.16,1.0}, {0.97,0.92,0.16,1.0}, {0.97,0.92,0.16,1.0}, {0.97,0.92,0.16,1.0},
    {0.97,0.92,0.16,1.0}, {0.97,0.92,0.16,1.0}, {0.97,0.94,0.16,1.0}, {0.97,0.94,0.17,1.0},
    {0.97,0.94,0.17,1.0}, {0.97,0.94,0.17,1.0}, {0.97,0.94,0.17,1.0}, {0.97,0.94,0.17,1.0}
};

@interface AAPLRenderer ()
@property (nonatomic, weak) MTKView *view;
@property (nonatomic, weak) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLLibrary> library;
@property (nonatomic, strong) id<MTLRenderPipelineState> renderPipelineState;
@property (nonatomic, strong) id<MTLComputePipelineState> simulationPipelineState;
@property (nonatomic, strong) id<MTLSamplerState> samplerState;
@property (nonatomic, strong) NSMutableArray<id<MTLTexture>> *textureQueue;
@property (nonatomic, strong) id<MTLBuffer> sparkBuffer;
@property (nonatomic, strong) id<MTLBuffer> activationPointBuffer;
@property (nonatomic, strong) id<MTLBuffer> colorMapBuffer;
@property (nonatomic, strong) NSMutableArray<id<MTLBuffer>> *warpMapBuffers;
@property (nonatomic, strong) NSMutableArray<id<MTLBuffer>> *sparkMapBuffers;
@property (nonatomic, strong) id<MTLBuffer> coolMapBuffer;
@property (nonatomic, strong) id<MTLTexture> currentGameStateTexture;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, strong) NSMutableArray<NSValue *> *activationPoints;
@property (nonatomic, strong) NSMutableArray<NSValue *> *pencilPoints;
@property (nonatomic, strong) dispatch_semaphore_t inflightSemaphore;
@property (nonatomic, strong) NSDate *nextResizeTimestamp;
@end

@implementation AAPLRenderer {
    GameState _gameState[2];
    unsigned int _gameFrame;
    unsigned long _numOffsets;
    NSUInteger _prevPencilPointCount;
    NSUInteger _persistentPointCount;
    NSUInteger _activationCellCount;
    NSUInteger _activationCellCapacity;
    packed_uint2 *_activationCells;
    bool _pointActivationStopped;
    bool _shakeFlame;
    NSTimer *_stopShakeTimer;
    CALayer *_backgroundLayer;
    CAShapeLayer *_pencilDrawingLayer;
#if TARGET_OS_IOS || TARGET_OS_TV
    UIBezierPath *_pencilPath;
#else
    NSBezierPath *_pencilPath;
#endif
#if TARGET_OS_IOS || TARGET_OS_TV
    AAPLTopViewController *_viewController;
    UIAlertController *_alert;
#endif
    NSDictionary *_drawActions;
    bool _onePointDrawn;
    bool _persistentDraw;
    NSMutableArray<PencilLine*> *_pencilHistory;
    NSMutableArray<FlameLine*> *_flameHistory;
    NSMutableArray<NSNumber*> *_combinedHistory;
    NSUInteger _pencilHistoryPos;
    NSUInteger _flameHistoryPos;
    NSUInteger _combinedHistoryPos;
    bool _drawingFlame;
    NSUInteger _activationPointBufferDataLen;
    ushort *_activationPointBufferData;
}

#pragma mark - Initializer

- (instancetype)initWithView:(MTKView *)view
#if TARGET_OS_IOS || TARGET_OS_TV
              viewController:(AAPLTopViewController*)viewController;
#endif
{
    if (view.device == nil) {
        NSLog(@"Cannot create renderer without the view already having an associated Metal device");
        return nil;
    }
    
    if ((self = [super init]))
    {
        _view = view;
        _view.delegate = self;
        
#if TARGET_OS_IOS || TARGET_OS_TV
        _viewController = viewController;
#endif
        
        _device = _view.device;
        _library = [_device newDefaultLibrary];
        _commandQueue = [_device newCommandQueue];
        
        _activationPoints = [NSMutableArray array];
        _pencilPoints = [NSMutableArray array];
        _textureQueue = [NSMutableArray arrayWithCapacity:kTextureCount];
        
        _gameFrame = 0;
        
        _gameState[0].ft = 0;
        _gameState[0].frame = 0;
        
        _drawActions = @{
                         @"onOrderIn": [NSNull null],
                         @"onOrderOut": [NSNull null],
                         @"sublayers": [NSNull null],
                         @"contents": [NSNull null],
                         @"position": [NSNull null],
                         @"bounds": [NSNull null]
                         };
        
        _pencilHistory = [NSMutableArray array];
        _flameHistory = [NSMutableArray array];
        _combinedHistory = [NSMutableArray array];

        [self buildRenderResources];
        [self buildRenderPipeline];
        [self buildComputePipelines];
        
        [self reshapeWithDrawableSize:_view.drawableSize];
        
        self.inflightSemaphore = dispatch_semaphore_create(kMaxInflightBuffers);
        
        [self initBackgroundLayer];
    }
    
    return self;
}

- (void)drawPencilLine {
    NSAssert(_pencilPoints.count >= _prevPencilPointCount, @"_pencilPoints.count %lu, _prevPencilPointCount %lu", (unsigned long)_pencilPoints.count, (unsigned long)_prevPencilPointCount);
    
    if((_prevPencilPointCount == 0 && _pencilPoints.count == 1) || (_pencilPoints.count - _prevPencilPointCount > 0)) {
        CGColorRef color;
#if TARGET_OS_IOS || TARGET_OS_TV
        color = CGColorRetain([(_pencilColor != nil? _pencilColor : kDefaultPencilColor) CGColor]);
#else
        color = CGColorRetain([[NSColor whiteColor] CGColor]);
#endif

        if(_prevPencilPointCount == 0 && _pencilPoints.count == 1) {
            _pencilDrawingLayer = [CAShapeLayer layer];

            CGPoint from;
            [_pencilPoints[_prevPencilPointCount] getValue:&from];

#if TARGET_OS_IOS || TARGET_OS_TV
            _pencilPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(from.x-kPencilLineWidth/2, from.y-kPencilLineWidth/2, kPencilLineWidth, kPencilLineWidth)];
            _pencilDrawingLayer.path = [_pencilPath CGPath];
#else
            _pencilPath = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(from.x-kPencilLineWidth/2, from.y-kPencilLineWidth/2, kPencilLineWidth, kPencilLineWidth)];
            _pencilDrawingLayer.path = [_pencilPath quartzPath];
#endif

            _pencilDrawingLayer.opacity = 1.0;
            _pencilDrawingLayer.lineWidth = 0;
            _pencilDrawingLayer.strokeColor = color;
            _pencilDrawingLayer.fillColor = color;
            _pencilDrawingLayer.actions = _drawActions;
            
            [_backgroundLayer addSublayer:_pencilDrawingLayer];

            _onePointDrawn = true;
        }
        else {
            if(_pencilDrawingLayer == nil || _onePointDrawn) {
                _pencilDrawingLayer = [CAShapeLayer layer];
#if TARGET_OS_IOS || TARGET_OS_TV
                _pencilPath = [UIBezierPath bezierPath];
#else
                _pencilPath = [NSBezierPath bezierPath];
#endif

                _pencilDrawingLayer.opacity = 1.0;
                _pencilDrawingLayer.lineWidth = kPencilLineWidth;
                _pencilDrawingLayer.lineCap = @"round";
                _pencilDrawingLayer.lineJoin = @"round";
                _pencilDrawingLayer.strokeColor = color;
                _pencilDrawingLayer.fillColor = color;
                _pencilDrawingLayer.actions = _drawActions;
                
                [_backgroundLayer addSublayer:_pencilDrawingLayer];
            }

            NSUInteger startPoint = (_prevPencilPointCount > 0 ? _prevPencilPointCount - 1 : 0);
            
            CGPoint from;
            [_pencilPoints[startPoint] getValue:&from];

            [_pencilPath moveToPoint:from];

            for(NSUInteger i = startPoint + 1; i < _pencilPoints.count; i++) {
                CGPoint to;
                [_pencilPoints[i] getValue:&to];
                
#if TARGET_OS_IOS || TARGET_OS_TV
                [_pencilPath addLineToPoint:to];
#else
                [_pencilPath lineToPoint:to];
#endif
                
                from = to;
            }

            _onePointDrawn = false;
        }
        
        CGColorRelease(color);

#if TARGET_OS_IOS || TARGET_OS_TV
        _pencilDrawingLayer.path = [_pencilPath CGPath];
#else
        _pencilDrawingLayer.path = [_pencilPath quartzPath];
#endif
    }
    
    if(_pointActivationStopped) {
        if(_pencilPath != nil) {
            PencilLine *pencilLineEntry = [[PencilLine alloc] init];

            pencilLineEntry.path = _pencilPath;
#if TARGET_OS_IOS || TARGET_OS_TV
            pencilLineEntry.color = [UIColor colorWithCGColor:_pencilDrawingLayer.strokeColor];
#else
            pencilLineEntry.color = [NSColor colorWithCGColor:_pencilDrawingLayer.strokeColor];
#endif
            pencilLineEntry.onePoint = _onePointDrawn;
            
            [self removeRedoHistory];

            [_pencilHistory addObject:pencilLineEntry];
            [_combinedHistory addObject:[NSNumber numberWithBool:NO]];
            
            _pencilHistoryPos++;
            _combinedHistoryPos++;
            
#if TARGET_OS_IOS || TARGET_OS_TV
            [_viewController enableUndo];
#endif
        }
        
        _prevPencilPointCount = 0;
        [_pencilPoints removeAllObjects];
        
#if TARGET_OS_IOS || TARGET_OS_TV
        UIGraphicsBeginImageContextWithOptions(_backgroundLayer.bounds.size, NO, 0.0);
        
        [_backgroundLayer renderInContext: UIGraphicsGetCurrentContext()];
        
        UIImage *layerImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        _backgroundLayer.contents = (id)layerImage.CGImage;
        _backgroundLayer.sublayers = nil;
        _pencilPath = nil;
        _pencilDrawingLayer = nil;
#endif
    }
    else {
        _prevPencilPointCount = _pencilPoints.count;
    }
}

- (void)initBackgroundLayer {
    _backgroundLayer = [CALayer layer];
    
    _backgroundLayer.bounds = self.view.bounds;
    
#if TARGET_OS_IOS || TARGET_OS_TV
    _backgroundLayer.backgroundColor = [[UIColor blackColor] CGColor];
    _backgroundLayer.position = CGPointMake(self.view.bounds.origin.x+_backgroundLayer.bounds.size.width/2, self.view.bounds.origin.y+_backgroundLayer.bounds.size.height/2);
#else
    _backgroundLayer.geometryFlipped = YES;
    _backgroundLayer.backgroundColor = [[NSColor blackColor] CGColor];
    _backgroundLayer.position = NSMakePoint(self.view.bounds.origin.x+_backgroundLayer.bounds.size.width/2, self.view.bounds.origin.y+_backgroundLayer.bounds.size.height/2);
#endif
    
    _backgroundLayer.actions = _drawActions;
    
    CALayer *metalLayer = self.view.layer;
    metalLayer.opaque = NO;

#if TARGET_OS_IOS || TARGET_OS_TV
#else
    NSView *superview = self.view.superview;
    [superview.layer insertSublayer:_backgroundLayer below:self.view.layer];
#endif
    
    self.view.framebufferOnly = false;
}

#if TARGET_OS_IOS || TARGET_OS_TV
- (void)undo {
    if(_combinedHistoryPos == 0) {
        NSAssert(_pencilHistoryPos == 0 && _flameHistoryPos == 0,
                 @"combined history is empty, but pencil history has %lu pos, flame history has %lu pos",
                 (unsigned long)_pencilHistoryPos, (unsigned long)_flameHistoryPos);
        return;
    }
    
    NSNumber *flameUndo = _combinedHistory[--_combinedHistoryPos];
    
    if(flameUndo.boolValue) {
        NSAssert(_flameHistoryPos != 0, @"_flameHistoryPos is 0");

        _flameHistoryPos--;
        
        if(_flameHistoryPos == 0) {
            _persistentPointCount = 0;
            _activationCellCount = 0;
        }
        else {
            _persistentPointCount = _flameHistory[_flameHistoryPos-1].persistentPointCount;
            _activationCellCount = _flameHistory[_flameHistoryPos-1].activationCellCount;
        }

        [self clearActivationBuffer];
        [self restoreActivationCells];
    }
    else {
        NSAssert(_pencilHistoryPos != 0, @"_pencilHistoryPos is 0");

        _pencilHistoryPos--;

        [self mergePencilLayersUpTo:_pencilHistoryPos];
    }

#if TARGET_OS_IOS || TARGET_OS_TV
    [_viewController enableRedo];
    
    if(_combinedHistoryPos == 0) {
        [_viewController disableUndo];
    }
#endif
}

- (void)redo {
    NSAssert(_pencilHistoryPos <= _pencilHistory.count, @"_pencilHistoryPos %lu, _pencilHistory.count %lu", (unsigned long)_pencilHistoryPos, (unsigned long)_pencilHistory.count);
    NSAssert(_flameHistoryPos <= _flameHistory.count, @"_flameHistoryPos %lu, _flameHistory.count %lu", (unsigned long)_flameHistoryPos, (unsigned long)_flameHistory.count);
    NSAssert(_combinedHistoryPos <= _combinedHistory.count, @"_combinedHistoryPos %lu, _combinedHistory.count %lu", (unsigned long)_combinedHistoryPos, (unsigned long)_combinedHistory.count);
    
    if(_combinedHistoryPos == _combinedHistory.count) {
        NSAssert(_pencilHistoryPos == _pencilHistory.count, @"_pencilHistoryPos %lu, _pencilHistory.count %lu", (unsigned long)_pencilHistoryPos, (unsigned long)_pencilHistory.count);
        NSAssert(_flameHistoryPos == _flameHistory.count, @"_flameHistoryPos %lu, _flameHistory.count %lu", (unsigned long)_flameHistoryPos, (unsigned long)_flameHistory.count);
        return;
    }

    NSNumber *flameRedo = _combinedHistory[_combinedHistoryPos++];
    
    if(flameRedo.boolValue) {
        NSAssert(_flameHistoryPos < _flameHistory.count, @"_flameHistoryPos %lu, _flameHistory.count %lu", (unsigned long)_flameHistoryPos, (unsigned long)_flameHistory.count);
        
        _flameHistoryPos++;
        
        _persistentPointCount = _flameHistory[_flameHistoryPos-1].persistentPointCount;
        _activationCellCount = _flameHistory[_flameHistoryPos-1].activationCellCount;
        
        [self clearActivationBuffer];
        [self restoreActivationCells];
    }
    else {
        NSAssert(_pencilHistoryPos < _pencilHistory.count, @"_pencilHistoryPos %lu, _pencilHistory.count %lu", (unsigned long)_pencilHistoryPos, (unsigned long)_pencilHistory.count);
        
        _pencilHistoryPos++;
        
        [self mergePencilLayersUpTo:_pencilHistoryPos];
    }

#if TARGET_OS_IOS || TARGET_OS_TV
    [_viewController enableUndo];
    
    if(_combinedHistoryPos == _combinedHistory.count) {
        [_viewController disableRedo];
    }
#endif
}

- (void)restoreActivationCells {
    for(NSUInteger i = 0; i < _activationCellCount; i++) {
        [self putActivationCellsAtX:_activationCells[i].x y:_activationCells[i].y];
    }
}

- (void)mergePencilLayersUpTo:(NSUInteger)pencilLayerCount {
    [self clearBackgroundLayer];
    
    _backgroundLayer.sublayers = nil;
    
    for(NSUInteger i = 0; i < pencilLayerCount; i++) {
        PencilLine *l = _pencilHistory[i];
        CAShapeLayer *layer = [CAShapeLayer layer];
        
        layer.path = [l.path CGPath];
        layer.opacity = 1.0;
        layer.lineWidth = l.onePoint ? 0 : kPencilLineWidth;
        layer.lineCap = @"round";
        layer.lineJoin = @"round";
        layer.strokeColor = [l.color CGColor];
        layer.fillColor = [l.color CGColor];
        layer.actions = _drawActions;
        
        [_backgroundLayer addSublayer:layer];
    }
    
    UIGraphicsBeginImageContextWithOptions(_backgroundLayer.bounds.size, NO, 0.0);
    
    [_backgroundLayer renderInContext: UIGraphicsGetCurrentContext()];
    
    UIImage *layerImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    _backgroundLayer.contents = (id)layerImage.CGImage;
    _backgroundLayer.sublayers = nil;
    _pencilPath = nil;
    _pencilDrawingLayer = nil;
}

- (void)saveImage {
    // 1. Get the metal view image
    id<MTLTexture> lastDrawableDisplayed = [self.view.currentDrawable texture];
    int width = (int)[lastDrawableDisplayed width];
    int height = (int)[lastDrawableDisplayed height];
    int rowBytes = width * 4;
    int selfturesize = width * height * 4;
    void *p = malloc(selfturesize);
    if(!p) {
        NSLog(@"failed to allocate %u bytes", selfturesize);
        abort();
        
        return;
    }
    
    [lastDrawableDisplayed getBytes:p bytesPerRow:rowBytes fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0];
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaFirst;
    CGDataProviderRef provider = CGDataProviderCreateWithData(nil, p, selfturesize, nil);
    CGImageRef cgImageRef = CGImageCreate(width, height, 8, 32, rowBytes, colorSpace, bitmapInfo, provider, nil, true, (CGColorRenderingIntent)kCGRenderingIntentDefault);
    UIImage *metalImage = [UIImage imageWithCGImage:cgImageRef];
    
    // 2. Get the background view image
    UIGraphicsBeginImageContextWithOptions(_backgroundLayer.bounds.size, NO, 0.0);
    [_backgroundLayer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *backgroundImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    // 3. Render those two images on top of each other to a third image
    UIGraphicsBeginImageContextWithOptions(self.view.bounds.size, NO, 0.0);
    [backgroundImage drawInRect:CGRectMake(0.0, 0.0, self.view.bounds.size.width, self.view.bounds.size.height)];
    [metalImage drawInRect:self.view.bounds];
    UIImage *layerImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    // 4. Write the layered image to the photo album
    UIImageWriteToSavedPhotosAlbum(layerImage,
                                   self,
                                   @selector(completeSavedImage:didFinishSavingWithError:contextInfo:), nil);

    // 5. Release the resources used
    CFRelease(cgImageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    free(p);
}

- (void)completeSavedImage:(UIImage *)_image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    _alert = [UIAlertController alertControllerWithTitle:(error? @"Could not save image" : @"Image saved")
                                                 message:(error? error.localizedDescription : nil)
                                          preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        if(_alert != nil) {
            [_alert dismissViewControllerAnimated:YES completion:nil];
            _alert = nil;
        }
    }];
    
    [_alert addAction:okAction];
    [_viewController presentViewController:_alert animated:YES completion:nil];
}

- (void)show:(bool)persistentDraw {
    _persistentDraw = persistentDraw;

    if(_persistentDraw) {
        UIView *superview = self.view.superview;
        [superview.layer insertSublayer:_backgroundLayer below:self.view.layer];
    }
}

- (void)hide {
    if(_persistentDraw) {
        [_backgroundLayer removeFromSuperlayer];

        NSArray<CALayer*> *sublayers = _backgroundLayer.sublayers.copy;
        for(CALayer *sublayer in sublayers) {
            [sublayer removeFromSuperlayer];
        }

        _persistentPointCount = 0;
        _activationCellCount = 0;
        
        [_activationPoints removeAllObjects];
        [_pencilPoints removeAllObjects];
        [_pencilHistory removeAllObjects];
        [_flameHistory removeAllObjects];
        [_combinedHistory removeAllObjects];
        
        _combinedHistoryPos = 0;
        _pencilHistoryPos = 0;
        _flameHistoryPos = 0;
        
        _drawingFlame = NO;
        
        [self stopPointActivation];
        [self clearActivationBuffer];
        [self clearBackgroundLayer];
        
        [_viewController disableUndo];
        [_viewController disableRedo];
    }
}

- (void)clearActivationBuffer {
    memset(_activationPointBufferData, 0, _activationPointBufferDataLen);
}

- (void)clearBackgroundLayer {
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, _backgroundLayer.bounds.size.width, _backgroundLayer.bounds.size.height) cornerRadius:0];
    CAShapeLayer *fillLayer = [CAShapeLayer layer];
    fillLayer.path = path.CGPath;
    fillLayer.fillRule = kCAFillRuleEvenOdd;
    fillLayer.fillColor = [UIColor blackColor].CGColor;
    fillLayer.opacity = 1;
    [_backgroundLayer addSublayer:fillLayer];
    
    UIGraphicsBeginImageContextWithOptions(_backgroundLayer.bounds.size, NO, 0.0);
    
    [_backgroundLayer renderInContext: UIGraphicsGetCurrentContext()];
    
    UIImage *layerImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    _backgroundLayer.contents = (id)layerImage.CGImage;
    _backgroundLayer.sublayers = nil;
}
#endif

- (void)initGameState {
    [self initColorMap];
    [self initWarpMap];
    [self initCoolMap];
    [self initSparkMap];
    [self initActivationPointBuffer];
}

- (void)initColorMap {
    _colorMapBuffer = [_device newBufferWithBytes:colorMap
                                           length:sizeof(colorMap)
                                          options:MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared];
    
    _colorMapBuffer.label = @"Color Map Buffer";
}

- (void)initWarpMap {
    unsigned long start_x = 0, end_x = _gridSize.width / kWarpBlockSize + 1;
    unsigned long start_y = 0, end_y = _gridSize.height / kWarpBlockSize + 1;
    
    _numOffsets = (end_x - start_x + 1) * (end_y - start_y + 1);
    
    WarpOffset *offsets = calloc(sizeof(WarpOffset), _numOffsets);
    NSAssert(offsets, @"could not allocate offsets");

    float t0 = 0, t1 = 0, t2 = 0, t3 = 0;
    
    for(unsigned long off = 0, y = start_y; y <= end_y; y++) {
        unsigned long yf = y;
        
        for(unsigned long x = start_x; x <= end_x; x++, off++) {
            unsigned long xf = x;
            
            t0 += 0.081;
            t1 += 0.083;
            t2 += 0.085;
            t3 += 0.087;
            
            float tx = x * kWarpBlockSize;
            float ty = y * kWarpBlockSize;
            
            if((x != start_x) && (x != end_x) && (y != start_y) && (y != end_y)) {
                tx += kWarpCoefficient * (sin(t2-xf) + cos(t2+yf) + sin(t0-yf) - cos(t0+xf));
                ty += kWarpCoefficient * (sin(t1-xf) + cos(t3+yf) + sin(t3-yf) - cos(t1+xf));
            }
            
            offsets[off].x = tx;
            offsets[off].y = ty;
            offsets[off].xv = 0;
            offsets[off].yv = 0;
            
            //printf("x %lu -> %.03f, y %lu -> %.03f, xv %.03f, yv %.03f\n", x*kWarpBlockSize, tx, y*kWarpBlockSize, ty, 0.0, 0.0);
        }
    }

    // Create a buffer to hold the static vertex data
    id<MTLBuffer> warpMapBuffer1 = [_device newBufferWithBytes:offsets
                                                        length:sizeof(WarpOffset) * _numOffsets
                                                       options:MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared];
    warpMapBuffer1.label = @"Warp Map 1";

    id<MTLBuffer> warpMapBuffer2 = [_device newBufferWithBytes:offsets
                                                        length:sizeof(WarpOffset) * _numOffsets
                                                       options:MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared];
    warpMapBuffer1.label = @"Warp Map 2";

    _warpMapBuffers = [NSMutableArray arrayWithObjects:warpMapBuffer1, warpMapBuffer2, nil];
    
    free(offsets);
}

- (void)initSparkMap {
    ushort *sparkMapBuf = calloc(sizeof(ushort), _gridSize.width * _gridSize.height);
    NSAssert(sparkMapBuf, @"could not allocate emptyBuf with ushort");

    id<MTLBuffer> sparkMapBuffer1 = [_device newBufferWithBytes:sparkMapBuf
                                                         length:sizeof(ushort) * _gridSize.width * _gridSize.height
                                                        options:MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared];
    sparkMapBuffer1.label = @"Spark Map 1";
    
    id<MTLBuffer> sparkMapBuffer2 = [_device newBufferWithBytes:sparkMapBuf
                                                         length:sizeof(ushort) * _gridSize.width * _gridSize.height
                                                        options:MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared];
    sparkMapBuffer2.label = @"Spark Map 2";

    _sparkMapBuffers = [NSMutableArray arrayWithObjects:sparkMapBuffer1, sparkMapBuffer2, nil];
    
    free(sparkMapBuf);

    Spark *sparkBuf = (Spark *)calloc(sizeof(Spark), _gridSize.width * _gridSize.height);
    NSAssert(sparkBuf, @"could not allocate emptyBuf with Spark");

    _sparkBuffer = [_device newBufferWithBytes:sparkBuf
                                        length:sizeof(Spark) * _gridSize.width * _gridSize.height
                                       options:MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared];
    sparkMapBuffer2.label = @"Spark Buffer";
    
    free(sparkBuf);
}

- (void)initActivationPointBuffer {
    NSUInteger pageSize = getpagesize();
    
    _activationPointBufferDataLen = (sizeof(ushort) * _gridSize.width * _gridSize.height + pageSize - 1) & ~(pageSize - 1);
    int result = posix_memalign((void**)&_activationPointBufferData, pageSize, _activationPointBufferDataLen);
    if(result != 0) {
        NSLog(@"failed to allocate %lu bytes for _activationPointBuffer", (unsigned long)_activationPointBufferDataLen);
        abort();
    }
    
    _activationPointBuffer = [_device newBufferWithBytesNoCopy:_activationPointBufferData
                                                        length:_activationPointBufferDataLen
                                                       options:MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared
                                                   deallocator:nil];

    _activationPointBuffer.label = @"Activation Point Buffer";
}

- (void)initCoolMap {
    unsigned long numElems = _gridSize.width * _gridSize.height;
    
    ushort *coolmap = calloc(sizeof(ushort), numElems);
    NSAssert(coolmap, @"could not allocate coolmaps");
    
    for(unsigned long i = 0; i < numElems; i++) {
        coolmap[i] = rand() % kMaxCoolingValue;
    }
    
    _coolMapBuffer = [_device newBufferWithBytes:coolmap
                                          length:sizeof(ushort) * numElems
                                         options:MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared];

    _coolMapBuffer.label = @"Cooling Map";
    
    free(coolmap);
}

#pragma mark - Resource and Pipeline Creation

#if TARGET_OS_IOS || TARGET_OS_TV
- (CGImageRef)CGImageForImageNamed:(NSString *)imageName {
    UIImage *image = [UIImage imageNamed:imageName];
    return [image CGImage];
}
#else
- (CGImageRef)CGImageForImageNamed:(NSString *)imageName {
    NSImage *image = [NSImage imageNamed:imageName];
    return [image CGImageForProposedRect:NULL context:nil hints:nil];
}
#endif

- (void)buildRenderResources
{
    // Vertex data for a full-screen quad. The first two numbers in each row represent
    // the x, y position of the point in normalized coordinates. The second two numbers
    // represent the texture coordinates for the corresponding position.
    static const float vertexData[] = {
        -1,  1, 0, 0,
        -1, -1, 0, 1,
         1, -1, 1, 1,
         1, -1, 1, 1,
         1,  1, 1, 0,
        -1,  1, 0, 0,
    };
    
    // Create a buffer to hold the static vertex data
    _vertexBuffer = [_device newBufferWithBytes:vertexData
                                         length:sizeof(vertexData)
                                        options:MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared];
    _vertexBuffer.label = @"Fullscreen Quad Vertices";
}

- (void)buildRenderPipeline {
    NSError *error = nil;
    
    // Retrieve the functions we need to build the render pipeline
    id<MTLFunction> vertexProgram = [_library newFunctionWithName:@"lighting_vertex"];
    id<MTLFunction> fragmentProgram = [_library newFunctionWithName:@"lighting_fragment"];

    // Create a vertex descriptor that describes a vertex with two float2 members:
    // position and texture coordinates
    MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor new];
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[1].offset = sizeof(float) * 2;
    vertexDescriptor.attributes[1].bufferIndex = 0;
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
    vertexDescriptor.layouts[0].stride = sizeof(float) * 4;
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    // Describe and create a render pipeline state
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = @"Fullscreen Quad Pipeline";
    pipelineStateDescriptor.vertexFunction = vertexProgram;
    pipelineStateDescriptor.fragmentFunction = fragmentProgram;
    pipelineStateDescriptor.vertexDescriptor = vertexDescriptor;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = self.view.colorPixelFormat;
    pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationSubtract;
    pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationSubtract;
    pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    _renderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_renderPipelineState)
    {
        NSLog(@"Failed to create render pipeline state, error %@", error);
    }
}

- (void)reshapeWithDrawableSize:(CGSize)drawableSize
{
    // Select a grid size that matches the size of the view in points
#if TARGET_OS_IOS || TARGET_OS_TV
    UIScreen* screen = self.view.window.screen ?: [UIScreen mainScreen];
    float scale = screen.nativeScale;
    
    self.view.layer.contentsScale = scale;
#else
    CGFloat scale = 1;
#endif

    MTLSize proposedGridSize = MTLSizeMake(drawableSize.width / scale, drawableSize.height / scale, 1);
    
    if (_gridSize.width != proposedGridSize.width || _gridSize.height != proposedGridSize.height) {
        _gridSize = proposedGridSize;

        [self initGameState];
        [self buildComputeResources];
    }
}

- (void)buildComputeResources
{
    [_textureQueue removeAllObjects];
    _currentGameStateTexture = nil;

    // Create a texture descriptor for the textures we will use to hold the
    // game grid. Each frame, the texture we previously used to draw becomes
    // the texture we use to update the simulation, so every texture is marked
    // as readable and writeable.
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Uint
                                                                                          width:_gridSize.width
                                                                                         height:_gridSize.height
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    
    for (NSUInteger i = 0; i < kTextureCount; ++i) {
        id<MTLTexture> texture = [_device newTextureWithDescriptor:descriptor];
        texture.label = [NSString stringWithFormat:@"Game State %d", (int)i];
        [_textureQueue addObject:texture];
    }
    
    // In order to make the simulation visually interesting, we need to seed it with
    // an initial game state that has some living and some dead cells. Here, we create
    // a temporary buffer that holds the initial, randomly-generated game state.
    uint8_t *randomGrid = (uint8_t *)malloc(_gridSize.width * _gridSize.height);
    memset(randomGrid, 0, _gridSize.width * _gridSize.height);
//    for (NSUInteger i = 0; i < _gridSize.width; ++i)
//    {
//        for (NSUInteger j = 0; j < _gridSize.height; ++j)
//        {
//            uint8_t alive = drand48() < kInitialAliveProbability ? kCellValueAlive : kCellValueDead;
//            randomGrid[j * _gridSize.width + i] = alive;
//        }
//    }
    
    // The texture that will be read from at the start of the simulation is the one
    // at the end of the queue we use to store textures, so we overwrite its
    // contents with the simulation seed data.
    id<MTLTexture> currentReadTexture = [_textureQueue lastObject];
    
    [currentReadTexture replaceRegion:MTLRegionMake2D(0, 0, _gridSize.width, _gridSize.height)
                          mipmapLevel:0
                            withBytes:randomGrid
                          bytesPerRow:_gridSize.width];
    
    free(randomGrid);
}

- (void)buildComputePipelines
{
    NSError *error = nil;
    
    _commandQueue = [_device newCommandQueue];
    
    // The main compute pipeline runs the game of life simulation each frame
    MTLComputePipelineDescriptor *descriptor = [MTLComputePipelineDescriptor new];
    descriptor.computeFunction = [_library newFunctionWithName:@"game_of_life"];
    descriptor.label = @"Living Flame";
    _simulationPipelineState = [_device newComputePipelineStateWithDescriptor:descriptor
                                                                      options:MTLPipelineOptionNone
                                                                   reflection:nil
                                                                        error:&error];
    
    if (!_simulationPipelineState)
    {
        NSLog(@"Error when compiling simulation pipeline state: %@", error);
    }

    // Create a sampler state we can use in the compute kernel to read the
    // game state texture, wrapping around the edges in each direction.
    MTLSamplerDescriptor *samplerDescriptor = [MTLSamplerDescriptor new];
    samplerDescriptor.sAddressMode = MTLSamplerAddressModeRepeat;
    samplerDescriptor.tAddressMode = MTLSamplerAddressModeRepeat;
    samplerDescriptor.minFilter = MTLSamplerMinMagFilterNearest;
    samplerDescriptor.magFilter = MTLSamplerMinMagFilterNearest;
    samplerDescriptor.normalizedCoordinates = YES;
    _samplerState = [_device newSamplerStateWithDescriptor:samplerDescriptor];
}

#pragma mark - Interactivity

- (void)activateRandomCellsInNeighborhoodOfCell:(CGPoint)cell
{
    // Here, we simply store the point that was touched/clicked. After the next
    // simulation step, we will activate some random neighbors in the vicinity
    // of the touch point(s).
    NSValue *value = [NSValue valueWithBytes:&cell objCType:@encode(CGPoint)];
    
    if(_persistentDraw && _pencilMode) {
        [_pencilPoints addObject:value];
    }
    else {
        if(_persistentDraw && !_pencilMode && !_drawingFlame) {
            _drawingFlame = YES;

            // remove redo flame history
            [_activationPoints removeObjectsInRange:NSMakeRange(_persistentPointCount,
                                                                _activationPoints.count - _persistentPointCount)];
        }
        
        [_activationPoints addObject:value];
    }
}

- (void)stopPointActivation {
    _pointActivationStopped = YES;
}

- (void)stopCurrentDrawing {
    if(!_persistentDraw) {
        _activationCellCount = 0;
        [_activationPoints removeAllObjects];
    }
    else {
        _persistentPointCount = _activationPoints.count;
    }

    _prevPencilPointCount = 0;
    [_pencilPoints removeAllObjects];

    _pointActivationStopped = NO;
}

- (void)shakeFlame {
    _shakeFlame = true;
    
    [_stopShakeTimer invalidate];
    
    _stopShakeTimer = [NSTimer scheduledTimerWithTimeInterval:kShakeDuration
                                                       target:self
                                                     selector:@selector(stopShaking)
                                                     userInfo:nil
                                                      repeats:NO];
}

- (void)stopShaking {
    _shakeFlame = false;
}

#pragma mark - Render and Compute Encoding

- (void)verifyActivationCellBufCapacity {
    NSAssert(_activationCellCount <= _activationCellCapacity, @"_activationCellCount %lu, _activationCellCapacity %lu", (unsigned long)_activationCellCount, (unsigned long)_activationCellCapacity);
    
    if(_activationCellCount == _activationCellCapacity) {
        NSUInteger newCapacity = _activationCellCapacity * 1.6;
        packed_uint2 *newBuf = (packed_uint2*)realloc(_activationCells, newCapacity * sizeof(packed_uint2));
        
        if(!newBuf) {
            NSLog(@"failed to reallocate _activationCells");
            abort();
        }
        
        _activationCellCapacity = newCapacity;
        _activationCells = newBuf;
    }
}

- (void)putActivationCellsAtX:(int)x0 y:(int)y0 {
    for(int yi = y0-1; yi <= y0+1; yi++) {
        for(int xi = x0-1; xi <= x0+1; xi++) {
            if(xi >= 0 && xi < _gridSize.width && yi >= 0 && yi < _gridSize.height) {
                _activationPointBufferData[yi * _gridSize.width + xi] = 255;//kCellValueAlive;
            }
        }
    }
}

- (void)encodeActivationPoints:(id<MTLComputeCommandEncoder>)commandEncoder texture:(id<MTLTexture>)writeTexture {
    if(_persistentDraw && _pencilMode) {
        [self drawPencilLine];
    }
    
    if(!_activationCells) {
        _activationCellCapacity = 4096;
        _activationCells = malloc(_activationCellCapacity * 4096);

        if(!_activationCells) {
            NSLog(@"failed to allocate _activationCells");
            abort();
        }
    }

    if ((!_persistentDraw || _drawingFlame) && (_activationPoints.count - _persistentPointCount > 0)) {
        [self verifyActivationCellBufCapacity];
        
        if(_activationPoints.count - _persistentPointCount == 1) {
            CGPoint point;
            [_activationPoints[_persistentPointCount] getValue:&point];
            
            _activationCells[_activationCellCount].x = point.x;
            _activationCells[_activationCellCount].y = point.y;
            
            _activationCellCount++;
            
            [self putActivationCellsAtX:point.x y:point.y];
        }
        else {
            CGPoint prevPoint;
            [_activationPoints[_persistentPointCount] getValue:&prevPoint];
            
            for(NSUInteger i = _persistentPointCount + 1; i < _activationPoints.count; i++) {
                CGPoint point;
                [_activationPoints[i] getValue:&point];
                
                int x0 = prevPoint.x;
                int y0 = prevPoint.y;
                int x1 = point.x;
                int y1 = point.y;
                
                int dx = abs(x1-x0), sx = x0 < x1 ? 1 : -1;
                int dy = abs(y1-y0), sy = y0 < y1 ? 1 : -1;
                int err = (dx > dy ? dx : -dy) / 2;
                
                for(;;) {
                    [self verifyActivationCellBufCapacity];
                    
                    _activationCells[_activationCellCount].x = x0;
                    _activationCells[_activationCellCount].y = y0;

                    _activationCellCount++;

                    [self putActivationCellsAtX:x0 y:y0];

                    if (x0==x1 && y0==y1) {
                        break;
                    }
                    
                    int e2 = err;
                    
                    if (e2 >-dx) {
                        err -= dy; x0 += sx;
                    }
                    if (e2 < dy) {
                        err += dx; y0 += sy;
                    }
                }

                prevPoint = point;
            }
        }
    }
    
    if(!_persistentDraw) {
        _activationCellCount = 0;

        if(_pointActivationStopped) {
            [_activationPoints removeAllObjects];
            _pointActivationStopped = NO;
        }
        else if(_activationPoints.count > 0) {
            [_activationPoints removeObjectsInRange:NSMakeRange(0, _activationPoints.count-1)];
        }
    }
    else {
        if(_pointActivationStopped) {
            if(!_pencilMode && _persistentPointCount != _activationPoints.count) {
                _persistentPointCount = _activationPoints.count;

                FlameLine *flameLine = [[FlameLine alloc] init];
                flameLine.persistentPointCount = _persistentPointCount;
                flameLine.activationCellCount = _activationCellCount;

                [self removeRedoHistory];
                
                [_flameHistory addObject:flameLine];
                [_combinedHistory addObject:[NSNumber numberWithBool:YES]];

                _flameHistoryPos++;
                _combinedHistoryPos++;

#if TARGET_OS_IOS || TARGET_OS_TV
                [_viewController enableUndo];
#endif
            }

            _pointActivationStopped = NO;
            _drawingFlame = NO;
        }
    }
}

- (void)removeRedoHistory {
    NSAssert(_pencilHistoryPos <= _pencilHistory.count,
             @"_pencilHistoryPos %lu, _pencilHistory.count %lu",
             (unsigned long)_pencilHistoryPos, (unsigned long)_pencilHistory.count);

    NSAssert(_combinedHistoryPos <= _combinedHistory.count,
             @"_combinedHistoryPos %lu, _combinedHistory.count %lu",
             (unsigned long)_combinedHistoryPos, (unsigned long)_combinedHistory.count);

    NSAssert(_flameHistoryPos <= _flameHistory.count,
             @"_flameHistoryPos %lu, _flameHistory.count %lu",
             (unsigned long)_flameHistoryPos, (unsigned long)_flameHistory.count);

    [_pencilHistory removeObjectsInRange:NSMakeRange(_pencilHistoryPos,
                                                     _pencilHistory.count - _pencilHistoryPos)];
    
    [_flameHistory removeObjectsInRange:NSMakeRange(_flameHistoryPos,
                                                    _flameHistory.count - _flameHistoryPos)];

    [_combinedHistory removeObjectsInRange:NSMakeRange(_combinedHistoryPos,
                                                       _combinedHistory.count - _combinedHistoryPos)];

#if TARGET_OS_IOS || TARGET_OS_TV
    [_viewController disableRedo];
#endif
}

- (void)encodeComputeWorkInBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    // The grid we read from to update the simulation is the one that was last displayed on the screen
    id<MTLTexture> readTexture = [self.textureQueue lastObject];
    // The grid we write the new game state to is the one at the head of the queue
    id<MTLTexture> writeTexture = [self.textureQueue firstObject];
    
    id<MTLBlitCommandEncoder> blitCommandEncoder = [commandBuffer blitCommandEncoder];
    
    [blitCommandEncoder fillBuffer:_sparkMapBuffers[1]
                             range:NSMakeRange(0, sizeof(ushort) * _gridSize.width * _gridSize.height)
                             value:0];
    
    [blitCommandEncoder endEncoding];
    
    // Create a compute command encoder with which we can ask the GPU to do compute work
    id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
    
    // For updating the game state, we divide our grid up into square threadgroups and
    // determine how many we need to dispatch in order to cover the entire grid
    MTLSize threadsPerThreadgroup = MTLSizeMake(16, 16, 1);
    MTLSize threadgroupCount = MTLSizeMake(ceil((float)_gridSize.width / threadsPerThreadgroup.width),
                                           ceil((float)_gridSize.height / threadsPerThreadgroup.height),
                                           1);
    
    int state = _gameFrame % 2;
    int nextState = (_gameFrame + 1) % 2;
    bool warp = ((_gameFrame + 1) % kWarpFrame == 0) ? true : false;
    
    _gameState[state].warp = warp;
    _gameState[state].seed = rand();
    _gameState[state].shake = _shakeFlame;
    _gameState[state].persistentDraw = _persistentDraw;
    
    // Configure the compute command encoder and dispatch the actual work
    [commandEncoder setComputePipelineState:self.simulationPipelineState];
    [commandEncoder setTexture:readTexture atIndex:0];
    [commandEncoder setTexture:writeTexture atIndex:1];
    [commandEncoder setBytes:&_gameState[state] length:sizeof(GameState) atIndex:0];
    [commandEncoder setBuffer:_warpMapBuffers[0] offset:0 atIndex:1];
    [commandEncoder setBuffer:_warpMapBuffers[1] offset:0 atIndex:2];
    [commandEncoder setBuffer:_coolMapBuffer offset:0 atIndex:3];
    [commandEncoder setBuffer:_sparkBuffer offset:0 atIndex:4];
    [commandEncoder setBuffer:_sparkMapBuffers[0] offset:0 atIndex:5];
    [commandEncoder setBuffer:_sparkMapBuffers[1] offset:0 atIndex:6];
    [commandEncoder setBuffer:_activationPointBuffer offset:0 atIndex:7];
    [commandEncoder setSamplerState:self.samplerState atIndex:0];
    [commandEncoder dispatchThreadgroups:threadgroupCount threadsPerThreadgroup:threadsPerThreadgroup];

    [self encodeActivationPoints:commandEncoder texture:writeTexture];
    
    [commandEncoder endEncoding];
    
    _gameFrame++;
    
    _gameState[nextState].ft = _gameState[state].ft + 0.010;
    _gameState[nextState].frame = _gameFrame;

    // Rotate the queue so the texture we just wrote can be in-flight for the next couple of frames
    self.currentGameStateTexture = [self.textureQueue firstObject];
    [self.textureQueue removeObjectAtIndex:0];
    [self.textureQueue addObject:self.currentGameStateTexture];

    if(warp) {
        id<MTLBuffer> firstBuffer = _warpMapBuffers[0];
        [_warpMapBuffers removeObjectAtIndex:0];
        [_warpMapBuffers addObject:firstBuffer];
    }

    id<MTLBuffer> firstBuffer = _sparkMapBuffers[0];
    [_sparkMapBuffers removeObjectAtIndex:0];
    [_sparkMapBuffers addObject:firstBuffer];
}

- (void)encodeRenderWorkInBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    MTLRenderPassDescriptor *renderPassDescriptor = self.view.currentRenderPassDescriptor;
    
    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder, which we can use to encode draw calls into the buffer
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
        // Configure the render encoder for drawing the full-screen quad, then issue the draw call
        NSAssert(self.renderPipelineState, @"render pipeline state not initialized");
        [renderEncoder setRenderPipelineState:self.renderPipelineState];
        [renderEncoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:0];
        [renderEncoder setFragmentTexture:self.currentGameStateTexture atIndex:0];
        [renderEncoder setFragmentBuffer:_colorMapBuffer offset:0 atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        
        [renderEncoder endEncoding];
        
        // Present the texture we just rendered on the screen
        [commandBuffer presentDrawable:self.view.currentDrawable];
    }
}

#pragma mark - MTKView Delegate Methods

// Called whenever view changes orientation or layout is changed
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
#if TARGET_OS_IOS || TARGET_OS_TV
    if(_alert != nil) {
        [_alert dismissViewControllerAnimated:YES completion:nil];
        _alert = nil;
    }
#endif
    
    [self stopCurrentDrawing];
    
    // Since we need to restart the simulation when the drawable size changes,
    // coalesce rapid changes (such as during window resize) into less frequent
    // updates to avoid re-creating expensive resources too often.
    static const NSTimeInterval resizeHysteresis = 0.200;
    self.nextResizeTimestamp = [NSDate dateWithTimeIntervalSinceNow:resizeHysteresis];
    dispatch_after(dispatch_time(0, resizeHysteresis * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([self.nextResizeTimestamp timeIntervalSinceNow] <= 0) {
#if TARGET_OS_IOS || TARGET_OS_TV
            UIScreen* screen = self.view.window.screen ?: [UIScreen mainScreen];
            if(self.view.bounds.size.height != screen.bounds.size.height) {
                NSLog(@"self.view.bounds.size.height: %g, screen.bounds.size.height %g", self.view.bounds.size.height, screen.bounds.size.height);
                self.view.frame = CGRectMake(0, self.view.bounds.size.height - screen.bounds.size.height, screen.bounds.size.width, screen.bounds.size.height);
                
                NSLog(@"Restarting simulation after window was resized...");
                [self reshapeWithDrawableSize:self.view.drawableSize];
            }
#endif
        }
    });
}

// Called whenever the view needs to render
- (void)drawInMTKView:(nonnull MTKView *)view
{
    dispatch_semaphore_wait(self.inflightSemaphore, DISPATCH_TIME_FOREVER);

#if 0
    static int frame = 0;
    WarpOffset *buf = _warpMapBuffers[1].contents;
    unsigned long start_x = 0, end_x = _gridSize.width / kWarpBlockSize;
    unsigned long start_y = 0, end_y = _gridSize.height / kWarpBlockSize;
    printf("Frame %d\n", frame++);
    for(unsigned long off = 0, y = start_y; y <= end_y; y++) {
        for(unsigned long x = start_x; x <= end_x; x++, off++) {
            WarpOffset o = buf[(_gridSize.width/kWarpBlockSize + 1) * y + x];
            printf("x %lu -> %.03f, y %lu -> %.03f, xv %.03f, yv %.03f\n", x*kWarpBlockSize, o.x, y*kWarpBlockSize, o.y, o.xv, o.yv);
        }
    }
#endif

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    
    __block dispatch_semaphore_t blockSemaphore = self.inflightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(blockSemaphore);
    }];
    
    [self encodeComputeWorkInBuffer:commandBuffer];
    
    [self encodeRenderWorkInBuffer:commandBuffer];

    [commandBuffer commit];
}

@end
