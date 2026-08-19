## 1.0.1

* First public release.


## 1.0.2

* Update README.md


## 1.0.3

* Test online


## 1.0.4

* Windows now compiles Pikafish from source into the plugin DLL and runs the
  engine in-process via FFI (same embedded approach as macOS), replacing the
  official prebuilt executables. A single generic x86-64 baseline build is
  produced; engine variants can still be used by importing external engines.
  The engine sources are compiled with the MSYS2 clang64 toolchain (the same
  toolchain as the official Pikafish Windows builds), so building on Windows
  requires MSYS2 with the mingw-w64-clang-x86_64-clang package installed.
* Remove the official Windows executables from assets.
* Linux keeps using the official prebuilt binaries.