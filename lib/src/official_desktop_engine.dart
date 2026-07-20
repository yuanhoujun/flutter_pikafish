import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'pikafish_engine_mode.dart';

class OfficialDesktopEngine {
  static const _packageAssetPrefix = 'packages/pikafish_engine/assets';

  final _stdoutController = StreamController<String>.broadcast();

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;

  Stream<String> get stdout => _stdoutController.stream;

  Future<bool> start(PikafishEngineMode mode) async {
    if (!Platform.isWindows && !Platform.isLinux) {
      return false;
    }

    if (_process != null) {
      throw StateError('Pikafish is already running');
    }

    final binaryName = _binaryNameForMode(mode);
    final executable = await _prepareExecutable(binaryName);

    final process = await Process.start(
      executable.path,
      const <String>[],
      runInShell: false,
    );
    _process = process;

    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _stdoutController.add,
          onError: _stdoutController.addError,
          onDone: () => _stdoutController.close(),
        );

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_stdoutController.add);

    return true;
  }

  void write(String line) {
    final process = _process;
    if (process == null) {
      throw StateError('Pikafish is not running');
    }

    process.stdin.writeln(line);
  }

  /// Requests the engine to quit and terminates its process without waiting.
  ///
  /// This is only intended for the application exit path, where waiting for
  /// stream cleanup or an exit code would delay the host application's exit.
  void terminateImmediately() {
    final process = _process;
    _process = null;
    if (process == null) return;

    try {
      process.stdin.writeln('quit');
    } on Object {
      // The process may already have closed stdin.
    }

    try {
      process.kill();
    } on Object {
      // The host application is exiting, so process termination is best effort.
    }
  }

  Future<void> dispose({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final process = _process;
    _process = null;

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    if (process == null) {
      if (!_stdoutController.isClosed) {
        await _stdoutController.close();
      }
      return;
    }

    try {
      process.stdin.writeln('quit');
      await process.stdin.flush();
      await process.exitCode.timeout(timeout);
    } on Object {
      process.kill();
    }

    try {
      await process.stdin.close();
    } on Object {
      // The process may already have exited and closed stdin.
    }

    if (!_stdoutController.isClosed) {
      await _stdoutController.close();
    }
  }

  String _binaryNameForMode(PikafishEngineMode mode) {
    final suffix = Platform.isWindows ? '.exe' : '';

    switch (mode) {
      case PikafishEngineMode.officialBmi2:
        return 'pikafish-bmi2$suffix';
      case PikafishEngineMode.officialAvx2:
        return 'pikafish-avx2$suffix';
      case PikafishEngineMode.officialAvx512:
        return 'pikafish-avx512$suffix';
      case PikafishEngineMode.officialAvx512Icl:
        return 'pikafish-avx512icl$suffix';
      case PikafishEngineMode.officialAvxVnni:
        return 'pikafish-avxvnni$suffix';
      case PikafishEngineMode.officialVnni512:
        return 'pikafish-vnni512$suffix';
      case PikafishEngineMode.auto:
      case PikafishEngineMode.officialSse41Popcnt:
      case PikafishEngineMode.officialArmv8:
      case PikafishEngineMode.officialDotProd:
        return 'pikafish-sse41-popcnt$suffix';
    }
  }

  Future<File> _prepareExecutable(String binaryName) async {
    final platformDir = Platform.isWindows ? 'windows' : 'linux';
    final bytes = await rootBundle.load(
      '$_packageAssetPrefix/$platformDir/$binaryName',
    );
    final executable = File(
      '${Directory.systemTemp.path}/pikafish_engine/$platformDir/$binaryName',
    );

    await executable.parent.create(recursive: true);
    await executable.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', <String>[
        '755',
        executable.path,
      ]);
      if (chmod.exitCode != 0) {
        throw StateError('Failed to mark Pikafish executable as runnable');
      }
    }

    return executable;
  }
}
