cmake_minimum_required(VERSION 3.20)

project(router_speed LANGUAGES CXX)

add_executable(router_speed router_speed.cpp)

target_compile_features(router_speed PRIVATE cxx_std_17)
target_compile_options(router_speed PRIVATE -Wall -Wextra)

set_target_properties(router_speed PROPERTIES
    CXX_EXTENSIONS OFF
)
