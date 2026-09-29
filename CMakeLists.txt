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

option(FRAMEEYEOSC_BUILD_TESTS "Build the witness-cpp tests (vendored in thirdparty/)" ${PROJECT_IS_TOP_LEVEL})
if(FRAMEEYEOSC_BUILD_TESTS)
  slang_to_cpp(core ${CMAKE_CURRENT_BINARY_DIR}/core.cpp)
  add_library(frameeyeosc_core STATIC ${CMAKE_CURRENT_BINARY_DIR}/core.cpp)
  find_package(Threads REQUIRED)
  target_link_libraries(frameeyeosc_core PUBLIC Threads::Threads)
  enable_testing()
  add_executable(frameeyeosc_tests tests/main.cpp tests/test_bridge.cpp tests/test_eye_server.cpp tests/test_osc.cpp
    tests/test_expressions.cpp tests/test_anime.cpp tests/test_params.cpp)
  target_include_directories(frameeyeosc_tests PRIVATE tests thirdparty/witness-cpp/include)
  target_link_libraries(frameeyeosc_tests PRIVATE frameeyeosc_core)
  target_compile_options(frameeyeosc_tests PRIVATE -Wall -Wextra -Werror)
  add_test(NAME frameeyeosc_tests COMMAND frameeyeosc_tests)
endif()
