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
constexpr int N = 32;

static VertexBuffer* vertexBuffer;

struct Object {
    Vertex* verts;
    int s;
    int n;
    float ox, oy;
    float vx, vy;
    unsigned char c1[4];
    unsigned char c2[4];
};

Object objs[C];




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
    id<MTLBuffer>  			   _vertexBuffer;
    id<CAMetalDrawable> 	   _currentDrawable;
    id <MTLBuffer> _uniformBuffer;
    id<MTLTexture> _earthTxt;
    id<MTLTexture> _moonTxt;
    id<MTLDepthStencilState> _depthState;
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

   // @autoreleasepool
   // {
        [view update];
  //  }

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

        id<MTLFunction> fragmentProgram = [_shaderLibrary newFunctionWithName:@"frag_txt"];
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
        _uniformBuffer = [_device newBufferWithLength:sizeof(FrameUniforms)
                                 options:MTLResourceCPUCacheModeWriteCombined];
        // Create vertex descriptor.

        NSDictionary *opt = [NSDictionary dictionaryWithObject:@(YES) forKey:MTKTextureLoaderOptionOrigin];

        MTKTextureLoader* txtLoader = [[MTKTextureLoader alloc] initWithDevice:_device];
        NSError *err;
        _earthTxt = [txtLoader newTextureWithContentsOfURL: [NSURL fileURLWithPath:@"earth.png"] options: opt error:&err];
        _moonTxt = [txtLoader newTextureWithContentsOfURL: [NSURL fileURLWithPath:@"moon.png"] options: opt error:&err];

        MTLDepthStencilDescriptor *depthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
        depthDescriptor.depthWriteEnabled = YES;
        depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
        _depthState = [_device newDepthStencilStateWithDescriptor:depthDescriptor];

//        MTLTextureDescriptor *TextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatRGBA8Unorm width: 2 height: 2 mipmapped: NO];
//        _texture = [_device newTextureWithDescriptor: TextureDescriptor];
//        [_texture replaceRegion: MTLRegionMake2D(0, 0, 2, 2) mipmapLevel: 0 withBytes: (uint8_t[]){
//                255,0,0,255,    0,255,0,255,
//                0,0,255,255,    0,0,0,255
//        } bytesPerRow: 8];

        MTLVertexDescriptor *vertDesc = [MTLVertexDescriptor new];
        vertDesc.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
        vertDesc.attributes[VertexAttributePosition].offset = 0;
        vertDesc.attributes[VertexAttributePosition].bufferIndex = MeshVertexBuffer;
        vertDesc.attributes[VertexAttributeColor].format = MTLVertexFormatUChar4;
        vertDesc.attributes[VertexAttributeColor].offset = sizeof(Vertex::position);
        vertDesc.attributes[VertexAttributeColor].bufferIndex = MeshVertexBuffer;
        vertDesc.attributes[VertexAttributeTexPos].format = MTLVertexFormatFloat2;
        vertDesc.attributes[VertexAttributeTexPos].offset = sizeof(Vertex::position) + sizeof(Vertex::color);
        vertDesc.attributes[VertexAttributeTexPos].bufferIndex = MeshVertexBuffer;

        vertDesc.layouts[MeshVertexBuffer].stride = sizeof(Vertex);
        vertDesc.layouts[MeshVertexBuffer].stepRate = 1;
        vertDesc.layouts[MeshVertexBuffer].stepFunction = MTLVertexStepFunctionPerVertex;

        pipelineStateDesc.depthAttachmentPixelFormat      = MTLPixelFormatDepth32Float;
       // pipelineStateDesc.stencilAttachmentPixelFormat    = MTLPixelFormatInvalid;
        pipelineStateDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

        pipelineStateDesc.sampleCount      = 1;
        pipelineStateDesc.vertexFunction   = vertexProgram;
        pipelineStateDesc.fragmentFunction = fragmentProgram;
        pipelineStateDesc.vertexDescriptor = vertDesc;
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDesc
                                                                 error:&error];
        if (!_pipelineState)
        {
            printf("ERROR: Failed acquiring pipeline state descriptor.");
            return nil;
        }

        srand (time(NULL));
        // Create vertices.

        vertexBuffer = new VertexBuffer(N*3*C);
        vertexBuffer->allocate(N*3*C);
        for (int j = 0; j < C; j++) {
            objs[j].s = j*N*3;
            objs[j].n = N*3;
            objs[j].verts = vertexBuffer->getBuffer();
            objs[j].c1[0] = rand()%256;
            objs[j].c1[1] = rand()%256;
            objs[j].c1[2] = rand()%256;
            objs[j].c1[3] = rand()%256;

            objs[j].c2[0] = rand()%256;
            objs[j].c2[1] = rand()%256;
            objs[j].c2[2] = rand()%256;
            objs[j].c2[3] = rand()%256;
            for (int i = 0; i < N; i++) {
                objs[j].verts[objs[j].s + i * 3].position[0] =
                        std::cos(i * (2.0 * M_PI) / N) * ((float) R / W);
                objs[j].verts[objs[j].s + i * 3].position[1] =
                        std::sin(i * (2.0 * M_PI) / N) * ((float) R / H);
                objs[j].verts[objs[j].s + i * 3].position[2] = 0;
                objs[j].verts[objs[j].s + i * 3].texpos[0] =
                        (std::cos(i * (2.0 * M_PI) / N) + 1.2f)* 0.4f;
                objs[j].verts[objs[j].s + i * 3].texpos[1] =
                        (std::sin(i * (2.0 * M_PI) / N) + 1.2f) * 0.4f;

                objs[j].verts[objs[j].s + i * 3 + 1].position[0] =
                        std::cos((i + 1) * (2.0 * M_PI) / N) * ((float) R / W);
                objs[j].verts[objs[j].s + i * 3 + 1].position[1] =
                        std::sin((i + 1) * (2.0 * M_PI) / N) * ((float) R / H);
                objs[j].verts[objs[j].s + i * 3 + 1].texpos[0] =
                        (std::cos((i + 1) * (2.0 * M_PI) / N)+ 1.2f)*0.4f;
                objs[j].verts[objs[j].s + i * 3 + 1].texpos[1] =
                        (std::sin((i + 1) * (2.0 * M_PI) / N)+ 1.2f)*0.4f;

                objs[j].verts[objs[j].s + i * 3 + 1].position[2] = 0;

                objs[j].verts[objs[j].s + i * 3 + 2].position[0] = 0;
                objs[j].verts[objs[j].s + i * 3 + 2].position[1] = 0;

                objs[j].verts[objs[j].s + i * 3 + 2].texpos[0] = 0.5f;
                objs[j].verts[objs[j].s + i * 3 + 2].texpos[1] = 0.5f;

                objs[j].verts[objs[j].s + i * 3 + 2].position[2] = 0;

                objs[j].verts[objs[j].s + i * 3].color[0] = objs[j].c1[0];
                objs[j].verts[objs[j].s + i * 3].color[1] = objs[j].c1[1];
                objs[j].verts[objs[j].s + i * 3].color[2] = objs[j].c1[2];
                objs[j].verts[objs[j].s + i * 3].color[3] = objs[j].c1[3];
                objs[j].verts[objs[j].s + i * 3 + 1].color[0] = objs[j].c1[0];
                objs[j].verts[objs[j].s + i * 3 + 1].color[1] = objs[j].c1[1];
                objs[j].verts[objs[j].s + i * 3 + 1].color[2] = objs[j].c1[2];
                objs[j].verts[objs[j].s + i * 3 + 1].color[3] = objs[j].c1[3];
                objs[j].verts[objs[j].s + i * 3 + 2].color[0] = objs[j].c2[0];
                objs[j].verts[objs[j].s + i * 3 + 2].color[1] = objs[j].c2[1];
                objs[j].verts[objs[j].s + i * 3 + 2].color[2] = objs[j].c2[2];
                objs[j].verts[objs[j].s + i * 3 + 2].color[3] = objs[j].c2[3];
            }
            objs[j].ox = rand()%(2*W-2*R) - W + R;
            objs[j].oy = rand()%(2*H-2*R) - H + R;
            objs[j].vx = rand()%20 - 10;
            objs[j].vy = rand()%20 - 10;
        }
        _vertexBuffer = [_device newBufferWithBytes:vertexBuffer->getBuffer()
                                                 length:vertexBuffer->getSize()*sizeof(Vertex)
                                                options:
                                                        MTLResourceCPUCacheModeDefaultCache];

        if (!_vertexBuffer)
        {
            printf("ERROR: Failed to create quad vertex buffer.");
            return nil;
        }
        _vertexBuffer.label = @"quad vertices";


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
        colorAttachment.clearColor = MTLClearColorMake(0.0f, 0.0f, 0.0f, 1.0f);

        colorAttachment.storeAction = MTLStoreActionStore;
    }

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    if (_renderPassDesc) {
        simd::float4x4 rot(simd::float4{1, 0, 0, 0},
                           simd::float4{0, 1, 0, 0},
                           simd::float4{0, 0, 1, 0},
                           simd::float4{0, 0, 0, 1});

        for (int j = 0; j < C; j++) {
            if (objs[j].ox + objs[j].vx > W - R || objs[j].ox + objs[j].vx < R - W)
                objs[j].vx = -objs[j].vx;

            if (objs[j].oy + objs[j].vy > H - R || objs[j].oy + objs[j].vy < R - H)
                objs[j].vy = -objs[j].vy;

            objs[j].ox += objs[j].vx;
            objs[j].oy += objs[j].vy;

            Vertex *v = static_cast<Vertex *>([_vertexBuffer contents]);
            for (int i = 0; i < N; i++) {
                v[i * 3 + objs[j].s].position[0] =
                        std::cos(i * (2.0 * M_PI) / N) * ((float) R / W) + objs[j].ox / W;
                v[i * 3 + objs[j].s].position[1] =
                        std::sin(i * (2.0 * M_PI) / N) * ((float) R / H) + objs[j].oy / H;
                v[i * 3 + objs[j].s].position[2] = j % 2;;
                v[i * 3 + 1 + objs[j].s].position[0] =
                        std::cos((i + 1) * (2.0 * M_PI) / N) * ((float) R / W) +
                        objs[j].ox / W;
                v[i * 3 + 1 + objs[j].s].position[1] =
                        std::sin((i + 1) * (2.0 * M_PI) / N) * ((float) R / H) +
                        objs[j].oy / H;
                v[i * 3 + 1 + objs[j].s].position[2] = j % 2;
                v[i * 3 + 2 + objs[j].s].position[0] = 0 + objs[j].ox / W;
                v[i * 3 + 2 + objs[j].s].position[1] = 0 + objs[j].oy / H;
                v[i * 3 + 2 + objs[j].s].position[2] = j % 2;

                v[i * 3 + objs[j].s].color[0] = objs[j].c1[0];;
                v[i * 3 + objs[j].s].color[1] = objs[j].c1[1];;
                v[i * 3 + objs[j].s].color[2] = objs[j].c1[2];;
                v[i * 3 + objs[j].s].color[3] = objs[j].c1[3];;
                v[i * 3 + 1 + objs[j].s].color[0] = objs[j].c1[0];;
                v[i * 3 + 1 + objs[j].s].color[1] = objs[j].c1[1];;
                v[i * 3 + 1 + objs[j].s].color[2] = objs[j].c1[2];;
                v[i * 3 + 1 + objs[j].s].color[3] = objs[j].c1[3];;
                v[i * 3 + 2 + objs[j].s].color[0] = objs[j].c2[0];;
                v[i * 3 + 2 + objs[j].s].color[1] = objs[j].c2[1];;
                v[i * 3 + 2 + objs[j].s].color[2] = objs[j].c2[2];;
                v[i * 3 + 2 + objs[j].s].color[3] = objs[j].c2[3];;
            }
        }
        [_vertexBuffer didModifyRange:NSMakeRange(0, sizeof(Vertex) * N * 3 * C)];

        FrameUniforms *uniforms = (FrameUniforms *) [_uniformBuffer contents];
        uniforms->projectionViewModel = rot;

        // Create a command buffer.

        // Encode render command.
        id <MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:_renderPassDesc];
        [encoder pushDebugGroup:@"encode balls"];
        [encoder setDepthStencilState:_depthState];
        [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [encoder setRenderPipelineState:_pipelineState];
        [encoder setVertexBuffer:_vertexBuffer
                          offset:0
                         atIndex:MeshVertexBuffer];
        [encoder setVertexBuffer:_uniformBuffer
                          offset:0 atIndex:FrameUniformBuffer];
        // [encoder setViewport:{0, 0, 800, 600, 0, 1}];

        [encoder setFragmentTexture: _earthTxt atIndex: 0];

        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:(N * 3 * C / 2)];
//        [encoder endEncoding];

  //      [encoder popDebugGroup];

    //    encoder = [commandBuffer renderCommandEncoderWithDescriptor:_renderPassDesc];
      //  [encoder pushDebugGroup:@"encode balls"];
        [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [encoder setRenderPipelineState:_pipelineState];
        [encoder setVertexBuffer:_vertexBuffer
                          offset:0
                         atIndex:MeshVertexBuffer];
        [encoder setVertexBuffer:_uniformBuffer
                          offset:0 atIndex:FrameUniformBuffer];
        // [encoder setViewport:{0, 0, 800, 600, 0, 1}];

        [encoder setFragmentTexture: _moonTxt atIndex: 0];

        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:(N * 3 * C / 2) vertexCount:(N * 3 * C / 2)];
        [encoder endEncoding];

        [encoder popDebugGroup];

        __block dispatch_semaphore_t blockRenderSemaphore = _renderSemaphore;
        [commandBuffer addCompletedHandler:^(id <MTLCommandBuffer> cmdBuff) {
            dispatch_semaphore_signal(blockRenderSemaphore);
        }];
        [commandBuffer presentDrawable:_currentDrawable];
        [commandBuffer commit];
    }
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
        OSXMetalView* view = [[OSXMetalView alloc] initWithFrame:frame];
        window.contentView = view;
        view.needsDisplay = YES;

        [window makeKeyAndOrderFront:nil];

        [NSApp activateIgnoringOtherApps:YES];
        // Run.
        [NSApp run];
    }
    return 0;
}
