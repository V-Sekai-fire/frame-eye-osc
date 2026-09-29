# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.16)
project(frameeyeosc VERSION 0.2.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(frameeyeosc_core STATIC src/eye_server.c src/bridge.cpp)
target_include_directories(frameeyeosc_core PUBLIC src)
target_compile_definitions(frameeyeosc_core PRIVATE _GNU_SOURCE)
target_compile_options(frameeyeosc_core PRIVATE -Wall -Wextra -Werror)
find_package(Threads REQUIRED)
target_link_libraries(frameeyeosc_core PUBLIC Threads::Threads)

add_executable(frameeyeosc src/main.cpp)
target_link_libraries(frameeyeosc PRIVATE frameeyeosc_core)
target_compile_options(frameeyeosc PRIVATE -Wall -Wextra -Werror)

option(FRAMEEYEOSC_BUILD_TESTS "Build the doctest and witness-cpp tests" ${PROJECT_IS_TOP_LEVEL})
if(FRAMEEYEOSC_BUILD_TESTS)
  include(FetchContent)
  set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)
  FetchContent_Declare(doctest GIT_REPOSITORY https://github.com/doctest/doctest.git GIT_TAG v2.4.11 GIT_SHALLOW TRUE)
  FetchContent_Declare(witness GIT_REPOSITORY https://github.com/V-Sekai-fire/repository-witness-cpp.git
    GIT_TAG 5680e856a81097fb7cc52f324b2c204c5cae601a)
  set(WITNESS_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(doctest witness)
  enable_testing()
  add_executable(frameeyeosc_tests tests/main.cpp tests/test_bridge.cpp tests/test_eye_server.cpp)
  target_link_libraries(frameeyeosc_tests PRIVATE frameeyeosc_core doctest::doctest witness::witness)
  target_compile_options(frameeyeosc_tests PRIVATE -Wall -Wextra -Werror)
  add_test(NAME frameeyeosc_tests COMMAND frameeyeosc_tests)
endif()
