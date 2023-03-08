cmake_minimum_required(VERSION 3.4.1)

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