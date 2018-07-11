#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "common.h"
#include "VertexBuffer.h"
#import <GLKit/GLKMath.h>

constexpr int W = 800;
constexpr int H = 800;
constexpr int R = 50;
constexpr int C = 1000;

@interface HelloMetalRenderer : NSObject
- (id)initWithLayer:(CAMetalLayer *)layer;
- (void)setup:(CAMetalLayer *)layer;
@end


@interface MyView : NSView
- (CALayer *)makeBackingLayer;
@end
static const float GlobalQuadVertices[6][4] =
        {
                { -1.0f,  -1.0f, 0.0f, 1.0f },
                {  1.0f,  -1.0f, 0.0f, 1.0f },
                { -1.0f,   1.0f, 0.0f, 1.0f },

                {  1.0f,  -1.0f, 0.0f, 1.0f },
                { -1.0f,   1.0f, 0.0f, 1.0f },
                {  1.0f,   1.0f, 0.0f, 1.0f }
        };
static const float GlobalQuadTexCoords[6][2] =
        {
                { 0.0f, 0.0f },
                { 1.0f, 0.0f },
                { 0.0f, 1.0f },

                { 1.0f, 0.0f },
                { 0.0f, 1.0f },
                { 1.0f, 1.0f }
        };

@interface OSXMetalView : NSView
@end

@implementation OSXMetalView
{
@public
    CVDisplayLinkRef	  	    _displayLink;
    dispatch_semaphore_t 	    _renderSemaphore;

    CAMetalLayer 	   *_metalLayer;

    MTLRenderPassDescriptor    *_renderPassDesc;
    id<MTLDevice> 			    _device;
    id<MTLCommandQueue>        _commandQueue;
    id<MTLLibrary>             _shaderLibrary;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLDepthStencilState>   _depthState;
    id<MTLTexture>  	       _texture;
    id<MTLBuffer>  			   _vertexBuffer;
    id<MTLBuffer>  			   _texCoordBuffer;
    id<CAMetalDrawable> 	   _currentDrawable;

    BOOL 				        _layerSizeDidUpdate;
    char 					   *_pixels;
}

static CVReturn OnDisplayLinkFrame(CVDisplayLinkRef displayLink,
                                   const CVTimeStamp *now,
                                   const CVTimeStamp *outputTime,
                                   CVOptionFlags flagsIn,
                                   CVOptionFlags *flagsOut,
                                   void *displayLinkContext)
{
    OSXMetalView *view = (__bridge OSXMetalView *)displayLinkContext;

    @autoreleasepool
    {
        [view update];
    }

    return kCVReturnSuccess;
}

+ (Class)layerClass
{
    return [CAMetalLayer class];
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];

    if (self)
    {
        self.wantsLayer = YES;
        self.layer = _metalLayer = [CAMetalLayer layer];

        _device = MTLCreateSystemDefaultDevice();

        _metalLayer.device          = _device;
        _metalLayer.pixelFormat     = MTLPixelFormatBGRA8Unorm;

        _metalLayer.framebufferOnly = YES;

        _commandQueue = [_device newCommandQueue];
        if (!_commandQueue)
        {
            printf("ERROR: Couldn't create a command queue.");
            return nil;
        }

        NSError *error = nil;

        _shaderLibrary = [_device newLibraryWithFile: @"shaders.metallib" error:&error];
        if (!_shaderLibrary)
        {
            printf("ERROR: Failed to load shader library.");
            return nil;
        }

        id<MTLFunction> fragmentProgram = [_shaderLibrary newFunctionWithName:@"frag"];
        if (!fragmentProgram)
        {
            printf("ERROR: Couldn't load fragment function from default library.");
            return nil;
        }

        id<MTLFunction> vertexProgram = [_shaderLibrary newFunctionWithName:@"vert"];
        if (!vertexProgram)
        {
            printf("ERROR: Couldn't load vertex function from default library.");
            return nil;
        }

        MTLRenderPipelineDescriptor *pipelineStateDesc = [MTLRenderPipelineDescriptor new];

        if (!pipelineStateDesc)
        {
            printf("ERROR: Failed creating a pipeline state descriptor!");
            return nil;
        }

        pipelineStateDesc.depthAttachmentPixelFormat      = MTLPixelFormatInvalid;
        pipelineStateDesc.stencilAttachmentPixelFormat    = MTLPixelFormatInvalid;
        pipelineStateDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

        pipelineStateDesc.sampleCount      = 1;
        pipelineStateDesc.vertexFunction   = vertexProgram;
        pipelineStateDesc.fragmentFunction = fragmentProgram;

        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDesc
                                                                 error:&error];
        if (!_pipelineState)
        {
            printf("ERROR: Failed acquiring pipeline state descriptor.");
            return nil;
        }

        MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                           width:frame.size.width
                                                                                          height:frame.size.height
                                                                                       mipmapped:NO];
        if (!texDesc)
        {
            printf("ERROR: Failed to create texture descriptor.");
            return nil;
        }

        _texture = [_device newTextureWithDescriptor:texDesc];

        if (!_texture)
        {
            printf("ERROR: Failed to create texture.");
            return nil;
        }

        _vertexBuffer = [_device newBufferWithBytes:GlobalQuadVertices
                                             length:6 * sizeof(float) * 4
                                            options:MTLResourceOptionCPUCacheModeDefault];
        if (!_vertexBuffer)
        {
            printf("ERROR: Failed to create quad vertex buffer.");
            return nil;
        }
        _vertexBuffer.label = @"quad vertices";

        _texCoordBuffer = [_device newBufferWithBytes:GlobalQuadTexCoords
                                               length:6 * sizeof(float) * 2
                                              options:MTLResourceOptionCPUCacheModeDefault];
        if (!_texCoordBuffer)
        {
            printf("ERROR: Failed to create 2d texture coordinate buffer.");
            return nil;
        }
        _texCoordBuffer.label = @"quad texcoords";

        _pixels = (char*)malloc(4 * frame.size.width * frame.size.height);
        char *pixelIterator = _pixels;

        for (int y = 0; y < frame.size.height; ++y)
        {
            for (int x = 0; x < frame.size.width; ++x)
            {
                *pixelIterator++ = 255;
                *pixelIterator++ = 0;
                *pixelIterator++ = 255;
                *pixelIterator++ = 255;
            }
        }

        _renderSemaphore = dispatch_semaphore_create(2);

        CVReturn cvReturn = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);

   //     Assert(cvReturn == kCVReturnSuccess);

        cvReturn = CVDisplayLinkSetOutputCallback(_displayLink, &OnDisplayLinkFrame, (__bridge void *)self);

   //     Assert(cvReturn == kCVReturnSuccess);

        cvReturn = CVDisplayLinkSetCurrentCGDisplay(_displayLink, CGMainDisplayID());

        CVDisplayLinkStart(_displayLink);

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

        [notificationCenter addObserver:self
                               selector:@selector(windowWillClose:)
                                   name:NSWindowWillCloseNotification
                                 object:self.window];
    }

    return self;
}

- (void)dealloc
{
    if (_displayLink)
    {
        [self stopUpdate];
    }
}

- (void)windowWillClose:(NSNotification*)notification
{
    // Stop the display link when the window is closing because we will
    // not be able to get a drawable, but the display link may continue
    // to fire
    if (notification.object == self.window)
    {
        CVDisplayLinkStop(_displayLink);
    }
}

- (void)update
{
    if (_layerSizeDidUpdate)
    {
        // Set the metal layer to the drawable size in case orientation or size changes.
        CGSize drawableSize = self.bounds.size;

        // Scale drawableSize so that drawable is 1:1 width pixels not 1:1 to points.
        NSScreen* screen = self.window.screen ?: [NSScreen mainScreen];
        drawableSize.width *= screen.backingScaleFactor;
        drawableSize.height *= screen.backingScaleFactor;

        _metalLayer.drawableSize = drawableSize;

        _layerSizeDidUpdate = NO;
    }

    dispatch_semaphore_wait(_renderSemaphore, DISPATCH_TIME_FOREVER);

    if (!_currentDrawable)
    {
        _currentDrawable = [_metalLayer nextDrawable];
    }

    if (!_currentDrawable)
    {
        printf("ERROR: Failed to get a valid drawable.");
        _renderPassDesc = nil;
    }
    else
    {
        if (_renderPassDesc == nil)
        {
            _renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
        }

        MTLRenderPassColorAttachmentDescriptor *colorAttachment = _renderPassDesc.colorAttachments[0];
        colorAttachment.texture = _currentDrawable.texture;

        colorAttachment.loadAction = MTLLoadActionClear;
        colorAttachment.clearColor = MTLClearColorMake(1.0f, 0.0f, 1.0f, 1.0f);

        colorAttachment.storeAction = MTLStoreActionStore;
    }

    MTLRegion region = MTLRegionMake2D(0, 0, self.frame.size.width, self.frame.size.height);
    int rowBytes = self.frame.size.width * 4;
    [_texture replaceRegion:region
                mipmapLevel:0
                  withBytes:_pixels
                bytesPerRow:rowBytes];

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    if (_renderPassDesc)
    {
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_renderPassDesc];

        [renderEncoder pushDebugGroup:@"encode quad"];

        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setVertexBuffer:_vertexBuffer
                                offset:0
                               atIndex:0];
        [renderEncoder setVertexBuffer:_texCoordBuffer
                                offset:0
                               atIndex:1];
        [renderEncoder setFragmentTexture:_texture
                                  atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6
                        instanceCount:1];
        [renderEncoder endEncoding];

        [renderEncoder popDebugGroup];

        [commandBuffer presentDrawable:_currentDrawable];
    }

    __block dispatch_semaphore_t blockRenderSemaphore = _renderSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> cmdBuff){
        dispatch_semaphore_signal(blockRenderSemaphore);
    }];

    [commandBuffer commit];

    _currentDrawable = nil;
}

- (void)stopUpdate
{
    if (_displayLink)
    {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
    }
}

@end

constexpr int uniformBufferCount = 3;
constexpr int N = 32;

struct Object {
    Vertex* verts;
    int s;
    int n;
    float ox, oy;
    float vx, vy;
    unsigned char c1[4];
    unsigned char c2[4];
};

typedef struct {
    GLKVector2 position;
}Triangle;

Object objs[C];
VertexBuffer* vertexBuffer;
HelloMetalRenderer* renderer;
int main () {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        NSRect frame = NSMakeRect(0, 0, W, H);
        NSWindow* window = [[NSWindow alloc]
                               initWithContentRect:frame styleMask:NSTitledWindowMask
                               backing:NSBackingStoreBuffered defer:NO];
        [window cascadeTopLeftFromPoint:NSMakePoint(20,20)];
        window.title = [[NSProcessInfo processInfo] processName];
        // Custom MTKView.
        NSView* view = [[MyView alloc] initWithFrame:frame];
        window.contentView = view;


        //CAMetalLayer *rootLayer = [[CAMetalLayer alloc] init];
        renderer = [[HelloMetalRenderer alloc] initWithLayer:nil andView:view];


        view.needsDisplay = YES;
        //[self draw];

        [window makeKeyAndOrderFront:nil];

        [NSApp activateIgnoringOtherApps:YES];
        // Run.
        [NSApp run];
    }
    return 0;
}

// The main view.
@implementation HelloMetalRenderer {
    id <MTLDevice> mtlDevice;
    id <MTLCommandQueue> mtlCommandQueue;
    MTLRenderPassDescriptor *mtlRenderPassDescriptor;
    CAMetalLayer *metalLayer;
    id <CAMetalDrawable> frameDrawable;
    NSView* _view;
    NSTimer* timer;
    MTLRenderPipelineDescriptor *renderPipelineDescriptor;
    id <MTLRenderPipelineState> renderPipelineState;
    id <MTLBuffer> object;
    dispatch_semaphore_t _semaphore;
    CVDisplayLinkRef displayLink;
}

- (id)initWithLayer:(CAMetalLayer *)layer andView:(NSView*)view{
    _view = view;
    self = [super init];
    if (self) {
        [self setup:layer andView:view];
    }
    return self;
}

- (void)setup:(CAMetalLayer *)layer andView:(NSView*)view {
    // Set view settings.
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
    metalLayer  = view.layer;
    mtlDevice = MTLCreateSystemDefaultDevice();
    mtlCommandQueue = [mtlDevice newCommandQueue];

    [metalLayer setDevice:mtlDevice];
    [metalLayer setPixelFormat:MTLPixelFormatBGRA8Unorm];
    metalLayer.framebufferOnly = YES;
    [metalLayer setFrame:_view.layer.frame];

    [_view.layer addSublayer:metalLayer];

    [_view setOpaque:YES];
    [_view setBackgroundColor:nil];
    [_view setWantsLayer:YES];

    // Load shaders.
    NSError *error = nil;
    id <MTLLibrary> _library = [mtlDevice newLibraryWithFile: @"shaders.metallib" error:&error];
    if (!_library) {
        NSLog(@"Failed to load library. error %@", error);
        exit(0);
    }

    // Create depth state.
    MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;


    // Create a reusable pipeline
    renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    renderPipelineDescriptor.vertexFunction = [_library newFunctionWithName:@"vert"];
    renderPipelineDescriptor.fragmentFunction = [_library newFunctionWithName:@"frag"];
    renderPipelineState = [mtlDevice newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error: nil];

    Triangle triangle[3] = { { -.5f, 0.0f }, { 0.5f, 0.0f }, { 0.0f, 0.5f } };

    object = [mtlDevice newBufferWithBytes:&triangle length:sizeof(Triangle[3]) options:MTLResourceOptionCPUCacheModeDefault];
    // Create vertex descriptor.
    MTLVertexDescriptor *vertDesc = [MTLVertexDescriptor new];
    vertDesc.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
    vertDesc.attributes[VertexAttributePosition].offset = 0;
    vertDesc.attributes[VertexAttributePosition].bufferIndex = MeshVertexBuffer;
    vertDesc.attributes[VertexAttributeColor].format = MTLVertexFormatUChar4;
    vertDesc.attributes[VertexAttributeColor].offset = sizeof(Vertex::position);
    vertDesc.attributes[VertexAttributeColor].bufferIndex = MeshVertexBuffer;
    vertDesc.layouts[MeshVertexBuffer].stride = sizeof(Vertex);
    vertDesc.layouts[MeshVertexBuffer].stepRate = 1;
    vertDesc.layouts[MeshVertexBuffer].stepFunction = MTLVertexStepFunctionPerVertex;
    CVDisplayLinkSetOutputCallback(displayLink, &MyDisplayLinkCallback, self);
    _semaphore = dispatch_semaphore_create(uniformBufferCount);

/*    timer = [NSTimer scheduledTimerWithTimeInterval:1
                                             target:self
                                           selector:@selector(render)
                                           userInfo:nil
                                            repeats:YES];
*/
    CVDisplayLinkStart(displayLink);
}

-(void) render {
    NSLog(@"aaaa\n");
    @autoreleasepool {
        dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);

        id <MTLCommandBuffer> mtlCommandBuffer = [mtlCommandQueue commandBuffer];

        if (frameDrawable = [metalLayer nextDrawable]) {
            if (!mtlRenderPassDescriptor)
                mtlRenderPassDescriptor = [MTLRenderPassDescriptor new];

            mtlRenderPassDescriptor.colorAttachments[0].texture = frameDrawable.texture;
            mtlRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
            mtlRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.75, 0.25, 1.0, 1.0);
            mtlRenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

            id <MTLRenderCommandEncoder> renderCommand = [mtlCommandBuffer renderCommandEncoderWithDescriptor:mtlRenderPassDescriptor];
            // Draw objects here
            // set MTLRenderPipelineState..
            [renderCommand endEncoding];
            __block dispatch_semaphore_t semaphore = _semaphore;
            [mtlCommandBuffer addCompletedHandler:^(id <MTLCommandBuffer> buffer) {
                dispatch_semaphore_signal(semaphore);
            }];
            [mtlCommandBuffer presentDrawable:frameDrawable];
            [mtlCommandBuffer commit];
            mtlRenderPassDescriptor = nil;
            frameDrawable = nil;
        }
    }
}

// This is the renderer output callback function
static CVReturn MyDisplayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp* now, const CVTimeStamp* outputTime, CVOptionFlags flagsIn, CVOptionFlags* flagsOut, void* displayLinkContext)
{
    [(HelloMetalRenderer*)displayLinkContext render];
    return kCVReturnSuccess;
}


@end

@implementation MyView {

}

- (CALayer *)makeBackingLayer {
    return [CAMetalLayer layer];
}
@end