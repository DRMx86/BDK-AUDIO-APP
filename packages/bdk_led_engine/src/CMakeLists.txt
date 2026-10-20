# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(bdk_led_engine_library VERSION 0.0.1 LANGUAGES CXX)

add_library(bdk_led_engine SHARED
  "bdk_led_engine.cpp"
)

set_target_properties(bdk_led_engine PROPERTIES
  PUBLIC_HEADER bdk_led_engine.h
  OUTPUT_NAME "bdk_led_engine"
)

target_compile_definitions(bdk_led_engine PUBLIC DART_SHARED_LIB)
target_compile_features(bdk_led_engine PRIVATE cxx_std_17)
if(MSVC)
  target_compile_options(bdk_led_engine PRIVATE /W3 /fp:precise)
else()
  target_compile_options(bdk_led_engine PRIVATE -fno-fast-math)
endif()

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(bdk_led_engine PRIVATE "-Wl,-z,max-page-size=16384")
endif()
