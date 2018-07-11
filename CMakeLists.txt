cmake_minimum_required(VERSION 3.6)
set (CMAKE_CXX_STANDARD 11)
project(metal)
execute_process(COMMAND xcode-select -p
        WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
        RESULT_VARIABLE xcode_result
        OUTPUT_VARIABLE xcode_path
        OUTPUT_STRIP_TRAILING_WHITESPACE)

set(xcode_usr_bin ${xcode_path}/Platforms/MacOSX.platform/usr/bin)
FIND_LIBRARY(APPKIT_LIBRARY AppKit)
set(SOURCE_FILES  src/RenderObject.cpp src/RenderObject.h src/VertexBuffer.cpp src/VertexBuffer.h src/MetalVertexBuffer.mm src/MetalVertexBuffer.h)
add_executable(metal ${SOURCE_FILES} src/main.mm ${PROJECT_BINARY_DIR}/shaders.metallib_)
add_executable(cametal ${SOURCE_FILES} src/camain.mm ${PROJECT_BINARY_DIR}/shaders.metallib_)

target_link_libraries(metal ${APPKIT_LIBRARY})
target_link_libraries(metal "-framework Cocoa")
target_link_libraries(metal "-framework Metal")
target_link_libraries(metal "-framework MetalKit")

target_link_libraries(cametal ${APPKIT_LIBRARY})
target_link_libraries(cametal "-framework Cocoa")
target_link_libraries(cametal "-framework Metal")
target_link_libraries(cametal "-framework MetalKit")
target_link_libraries(cametal "-framework QuartzCore")
add_custom_command(
        OUTPUT ${PROJECT_BINARY_DIR}/shaders.metallib_
        WORKING_DIR ${PROJECT_BINARY_DIR}
        COMMAND ${xcode_usr_bin}/metal -O2 -std=osx-metal1.1 -o shaders.air
                                       ${CMAKE_SOURCE_DIR}/src/shaders.metal
        COMMAND ${xcode_usr_bin}/metal-ar r shaders.metal-ar shaders.air
        COMMAND ${xcode_usr_bin}/metallib -o shaders.metallib_ shaders.metal-ar
        COMMAND ${CMAKE_COMMAND} -E copy shaders.metallib_ shaders.metallib
        MAIN_DEPENDENCY src/shaders.metal
        VERBATIM
)