cmake_minimum_required(VERSION 3.14)
project(libstf_output_buffer_manager VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(EN_SIMULATION "Link against Coyote simulation library (no FPGA required)" OFF)

add_executable(output_buffer_manager src/main.cpp)

if(NOT TARGET Coyote)
    if(EN_SIMULATION)
        find_package(CoyoteSimulation QUIET)
        if(NOT CoyoteSimulation_FOUND)
            add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../coyote/sim/sw coyote)
        endif()
    else()
        find_package(Coyote QUIET)
        if(NOT Coyote_FOUND)
            add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../coyote/sw coyote)
        endif()
    endif()
endif()

if(NOT TARGET libstf)
    find_package(libstf QUIET)
    if(NOT libstf_FOUND)
        add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../software libstf)
    endif()
endif()

target_link_libraries(output_buffer_manager PRIVATE Coyote libstf)
