# Apply only to a generated translation unit; never edit the upstream submodule.
# Usable independently: cmake -DINPUT=.../misc.cpp -DOUTPUT=.../misc.cpp -P this-file
if(NOT DEFINED INPUT OR NOT DEFINED OUTPUT)
  message(FATAL_ERROR "NNUE Unicode patch requires INPUT and OUTPUT paths")
endif()
get_filename_component(_input_real "${INPUT}" REALPATH)
get_filename_component(_output_real "${OUTPUT}" REALPATH)
if(_input_real STREQUAL _output_real)
  message(FATAL_ERROR "NNUE Unicode patch must not overwrite upstream source")
endif()
file(READ "${INPUT}" _source)
string(REPLACE "\r\n" "\n" _source "${_source}")

set(_old [=[std::stringstream read_compressed_nnue(const std::string& fpath) {
    std::stringstream ss;

    std::ifstream fin(fpath, std::ios::binary);]=])
set(_new [=[std::stringstream read_compressed_nnue(const std::string& fpath) {
    std::stringstream ss;

#if defined(_WIN32)
    // EvalFile arrives over FFI as UTF-8. Use a native UTF-16 filesystem path
    // so opening the model does not depend on the Windows ANSI code page.
    std::ifstream fin(std::filesystem::u8path(fpath), std::ios::binary);
#else
    std::ifstream fin(fpath, std::ios::binary);
#endif]=])

# Require the known context exactly once. Upstream changes must be reviewed,
# never silently compiled without the compatibility fix.
string(FIND "${_source}" "${_old}" _match)
if(_match EQUAL -1)
  message(FATAL_ERROR
    "Pikafish NNUE Unicode patch no longer matches misc.cpp. Review the upstream "
    "update and windows/patches/windows-unicode-nnue.cmake before building.")
endif()
string(REPLACE "${_old}" "" _without_match "${_source}")
string(LENGTH "${_source}" _source_length)
string(LENGTH "${_without_match}" _remaining_length)
string(LENGTH "${_old}" _match_length)
math(EXPR _removed_length "${_source_length} - ${_remaining_length}")
if(NOT _removed_length EQUAL _match_length)
  message(FATAL_ERROR "Pikafish NNUE Unicode patch matched more than once")
endif()
string(REPLACE "${_old}" "${_new}" _patched "${_source}")
set(_patched "#if defined(_WIN32)\n#include <filesystem>\n#endif\n${_patched}")
get_filename_component(_output_dir "${OUTPUT}" DIRECTORY)
file(MAKE_DIRECTORY "${_output_dir}")
# Avoid rebuilding the engine when a configure run produced identical content.
file(WRITE "${OUTPUT}.in" "${_patched}")
configure_file("${OUTPUT}.in" "${OUTPUT}" COPYONLY)
