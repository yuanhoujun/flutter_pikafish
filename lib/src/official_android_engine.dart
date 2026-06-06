import 'dart:async';

import 'package:flutter/services.dart';

import 'pikafish_engine_mode.dart';

class OfficialAndroidEngine {
  static const _methodChannel = MethodChannel(
    'cn.chessroad.pikafish_engine/methods',
  );
  static const _eventChannel = EventChannel(
    'cn.chessroad.pikafish_engine/stdout',
  );

  Stream<String> get stdout =>
      _eventChannel.receiveBroadcastStream().cast<String>();

  Future<bool> start(PikafishEngineMode mode) async {
    final result = await _methodChannel.invokeMethod<bool>('start', {
      'mode': mode.name,
    });
    return result ?? false;
  }

  Future<void> write(String line) {
    return _methodChannel.invokeMethod<void>('write', {'line': line});
  }

  Future<void> dispose() {
    return _methodChannel.invokeMethod<void>('dispose');
  }
}
