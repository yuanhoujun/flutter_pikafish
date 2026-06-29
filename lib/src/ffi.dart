import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

DynamicLibrary? _nativeLib;

DynamicLibrary get _nativeLibrary {
  final existing = _nativeLib;
  if (existing != null) {
    return existing;
  }

  final library = _openNativeLibrary();
  _nativeLib = library;
  return library;
}

DynamicLibrary _openNativeLibrary() {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('pikafish_engine.framework/pikafish_engine');
  }

  return DynamicLibrary.process();
}

final int Function() nativeInit = _nativeLibrary
    .lookup<NativeFunction<Int32 Function()>>('pikafish_init')
    .asFunction();

final int Function() nativeMain = _nativeLibrary
    .lookup<NativeFunction<Int32 Function()>>('pikafish_main')
    .asFunction();

final int Function() nativeStartThreaded = _nativeLibrary
    .lookup<NativeFunction<Int32 Function()>>('pikafish_start_threaded')
    .asFunction();

final int Function(Pointer<Utf8>) nativeStdinWrite = _nativeLibrary
    .lookup<NativeFunction<IntPtr Function(Pointer<Utf8>)>>(
      'pikafish_stdin_write',
    )
    .asFunction();

final Pointer<Utf8> Function() nativeStdoutRead = _nativeLibrary
    .lookup<NativeFunction<Pointer<Utf8> Function()>>('pikafish_stdout_read')
    .asFunction();

final Pointer<Utf8> Function() nativeStdoutTryRead = _nativeLibrary
    .lookup<NativeFunction<Pointer<Utf8> Function()>>(
      'pikafish_stdout_try_read',
    )
    .asFunction();

final int Function() nativeIsRunning = _nativeLibrary
    .lookup<NativeFunction<Int32 Function()>>('pikafish_is_running')
    .asFunction();

final int Function() nativeExitCode = _nativeLibrary
    .lookup<NativeFunction<Int32 Function()>>('pikafish_exit_code')
    .asFunction();

final void Function() nativeJoinThreaded = _nativeLibrary
    .lookup<NativeFunction<Void Function()>>('pikafish_join_threaded')
    .asFunction();

final void Function() nativeShutdown = _nativeLibrary
    .lookup<NativeFunction<Void Function()>>('pikafish_shutdown')
    .asFunction();
