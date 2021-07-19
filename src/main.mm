#include "main.h"

#include <iostream>

#define GLFW_INCLUDE_NONE
#define GLFW_EXPOSE_NATIVE_COCOA
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>

static const NSUInteger MAX_BUFFERS_IN_FLIGHT = 3;

const float PI = 3.14159265358979f;

// Cube
float vertices[] = {
    // Pos                      // Color
    -0.5f, -0.5f, -0.5f,        0.0f, 0.0f, 0.0f,
    -0.5f, -0.5f, +0.5f,        0.0f, 0.0f, 1.0f,
    -0.5f, +0.5f, -0.5f,        0.0f, 1.0f, 0.0f,
    -0.5f, +0.5f, +0.5f,        0.0f, 1.0f, 1.0f,
    +0.5f, -0.5f, -0.5f,        1.0f, 0.0f, 0.0f,
    +0.5f, -0.5f, +0.5f,        1.0f, 0.0f, 1.0f,
    +0.5f, +0.5f, -0.5f,        1.0f, 1.0f, 0.0f,
    +0.5f, +0.5f, +0.5f,        1.0f, 1.0f, 1.0f
};

unsigned int indices[] =
{
    0, 2, 1,
    1, 2, 3,
    4, 5, 6,
    5, 7, 6,
    0, 1, 5,
    0, 5, 4,
    2, 6, 7,
    2, 7, 3,
    0, 4, 6,
    0, 6, 2,
    1, 3, 7,
    1, 7, 5
};

const char* vertexShaderSource = R"(
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct OffsetBlock
{
    float offsetx;
};

struct main0_out
{
    float3 vColor [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct main0_in
{
    float3 aPos [[attribute(0)]];
    float3 aColor [[attribute(1)]];
};

vertex main0_out main0(main0_in in [[stage_in]], constant OffsetBlock& _26 [[buffer(0)]])
{
    main0_out out = {};
    out.vColor = in.aColor;
    out.gl_Position = float4(in.aPos + float3(_26.offsetx, 0.0, 0.5), 1.0);
    return out;
}
)";

const char* fragmentShaderSource = R"(
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct main0_out
{
    float4 FragColor [[color(0)]];
};

struct main0_in
{
    float3 vColor [[user(locn0)]];
};

fragment main0_out main0(main0_in in [[stage_in]])
{
    main0_out out = {};
    out.FragColor = float4(in.vColor, 1.0);
    return out;
}
)";

@interface Renderer : NSObject <MTKViewDelegate>
-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
@end

@implementation Renderer
{
    dispatch_semaphore_t inFlightSemaphore;
    id<MTLDevice> device;
    
    id<MTLRenderPipelineState> renderPipelineState;
    id<MTLDepthStencilState> depthStencilState;
    
    id<MTLCommandQueue> commandQueue;
    
    id<MTLBuffer> dynamicUniformBuffer[MAX_BUFFERS_IN_FLIGHT];
    uint8_t uniformBufferIndex;
    
    id<MTLBuffer> vertexBuffer;
    id<MTLBuffer> indexBuffer;
    MTLVertexDescriptor* vertexDescriptor;
    
    float offsetx;
}

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view
{
    self = [super init];
    uniformBufferIndex = 0;
    offsetx = 0.5f;
    
    if (self)
    {
        device = view.device;
        inFlightSemaphore = dispatch_semaphore_create(MAX_BUFFERS_IN_FLIGHT);
        
        view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        view.sampleCount = 1;
        
        vertexDescriptor = [[MTLVertexDescriptor alloc] init];
        vertexDescriptor.attributes[0].format = MTLVertexFormatFloat3;
        vertexDescriptor.attributes[0].offset = 0;
        vertexDescriptor.attributes[0].bufferIndex = 2;
        
        vertexDescriptor.attributes[1].format = MTLVertexFormatFloat3;
        vertexDescriptor.attributes[1].offset = 12;
        vertexDescriptor.attributes[1].bufferIndex = 2;
        
        vertexDescriptor.layouts[2].stride = 24;
        vertexDescriptor.layouts[2].stepRate = 1;
        vertexDescriptor.layouts[2].stepFunction = MTLVertexStepFunctionPerVertex;
        
        NSError* vertexshaderError;
        id<MTLLibrary> vertexLibrary = [device newLibraryWithSource:[NSString stringWithUTF8String:vertexShaderSource]
                                                            options:nil
                                                              error:&vertexshaderError];
        if (!vertexLibrary)
        {
            NSLog(@"Can not compile metal shader: %@", vertexshaderError);
        }
        
        NSError* fragmentshaderError;
        id<MTLLibrary> fragmentLibrary = [device newLibraryWithSource:[NSString stringWithUTF8String:fragmentShaderSource]
                                                              options:nil
                                                                error:&fragmentshaderError];
        if (!fragmentLibrary)
        {
            NSLog(@"Can not compile metal shader: %@", fragmentshaderError);
        }
        
        id<MTLFunction> vertexFunction = [vertexLibrary newFunctionWithName:@"main0"];
        id<MTLFunction> fragmentFunction = [fragmentLibrary newFunctionWithName:@"main0"];
        
        MTLRenderPipelineDescriptor* renderPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        renderPipelineDescriptor.sampleCount = view.sampleCount;
        renderPipelineDescriptor.vertexFunction = vertexFunction;
        renderPipelineDescriptor.fragmentFunction = fragmentFunction;
        renderPipelineDescriptor.vertexDescriptor = vertexDescriptor;
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
        renderPipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
        renderPipelineDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
        
        NSError* renderPipelineError;
        renderPipelineState = [device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor
                                                                     error:&renderPipelineError];
        if (!renderPipelineState)
        {
            NSLog(@"Failed to create pipeline state, error %@", renderPipelineError);
        }
        
        MTLDepthStencilDescriptor* depthStencilDescriptor = [[MTLDepthStencilDescriptor alloc] init];
        depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
        depthStencilDescriptor.depthWriteEnabled = YES;
        depthStencilState = [device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
        
        for (NSUInteger i=0; i<MAX_BUFFERS_IN_FLIGHT; i++)
        {
            dynamicUniformBuffer[i] = [device newBufferWithLength:sizeof(float)
                                                          options:MTLResourceStorageModeShared];
        }
        
        vertexBuffer = [device newBufferWithBytes:vertices
                                           length:sizeof(vertices)
                                          options:MTLResourceStorageModeShared];
        indexBuffer = [device newBufferWithBytes:indices
                                          length:sizeof(indices)
                                         options:MTLResourceStorageModeShared];
        
        commandQueue = [device newCommandQueue];
    }
    
    return self;
}

-(void)drawInMTKView:(MTKView *)view
{
    dispatch_semaphore_wait(inFlightSemaphore, DISPATCH_TIME_FOREVER);
    
    uniformBufferIndex = (uniformBufferIndex + 1) % MAX_BUFFERS_IN_FLIGHT;
    
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    __block dispatch_semaphore_t blockSemaphore = inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _) {
        dispatch_semaphore_signal(blockSemaphore);
    }];
    
    offsetx += 0.01f;
    if (offsetx > 0.5f) offsetx = -0.5f;
    float* uniforms = (float*) dynamicUniformBuffer[uniformBufferIndex].contents;
    *uniforms = offsetx;
    
    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor != nil)
    {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.2, 0.2, 1.0);
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        id<MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderCommandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderCommandEncoder setCullMode:MTLCullModeBack];
        [renderCommandEncoder setRenderPipelineState:renderPipelineState];
        [renderCommandEncoder setDepthStencilState:depthStencilState];
        
        [renderCommandEncoder setVertexBuffer:dynamicUniformBuffer[uniformBufferIndex]
                                       offset:0
                                      atIndex:0];
        
        [renderCommandEncoder setVertexBuffer:vertexBuffer
                                       offset:0
                                      atIndex:2];
        
        [renderCommandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                         indexCount:36
                                          indexType:MTLIndexTypeUInt32
                                        indexBuffer:indexBuffer
                                  indexBufferOffset:0];
        
        [renderCommandEncoder endEncoding];
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    
    [commandBuffer commit];
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
}

@end

@interface ViewController : NSViewController
@property (nonatomic, strong) Renderer* renderer;
@end

@implementation ViewController
-(void)viewDidLoad
{
    [super viewDidLoad];
    
    MTKView* mtkView = (MTKView*) self.view;
    
    self.renderer = [[Renderer alloc] initWithMetalKitView: mtkView];
    mtkView.delegate = self.renderer;
    
    [mtkView setPreferredFramesPerSecond:60];
}
@end

void run()
{
    glfwInit();
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    GLFWwindow* pWindow = glfwCreateWindow(800, 600, "GLFW Metal", nullptr, nullptr);
    
    int width{};
    int height{};
    glfwGetFramebufferSize(pWindow, &width, &height);
    
    const id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    
    CGRect frame = CGRectMake(0.0f, 0.0f, width, height);
    MTKView* view = [[MTKView alloc] initWithFrame:frame device:device];
    
    NSWindow* nsWindow = glfwGetCocoaWindow(pWindow);
    [nsWindow setContentView: view];
    
    ViewController* viewController = [[ViewController alloc] init];
    viewController.view = view;
    [viewController viewDidLoad];

    while (!glfwWindowShouldClose(pWindow))
    {
        //glfwPollEvents();
        glfwWaitEvents();
    }

    glfwDestroyWindow(pWindow);
    glfwTerminate();
}
