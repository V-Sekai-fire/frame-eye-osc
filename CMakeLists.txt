# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.16)
project(frameeyeosc VERSION 0.3.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The source is Slang. slangc emits it as C++ that calls libc through __extern_cpp
# declarations; E41017 flags reads of zero-initialised globals, which C++ guarantees.
find_program(SLANGC slangc REQUIRED)
file(GLOB SLANG_SOURCES CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/src/*.slang)

function(slang_to_cpp p_module p_output)
  add_custom_command(OUTPUT ${p_output}
    COMMAND ${SLANGC} ${CMAKE_CURRENT_SOURCE_DIR}/src/${p_module}.slang -I ${CMAKE_CURRENT_SOURCE_DIR}/src
            -target cpp -warnings-disable 41017 -o ${p_output}
    DEPENDS ${SLANG_SOURCES}
    VERBATIM)
endfunction()

slang_to_cpp(main ${CMAKE_CURRENT_BINARY_DIR}/main.cpp)
add_executable(frameeyeosc ${CMAKE_CURRENT_BINARY_DIR}/main.cpp)
target_compile_options(frameeyeosc PRIVATE -Wno-main)

# The tests are an optional Lean package in tests/ (lake fetches plausible-witness-dag).
option(FRAMEEYEOSC_LEAN_TESTS "Add a lean_tests target that builds and runs tests/ with lake" OFF)
if(FRAMEEYEOSC_LEAN_TESTS)
  find_program(LAKE lake REQUIRED)
  add_custom_target(lean_tests
    COMMAND ${LAKE} build
    COMMAND ${LAKE} exe tests
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/tests
    USES_TERMINAL)
endif()
