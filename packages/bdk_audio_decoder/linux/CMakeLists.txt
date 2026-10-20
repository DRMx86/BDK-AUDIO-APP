cmake_minimum_required(VERSION 3.14)
project(bdk_audio_decoder LANGUAGES CXX)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")
set(bdk_audio_decoder_bundled_libraries $<TARGET_FILE:bdk_audio_decoder> PARENT_SCOPE)
