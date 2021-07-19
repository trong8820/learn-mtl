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

const char* vertexShaderSource = R"(
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wmissing-braces"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

template<typename T, size_t Num>
struct spvUnsafeArray
{
    T elements[Num ? Num : 1];
    
    thread T& operator [] (size_t pos) thread
    {
        return elements[pos];
    }
    constexpr const thread T& operator [] (size_t pos) const thread
    {
        return elements[pos];
    }
    
    device T& operator [] (size_t pos) device
    {
        return elements[pos];
    }
    constexpr const device T& operator [] (size_t pos) const device
    {
        return elements[pos];
    }
    
    constexpr const constant T& operator [] (size_t pos) const constant
    {
        return elements[pos];
    }
    
    threadgroup T& operator [] (size_t pos) threadgroup
    {
        return elements[pos];
    }
    constexpr const threadgroup T& operator [] (size_t pos) const threadgroup
    {
        return elements[pos];
    }
};

struct OffsetBlock
{
    float offsetx;
};

constant spvUnsafeArray<float2, 3> _19 = spvUnsafeArray<float2, 3>({ float2(0.0, -0.5), float2(0.5), float2(-0.5, 0.5) });
constant spvUnsafeArray<float3, 3> _28 = spvUnsafeArray<float3, 3>({ float3(1.0, 0.0, 0.0), float3(0.0, 1.0, 0.0), float3(0.0, 0.0, 1.0) });

struct main0_out
{
    float3 fragColor [[user(locn0)]];
    float4 gl_Position [[position]];
};

vertex main0_out main0(constant OffsetBlock& _45 [[buffer(0)]], uint gl_VertexIndex [[vertex_id]])
{
    main0_out out = {};
    out.gl_Position = float4(_19[int(gl_VertexIndex)] + float2(_45.offsetx, 0.0), 0.0, 1.0);
    out.fragColor = _28[int(gl_VertexIndex)];
    return out;
}
)";

const char* fragmentShaderSource = R"(
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct main0_out
{
    float4 outColor [[color(0)]];
};

struct main0_in
{
    float3 fragColor [[user(locn0)]];
};

fragment main0_out main0(main0_in in [[stage_in]])
{
    main0_out out = {};
    out.outColor = float4(in.fragColor, 1.0);
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
    
    id<MTLBuffer> dynamicUniformBuffer[MAX_BUFFERS_IN_FLIGHT];
    
    id<MTLRenderPipelineState> renderPipelineState;
    id<MTLDepthStencilState> depthStencilState;
    
    id<MTLCommandQueue> commandQueue;
    
    uint8_t uniformBufferIndex;
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
        
        [renderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        
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
