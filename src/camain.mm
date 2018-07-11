#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "common.h"
#include "VertexBuffer.h"

constexpr int W = 800;
constexpr int H = 800;
constexpr int R = 50;
constexpr int C = 1000;

@interface HelloMetalRenderer : NSObject
- (id)initWithLayer:(CAMetalLayer *)layer;
- (void)setup:(CAMetalLayer *)layer;
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
        NSView* view = [[NSView alloc] initWithFrame:frame];
        window.contentView = view;


        CAMetalLayer *rootLayer = [[CAMetalLayer alloc] init];
        renderer = [[HelloMetalRenderer alloc] initWithLayer:rootLayer andView:view];


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
    CAMetalLayer *rootLayer;
    NSView* _view;

    id <MTLLibrary> _library;
    id <MTLCommandQueue> _commandQueue;
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLDepthStencilState> _depthState;
    dispatch_semaphore_t _semaphore;
    id <MTLBuffer> _uniformBuffers[uniformBufferCount];
    id <MTLBuffer> _vertexBuffer;
    MTLRenderPipelineDescriptor *pipelineDesc;
    int uniformBufferIndex;
    long frame;
    NSTimer* timer;
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
    rootLayer = layer;

    rootLayer.device = MTLCreateSystemDefaultDevice();
    rootLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;

    rootLayer.framebufferOnly = true;
    rootLayer.frame = view.layer.frame;
    rootLayer.backgroundColor = [[NSColor whiteColor] CGColor];
    rootLayer.bounds = [view bounds];
    rootLayer.cornerRadius = 10.0;
    rootLayer.borderColor = [[NSColor redColor] CGColor];
    rootLayer.borderWidth = 10.0;
    rootLayer.shadowOpacity = 1.0;
    rootLayer.shadowRadius = 10.0;
    view.layer = rootLayer;
    [view setBackgroundColor:nil];
    [view setWantsLayer:YES];


    // Load shaders.
    NSError *error = nil;
    id <MTLLibrary> _library = [rootLayer.device newLibraryWithFile: @"shaders.metallib" error:&error];
    if (!_library) {
        NSLog(@"Failed to load library. error %@", error);
        exit(0);
    }
    id <MTLFunction> vertFunc = [_library newFunctionWithName:@"vert"];
    id <MTLFunction> fragFunc = [_library newFunctionWithName:@"frag"];

    // Create depth state.
    MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;
    _depthState = [rootLayer.device newDepthStencilStateWithDescriptor:depthDesc];

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

    // Create pipeline state.
    pipelineDesc = [MTLRenderPipelineDescriptor new];
    pipelineDesc.sampleCount = 1;
    pipelineDesc.vertexFunction = vertFunc;
    pipelineDesc.fragmentFunction = fragFunc;
    pipelineDesc.vertexDescriptor = vertDesc;
    pipelineDesc.colorAttachments[0].pixelFormat = rootLayer.pixelFormat;
   // pipelineDesc.depthAttachmentPixelFormat = rootLayer.depthStencilPixelFormat;
    //pipelineDesc.stencilAttachmentPixelFormat = self.depthStencilPixelFormat;
    _pipelineState = [rootLayer.device  newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (!_pipelineState) {
        NSLog(@"Failed to create pipeline state, error %@", error);
        exit(0);
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
            objs[j].verts[objs[j].s + i * 3 + 1].position[0] =
                    std::cos((i + 1) * (2.0 * M_PI) / N) * ((float) R / W);
            objs[j].verts[objs[j].s + i * 3 + 1].position[1] =
                    std::sin((i + 1) * (2.0 * M_PI) / N) * ((float) R / H);
            objs[j].verts[objs[j].s + i * 3 + 1].position[2] = 0;
            objs[j].verts[objs[j].s + i * 3 + 2].position[0] = 0;
            objs[j].verts[objs[j].s + i * 3 + 2].position[1] = 0;
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

    _vertexBuffer = [rootLayer.device  newBufferWithBytes:vertexBuffer->getBuffer()
                                                   length:vertexBuffer->getSize()*sizeof(Vertex)
                                                  options:
                                                          MTLResourceCPUCacheModeDefaultCache];
    // Create uniform buffers.
    for (int i = 0; i < uniformBufferCount; i++) {
        _uniformBuffers[i] = [rootLayer.device newBufferWithLength:sizeof(FrameUniforms)
                                                           options:MTLResourceCPUCacheModeWriteCombined];
    }
    // frame = 0;

    // Create semaphore for each uniform buffer.
    _semaphore = dispatch_semaphore_create(uniformBufferCount);
    uniformBufferIndex = 0;

    // Create command queue
    _commandQueue = [rootLayer.device newCommandQueue];

    timer = [NSTimer scheduledTimerWithTimeInterval:1
                                             target:self
                                           selector:@selector(render)
                                           userInfo:nil
                                            repeats:YES];

}

-(void) render
{
    NSLog(@"aaaa\n");
    // Wait for an available uniform buffer.
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);

    // Animation.
    frame++;
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
            v[i * 3 + objs[j].s].position[2] = 0;
            v[i * 3 + 1 + objs[j].s].position[0] =
                    std::cos((i + 1) * (2.0 * M_PI) / N) * ((float) R / W) +
                    objs[j].ox / W;
            v[i * 3 + 1 + objs[j].s].position[1] =
                    std::sin((i + 1) * (2.0 * M_PI) / N) * ((float) R / H) +
                    objs[j].oy / H;
            v[i * 3 + 1 + objs[j].s].position[2] = 0;
            v[i * 3 + 2 + objs[j].s].position[0] = 0 + objs[j].ox / W;
            v[i * 3 + 2 + objs[j].s].position[1] = 0 + objs[j].oy / H;
            v[i * 3 + 2 + objs[j].s].position[2] = 0;

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
    [_vertexBuffer didModifyRange:NSMakeRange(0, sizeof(Vertex)*N*3*C)];

    // Update the current uniform buffer.
    uniformBufferIndex = (uniformBufferIndex + 1) % uniformBufferCount;
    FrameUniforms *uniforms = (FrameUniforms *)[_uniformBuffers[uniformBufferIndex] contents];
    uniforms->projectionViewModel = rot;

    // Create a command buffer.
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    // Encode render command.
    id <MTLRenderCommandEncoder> encoder =
            [commandBuffer renderCommandEncoderWithDescriptor:[MTLRenderPassDescriptor renderPassDescriptor]];

    [encoder setViewport:{0, 0, rootLayer.drawableSize.width, rootLayer.drawableSize.height, 0, 1}];
    [encoder setDepthStencilState:_depthState];
    [encoder setRenderPipelineState:_pipelineState];
    [encoder setVertexBuffer:_uniformBuffers[uniformBufferIndex]
                      offset:0 atIndex:FrameUniformBuffer];

    [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:MeshVertexBuffer];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:N*3*C];
    [encoder endEncoding];

    // Set callback for semaphore.
    __block dispatch_semaphore_t semaphore = _semaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(semaphore);
    }];
    [commandBuffer presentDrawable:[rootLayer nextDrawable]];
    [commandBuffer commit];
}

@end