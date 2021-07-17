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

@interface Renderer : NSObject <MTKViewDelegate>
-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
@end

@implementation Renderer
{
    dispatch_semaphore_t inFlightSemaphore;
    id<MTLDevice> device;
    id<MTLCommandQueue> commandQueue;
}

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view
{
    self = [super init];
    
    if (self)
    {
        device = view.device;
        inFlightSemaphore = dispatch_semaphore_create(MAX_BUFFERS_IN_FLIGHT);
        
        view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        view.sampleCount = 1;
        
        commandQueue = [device newCommandQueue];
    }
    
    return self;
}

-(void)drawInMTKView:(MTKView *)view
{
    dispatch_semaphore_wait(inFlightSemaphore, DISPATCH_TIME_FOREVER);
    
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    __block dispatch_semaphore_t blockSemaphore = inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _) {
        dispatch_semaphore_signal(blockSemaphore);
    }];
    
    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor != nil)
    {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.2, 0.2, 1.0);
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        id<MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
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
    const id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    
    glfwInit();
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    GLFWwindow* pWindow = glfwCreateWindow(800, 600, "GLFW Metal", nullptr, nullptr);
    
    int width{};
    int height{};
    glfwGetFramebufferSize(pWindow, &width, &height);
    
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
