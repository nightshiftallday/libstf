cmake_minimum_required(VERSION 3.16)
project(libstf)

# NOTE: This CMakeLists.txt is only here because of VSCode

# Dependencies
add_subdirectory(coyote/sw coyote)

# libSTF
add_subdirectory(software)

# Examples
add_subdirectory(examples/01_output_buffer_manager)
