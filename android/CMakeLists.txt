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

# file(DOWNLOAD
# https://tests.pikafishchess.org/api/nn/nn-3475407dc199.nnue
# ${CMAKE_BINARY_DIR}/nn-3475407dc199.nnue
# )
