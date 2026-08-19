#include "pikafish_engine/pikafish_engine_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace pikafish_engine {

// static
void PikafishEnginePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  // The engine itself lives in the self-contained pikafish_core.dll built by
  // the MSYS2 clang64 toolchain (see CMakeLists.txt); the Dart side loads it
  // directly via FFI. This plugin only registers the (channel-less) plugin.
  registrar->AddPlugin(std::make_unique<PikafishEnginePlugin>());
}

}  // namespace pikafish_engine

extern "C" __declspec(dllexport) void PikafishEnginePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  pikafish_engine::PikafishEnginePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
