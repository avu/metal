#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "common.h"
#include "VertexBuffer.h"

constexpr int W = 800;
constexpr int H = 800;
constexpr int R = 50;
constexpr int C = 1000;


@interface HelloMetalView : MTKView
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
        // Custom MTKView.
        HelloMetalView* view = [[HelloMetalView alloc] initWithFrame:frame];
        window.contentView = view;

        [window makeKeyAndOrderFront:nil];

        [NSApp activateIgnoringOtherApps:YES];

        // Run.
        [NSApp run];
    }
    return 0;
}

// For pipeline executing.
constexpr int uniformBufferCount = 3;

constexpr int N = 32;
//static Vertex verts[N*3*C];
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

// The main view.
@implementation HelloMetalView {
    id <MTLLibrary> _library;
    id <MTLCommandQueue> _commandQueue;
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLDepthStencilState> _depthState;
    dispatch_semaphore_t _semaphore;
    id <MTLBuffer> _uniformBuffers[uniformBufferCount];
    id <MTLBuffer> _vertexBuffer;
    id <MTLTexture> _texture;
    int uniformBufferIndex;
    long frame;
}

- (id)initWithFrame:(CGRect)inFrame {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:inFrame device:device];
    if (self) {
        [self setup];
    }
    return self;
}

+ (uint8_t *)dataForImage:(NSImage *)image
{
// create the image somehow, load from file, draw into it...
    CGImageSourceRef source;

    source = CGImageSourceCreateWithData((CFDataRef)[image TIFFRepresentation], NULL);
    CGImageRef imageRef =  CGImageSourceCreateImageAtIndex(source, 0, NULL);


    // Create a suitable bitmap context for extracting the bits of the image
    const NSUInteger width = CGImageGetWidth(imageRef);
    const NSUInteger height = CGImageGetHeight(imageRef);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    uint8_t *rawData = (uint8_t *)calloc(height * width * 4, sizeof(uint8_t));
    const NSUInteger bytesPerPixel = 4;
    const NSUInteger bytesPerRow = bytesPerPixel * width;
    const NSUInteger bitsPerComponent = 8;
    CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(context);

    return rawData;
}

+ (id<MTLTexture>)texture2DWithImageNamed:(NSString *)imageName device:(id<MTLDevice>)device
{
    NSImage *image = [NSImage imageNamed:imageName];
    CGSize imageSize = CGSizeMake(image.size.width, image.size.height);
    const NSUInteger bytesPerPixel = 4;
    const NSUInteger bytesPerRow = bytesPerPixel * imageSize.width;
    uint8_t *imageData = [self dataForImage:image];

    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                                 width:imageSize.width
                                                                                                height:imageSize.height
                                                                                             mipmapped:NO];
    id<MTLTexture> texture = [device newTextureWithDescriptor:textureDescriptor];

    MTLRegion region = MTLRegionMake2D(0, 0, imageSize.width, imageSize.height);
    [texture replaceRegion:region mipmapLevel:0 withBytes:imageData bytesPerRow:bytesPerRow];

    free(imageData);

    return texture;
}

- (void)setup {
    // Set view settings.
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

    // Load shaders.
    NSError *error = nil;
    _library = [self.device newLibraryWithFile: @"shaders.metallib" error:&error];
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
    _depthState = [self.device newDepthStencilStateWithDescriptor:depthDesc];

    // Create vertex descriptor.
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

    // Create pipeline state.
    MTLRenderPipelineDescriptor *pipelineDesc = [MTLRenderPipelineDescriptor new];
    pipelineDesc.sampleCount = self.sampleCount;
    pipelineDesc.vertexFunction = vertFunc;
    pipelineDesc.fragmentFunction = fragFunc;
    pipelineDesc.vertexDescriptor = vertDesc;
    pipelineDesc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    pipelineDesc.depthAttachmentPixelFormat = self.depthStencilPixelFormat;
    pipelineDesc.stencilAttachmentPixelFormat = self.depthStencilPixelFormat;
    _pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
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

            objs[j].verts[objs[j].s + i * 3].texpos[0] =
                    std::cos(i * (2.0 * M_PI) / N);
            objs[j].verts[objs[j].s + i * 3].texpos[1] =
                    std::sin(i * (2.0 * M_PI) / N);
            objs[j].verts[objs[j].s + i * 3 + 1].texpos[0] =
                    std::cos((i + 1) * (2.0 * M_PI) / N) * ((float) R / W);
            objs[j].verts[objs[j].s + i * 3 + 1].texpos[1] =
                    std::sin((i + 1) * (2.0 * M_PI) / N) * ((float) R / H);
            objs[j].verts[objs[j].s + i * 3 + 2].texpos[0] = 0;
            objs[j].verts[objs[j].s + i * 3 + 2].texpos[1] = 0;


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
    _vertexBuffer = [self.device newBufferWithBytes:vertexBuffer->getBuffer()
                                             length:vertexBuffer->getSize()*sizeof(Vertex)
                                            options:
                                                    MTLResourceCPUCacheModeDefaultCache];
    // Create uniform buffers.
    for (int i = 0; i < uniformBufferCount; i++) {
        _uniformBuffers[i] = [self.device newBufferWithLength:sizeof(FrameUniforms)
                                          options:MTLResourceCPUCacheModeWriteCombined];
    }
    frame = 0;

    // Create semaphore for each uniform buffer.
    _semaphore = dispatch_semaphore_create(uniformBufferCount);
    uniformBufferIndex = 0;

    // Create command queue
    _commandQueue = [self.device newCommandQueue];

    //self.paused = YES;
    //self.enableSetNeedsDisplay = NO;
    //[self draw];

    _texture = [HelloMetalView texture2DWithImageNamed:@"earth.png" device:self.device];
}

- (void)drawRect:(CGRect)rect {
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
        [commandBuffer renderCommandEncoderWithDescriptor:self.currentRenderPassDescriptor];
    [encoder setViewport:{0, 0, self.drawableSize.width, self.drawableSize.height, 0, 1}];
    [encoder setDepthStencilState:_depthState];
    [encoder setRenderPipelineState:_pipelineState];
    [encoder setVertexBuffer:_uniformBuffers[uniformBufferIndex]
                      offset:0 atIndex:FrameUniformBuffer];

    [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:MeshVertexBuffer];
    [encoder setFragmentTexture:_texture atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:N*3*C];
    [encoder endEncoding];

    // Set callback for semaphore.
    __block dispatch_semaphore_t semaphore = _semaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(semaphore);
    }];
    [commandBuffer presentDrawable:self.currentDrawable];
    [commandBuffer commit];

    // Draw children.
    [super drawRect:rect];
}

@end
