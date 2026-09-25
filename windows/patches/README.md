# Windows NNUE path compatibility

The app's `runner.exe.manifest` declares UTF-8 for Windows 10 1903 and newer.
The plugin additionally patches NNUE file opening to use a UTF-8 filesystem
path, converted to native UTF-16 on Windows. This avoids relying on the ANSI
code page, including on older Windows versions supported by the toolchain.

`windows-unicode-nnue.cmake` is an exact-context source patch. Windows CMake
configuration applies it to a generated copy of `misc.cpp` in the build tree.
Only this translation unit is replaced in the engine source list; headers and
other sources remain upstream. The official `ios/Pikafish` checkout stays
unchanged, and macOS/iOS/Linux builds are not affected.

When updating Pikafish:

1. Update the upstream submodule to the chosen commit.
2. Configure/build Windows. A missing or ambiguous patch context fails the build.
3. If it fails, review the upstream model loader and update or remove the patch
   as appropriate; do not bypass the check.
4. Run `python windows/tests/test_nnue_patch.py` from the plugin directory.
5. Build and test on Windows with Chinese, space-containing and ASCII model
   paths, including a pre-1903 system if it is a supported target. Test with
   the UTF-8 manifest disabled in a temporary build to isolate this patch.

The patch addresses path encoding only. Upstream model verification still
calls `exit()` on failure; missing/corrupt models and unrelated native crashes
are not fixed by this patch. It does not establish OS support for other app
components or the engine runtime.
