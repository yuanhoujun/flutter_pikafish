#ifndef PIKAFISH_ENGINE_PLUGIN_H_
#define PIKAFISH_ENGINE_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

namespace pikafish_engine {

/// The Windows plugin does not expose any method channel API.
///
/// Its purpose is to keep the self-contained pikafish_core.dll (built with
/// the MSYS2 clang64 toolchain by CMakeLists.txt) in the application bundle.
/// The Dart side talks to the engine through FFI (see lib/src/ffi.dart), the
/// same way the macOS build embeds the engine in its framework.
class PikafishEnginePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);
};

}  // namespace pikafish_engine

// Registers the plugin with the Flutter engine.
extern "C" __declspec(dllexport) void PikafishEnginePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#endif  // PIKAFISH_ENGINE_PLUGIN_H_
