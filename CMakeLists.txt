cmake_minimum_required (VERSION 3.18)

project ("learn-mtl")

enable_language(C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED OFF)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_UNITY_BUILD ON)

set_property(GLOBAL PROPERTY USE_FOLDERS ON)

# Detect platform
#WINDOWS   	=  Windows
#ANDROID    =  Android
#LINUX      =  Linux
#MACOS    	=  macOS
#IOS    	=  iOS
if(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
	set(WINDOWS TRUE)
	set(PLATFORM_FOLDER windows)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Android")
	set(ANDROID TRUE)
	set(PLATFORM_FOLDER android)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	if(ANDROID)
		set(ANDROID TRUE)
		set(PLATFORM_FOLDER android)
	else()
		set(LINUX TRUE)
		set(PLATFORM_FOLDER linux)
	endif()
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	set(APPLE TRUE)
	set(MACOS TRUE)
	set(PLATFORM_FOLDER macos)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "iOS")
	set(APPLE TRUE)
	set(IOS TRUE)
	set(PLATFORM_FOLDER ios)
else()
	message(FATAL_ERROR "Unsupported platform, CMake will exit")
	return()
endif()

# 3rdparty include
include_directories (
	${CMAKE_SOURCE_DIR}/3rdparty/glfw-3.3.2/include
)

# 3rdparty sources
file(GLOB_RECURSE 3RDPARTY_SOURCE_FILES
	${CMAKE_SOURCE_DIR}/3rdparty/*.c
	${CMAKE_SOURCE_DIR}/3rdparty/*.cc
	${CMAKE_SOURCE_DIR}/3rdparty/*.cpp
)

# 3rdparty libs
link_directories(
	${CMAKE_SOURCE_DIR}/3rdparty/glfw-3.3.2/lib/${PLATFORM_FOLDER}
)

# 3rdparty link
link_libraries(glfw3)

if (APPLE)
    link_libraries(
        "-framework AppKit"
        "-framework IOKit"
        "-framework Carbon"
        "-framework Cocoa"
        "-framework QuartzCore"
        "-framework AudioToolbox"
        "-framework System"
        "-framework CoreGraphics"
        "-framework Metal"
        "-framework MetalKit"
    )
endif()

# Projects
include_directories (
	${CMAKE_SOURCE_DIR}/include
)

add_executable(${PROJECT_NAME} src/main.cpp src/main.mm)

