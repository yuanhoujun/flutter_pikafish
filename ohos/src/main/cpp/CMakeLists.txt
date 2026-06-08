cmake_minimum_required(VERSION 3.5.0)
project(pikafish_engine LANGUAGES CXX)

set(PLUGIN_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../..)
set(PIKAFISH_ROOT ${PLUGIN_ROOT}/ios/Pikafish)

file(GLOB_RECURSE PIKAFISH_SOURCES
    "${PIKAFISH_ROOT}/src/*.cpp"
)

list(FILTER PIKAFISH_SOURCES EXCLUDE REGEX ".*/src/main\\.cpp$")
list(FILTER PIKAFISH_SOURCES EXCLUDE REGEX ".*/src/universal/.*")

add_library(pikafish SHARED
    "${PLUGIN_ROOT}/ios/FlutterPikafish/ffi.cpp"
    "${PIKAFISH_ROOT}/src/main.cpp"
    ${PIKAFISH_SOURCES}
)

target_compile_features(pikafish PRIVATE cxx_std_17)

target_include_directories(pikafish PRIVATE
    "${PIKAFISH_ROOT}/src"
    "${PLUGIN_ROOT}/ios/FlutterPikafish"
)

target_compile_options(pikafish PRIVATE
    -fno-exceptions
    $<$<NOT:$<CONFIG:Debug>>:-O3>
)

target_compile_definitions(pikafish PRIVATE
    __OHOS__
    USE_PTHREADS
    IS_64BIT
    USE_POPCNT
    USE_NEON=8
    ARCH=armv8
    $<$<NOT:$<CONFIG:Debug>>:NDEBUG>
)
