# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "pikafish_engine")
project(${PROJECT_NAME} LANGUAGES CXX)

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "pikafish_engine_plugin")

# Pikafish sources live in the shared submodule used by the iOS/macOS builds.
set(PIKAFISH_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../ios/Pikafish/src")
set(PIKAFISH_FFI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../ios/FlutterPikafish")

# Pikafish engine sources.
#
# Notes (mirroring the official Makefile, `make COMP=clang ARCH=x86-64`):
# - main.cpp is excluded: ffi.cpp provides the equivalent in-process engine
#   entry point (runPikafishEngine).
# - huf_decompress_amd64.S is the hand-written x86-64 zstd decompression
#   kernel; the C sources reference its symbols on 64-bit x86 targets, so it
#   must be assembled alongside them (the macOS build does the same).
# - No USE_POPCNT / USE_PEXT / USE_AVX* / USE_PREFETCH defines: ARCH=x86-64
#   is the generic baseline that runs on any 64-bit Windows machine.
set(PIKAFISH_ENGINE_SOURCES
  "${PIKAFISH_SRC_DIR}/benchmark.cpp"
  "${PIKAFISH_SRC_DIR}/bitboard.cpp"
  "${PIKAFISH_SRC_DIR}/engine.cpp"
  "${PIKAFISH_SRC_DIR}/evaluate.cpp"
  "${PIKAFISH_SRC_DIR}/memory.cpp"
  "${PIKAFISH_SRC_DIR}/misc.cpp"
  "${PIKAFISH_SRC_DIR}/movegen.cpp"
  "${PIKAFISH_SRC_DIR}/movepick.cpp"
  "${PIKAFISH_SRC_DIR}/position.cpp"
  "${PIKAFISH_SRC_DIR}/score.cpp"
  "${PIKAFISH_SRC_DIR}/search.cpp"
  "${PIKAFISH_SRC_DIR}/thread.cpp"
  "${PIKAFISH_SRC_DIR}/timeman.cpp"
  "${PIKAFISH_SRC_DIR}/tt.cpp"
  "${PIKAFISH_SRC_DIR}/tune.cpp"
  "${PIKAFISH_SRC_DIR}/uci.cpp"
  "${PIKAFISH_SRC_DIR}/ucioption.cpp"
  # NNUE
  "${PIKAFISH_SRC_DIR}/nnue/network.cpp"
  "${PIKAFISH_SRC_DIR}/nnue/nnue_accumulator.cpp"
  "${PIKAFISH_SRC_DIR}/nnue/nnue_misc.cpp"
  "${PIKAFISH_SRC_DIR}/nnue/features/full_threats.cpp"
  "${PIKAFISH_SRC_DIR}/nnue/features/half_ka_v2_hm.cpp"
  # zstd decompression subset used to load compressed NNUE networks
  "${PIKAFISH_SRC_DIR}/external/common/debug.cpp"
  "${PIKAFISH_SRC_DIR}/external/common/entropy_common.cpp"
  "${PIKAFISH_SRC_DIR}/external/common/error_private.cpp"
  "${PIKAFISH_SRC_DIR}/external/common/fse_decompress.cpp"
  "${PIKAFISH_SRC_DIR}/external/common/pool.cpp"
  "${PIKAFISH_SRC_DIR}/external/common/threading.cpp"
  "${PIKAFISH_SRC_DIR}/external/common/xxhash.cpp"
  "${PIKAFISH_SRC_DIR}/external/common/zstd_common.cpp"
  "${PIKAFISH_SRC_DIR}/external/decompress/huf_decompress.cpp"
  "${PIKAFISH_SRC_DIR}/external/decompress/huf_decompress_amd64.S"
  "${PIKAFISH_SRC_DIR}/external/decompress/zstd_ddict.cpp"
  "${PIKAFISH_SRC_DIR}/external/decompress/zstd_decompress.cpp"
  "${PIKAFISH_SRC_DIR}/external/decompress/zstd_decompress_block.cpp"
  # In-process engine wrapper (FFI entry points)
  "${PIKAFISH_FFI_DIR}/ffi.cpp"
)

if(MSVC)
  # The Pikafish sources only build correctly in GNU/MinGW mode: they rely on
  # the native __uint128_t type and on code paths guarded by _MSC_VER that are
  # inconsistent under clang-cl (bitboard.h accesses _Unsigned128 members that
  # do not exist when clang treats Bitboard as its builtin unsigned __int128).
  # The official Pikafish Windows builds therefore use the MSYS2 clang64
  # (MinGW) toolchain. MSVC's linker cannot digest the GNU-style COMDAT
  # sections those objects contain, so the engine is built into a separate,
  # fully self-contained pikafish_core.dll with the MSYS2 toolchain itself
  # (static libc++/winpthread, only system DLL dependencies). The plugin DLL
  # keeps only the Flutter plugin registration and the engine DLL is bundled
  # next to the application executable via pikafish_engine_bundled_libraries.
  set(_msys2_roots "C:/msys64" "D:/msys64" "C:/ProgramData/msys64" "C:/tools/msys64")
  find_program(MSYS2_CLANGXX
    NAMES clang++
    HINTS ${_msys2_roots}
    PATH_SUFFIXES clang64/bin
    NO_DEFAULT_PATH
  )

  if(NOT MSYS2_CLANGXX)
    message(FATAL_ERROR
      "pikafish_engine requires the MSYS2 clang64 toolchain to build the "
      "Pikafish engine sources (same toolchain as the official Pikafish "
      "Windows builds). Install MSYS2 (https://www.msys2.org), then run in "
      "an MSYS2 shell: pacman -S --needed mingw-w64-clang-x86_64-clang. "
      "Afterwards run 'flutter clean' and rebuild.")
  endif()

  set(_engine_obj_dir "${CMAKE_CURRENT_BINARY_DIR}/pikafish_objs")
  set(_engine_objs "")

  # GNU mode (no _MSC_VER): the sources take their gcc/__builtin code paths
  # and use the native __uint128_t, exactly like the official builds.
  # Flags mirror the official Makefile for `make COMP=clang ARCH=x86-64`:
  # -Wall -Wcast-qual -fno-exceptions -std=c++17 -O3 -funroll-loops -DNDEBUG,
  # with -DUSE_PTHREADS intentionally omitted (mingw uses Windows threads).
  set(_engine_flags
    -c -std=c++17 -fno-exceptions -O3 -funroll-loops -DNDEBUG
    -Wa,-mbig-obj
    -D_CRT_SECURE_NO_WARNINGS
    -I"${PIKAFISH_SRC_DIR}"
    -I"${PIKAFISH_SRC_DIR}/external"
    -I"${PIKAFISH_FFI_DIR}"
  )

  foreach(_src IN LISTS PIKAFISH_ENGINE_SOURCES)
    get_filename_component(_stem "${_src}" NAME_WE)
    get_filename_component(_ext "${_src}" EXT)
    file(TO_NATIVE_PATH "${_src}" _src_native)
    set(_obj "${_engine_obj_dir}/${_stem}.obj")
    file(TO_NATIVE_PATH "${_obj}" _obj_native)

    add_custom_command(
      OUTPUT "${_obj}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${_engine_obj_dir}"
      COMMAND "${MSYS2_CLANGXX}" ${_engine_flags} -o "${_obj_native}" "${_src_native}"
      DEPENDS "${_src}"
      COMMENT "Compiling Pikafish source ${_stem}${_ext} with MSYS2 clang64"
      VERBATIM
      COMMAND_EXPAND_LISTS
    )
    list(APPEND _engine_objs "${_obj}")
  endforeach()

  # Link the self-contained engine DLL with the MSYS2 driver itself:
  # -shared exports the __declspec(dllexport) pikafish_* FFI entry points,
  # -static links libc++/winpthread/compiler-rt statically, so the DLL only
  # depends on system DLLs (ucrtbase via api-ms-win-crt-*, KERNEL32).
  set(PIKAFISH_CORE_DLL "${CMAKE_CURRENT_BINARY_DIR}/pikafish_core.dll")
  file(TO_NATIVE_PATH "${PIKAFISH_CORE_DLL}" _core_dll_native)
  add_custom_command(
    OUTPUT "${PIKAFISH_CORE_DLL}"
    COMMAND "${MSYS2_CLANGXX}" -shared -static -o "${_core_dll_native}"
            ${_engine_objs} -lwinpthread
    DEPENDS ${_engine_objs}
    COMMENT "Linking self-contained Pikafish engine DLL"
    VERBATIM
    COMMAND_EXPAND_LISTS
  )
  add_custom_target(pikafish_engine_core ALL DEPENDS "${PIKAFISH_CORE_DLL}")

  add_library(${PLUGIN_NAME} SHARED
    "pikafish_engine_plugin.cpp"
  )
  add_dependencies(${PLUGIN_NAME} pikafish_engine_core)

  apply_standard_settings(${PLUGIN_NAME})

  set_target_properties(${PLUGIN_NAME} PROPERTIES
    CXX_VISIBILITY_PRESET hidden)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
  # Avoid conflicts between Windows headers and engine code.
  target_compile_definitions(${PLUGIN_NAME} PRIVATE NOMINMAX)

  # Exported so that the generated plugin registrant can resolve
  # <pikafish_engine/pikafish_engine_plugin.h>.
  target_include_directories(${PLUGIN_NAME} INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}"
  )

  target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

  # Ship pikafish_core.dll next to the application executable; the Dart side
  # loads it via DynamicLibrary.open('pikafish_core.dll').
  set(pikafish_engine_bundled_libraries "${PIKAFISH_CORE_DLL}" PARENT_SCOPE)
else()
  # Non-MSVC toolchains (e.g. clang) support __uint128_t natively and can
  # compile the engine sources directly.
  add_library(${PLUGIN_NAME} SHARED
    "pikafish_engine_plugin.cpp"
    ${PIKAFISH_ENGINE_SOURCES}
  )

  apply_standard_settings(${PLUGIN_NAME})

  set_target_properties(${PLUGIN_NAME} PROPERTIES
    CXX_VISIBILITY_PRESET hidden)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE NOMINMAX)

  target_include_directories(${PLUGIN_NAME} INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}"
  )
  target_include_directories(${PLUGIN_NAME} PRIVATE
    "${PIKAFISH_SRC_DIR}"
    "${PIKAFISH_SRC_DIR}/external"
    "${PIKAFISH_FFI_DIR}"
  )

  target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
endif()
