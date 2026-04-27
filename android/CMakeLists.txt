cmake_minimum_required(VERSION 3.10.2)
project(pikafish_engine LANGUAGES CXX)

# Enable 16KB page size support for Android (required for Google Play).
add_link_options(-Wl,-z,max-page-size=16384)
add_link_options(-Wl,-z,common-page-size=16384)

if(ANDROID_ABI STREQUAL arm64-v8a)
    file(
        GLOB_RECURSE
        cppPaths
        "../ios/Pikafish/src/*.cpp"
    )

    add_library(
        pikafish
        SHARED
        ../ios/FlutterPikafish/ffi.cpp
        ${cppPaths}
    )

    # Matches Pikafish's official Android ARCH=armv8 settings.
    target_compile_definitions(pikafish PRIVATE IS_64BIT USE_POPCNT USE_NEON=8)
else()
    add_library(
        pikafish
        SHARED
        pikafish_stub.cpp
    )

    target_compile_definitions(pikafish PRIVATE PIKAFISH_UNSUPPORTED_ABI="${ANDROID_ABI}")
endif()

target_compile_features(pikafish PRIVATE cxx_std_17)

target_compile_options(
    pikafish
    PRIVATE
    -fno-exceptions
    $<$<NOT:$<CONFIG:Debug>>:-O3>
)

target_compile_definitions(
    pikafish
    PRIVATE
    USE_PTHREADS
    $<$<NOT:$<CONFIG:Debug>>:NDEBUG>
)
