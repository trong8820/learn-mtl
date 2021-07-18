# learn-mtl

https://gist.github.com/yushroom/653602caad7338d6c8f6a7590b38d7fb

# Compile shaders to SPIR-V binary
glslangValidator -V triangle.vert -o triangle.vert.spv
glslangValidator -V triangle.frag -o triangle.frag.spv

# HLSL
spirv-cross triangle.vert.spv --hlsl --shader-model 50 --set-hlsl-vertex-input-semantic 0 POSITION --set-hlsl-vertex-input-semantic 1 COLOR --output triangle.vert.hlsl
spirv-cross triangle.frag.spv --hlsl --shader-model 50 --set-hlsl-vertex-input-semantic 0 COLOR --output triangle.frag.hlsl

# OpenGL ES 3.1
spirv-cross triangle.vert.spv --version 310 --es --output triangle.vert.glsl
spirv-cross triangle.frag.spv --version 310 --es --output triangle.frag.glsl

# Metal
spirv-cross triangle.vert.spv --msl --output triangle.vert.metal
spirv-cross triangle.frag.spv --msl --output triangle.frag.metal

# Metal command line tools
xcrun -sdk macosx metal -c MyLibrary.metal -o MyLibrary.air
xcrun -sdk macosx metallib MyLibrary.air -o MyLibrary.metallib