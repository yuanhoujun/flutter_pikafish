import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'ffi.dart';
import 'official_android_engine.dart';
import 'official_desktop_engine.dart';
import 'pikafish_engine_mode.dart';
import 'pikafish_state.dart';

/// A wrapper for C++ engine.
class Pikafish {
  //
  final Completer<Pikafish>? completer;
  final PikafishEngineMode engineMode;

  final _state = _PikafishState();

  final _stdoutController = StreamController<String>.broadcast();

  final _mainPort = ReceivePort();
  final _stdoutPort = ReceivePort();

  late StreamSubscription _mainSubscription;
  late StreamSubscription _stdoutSubscription;
  final _exitCompleter = Completer<void>();
  bool _cleanedUp = false;
  OfficialAndroidEngine? _officialAndroidEngine;
  OfficialDesktopEngine? _officialDesktopEngine;
  bool _disposed = false;
  bool _threadedNativeEngine = false;
  Timer? _nativeStdoutTimer;
  String _nativeStdoutRemainder = '';

  Pikafish._({this.completer, required this.engineMode}) {
    //
    _mainSubscription = _mainPort.listen(
      (message) => _cleanUp(message is int ? message : 1),
    );

    _stdoutSubscription = _stdoutPort.listen(
      (message) {
        if (message is String) {
          if (_stdoutController.isClosed) return;
          _stdoutController.sink.add(message);
        } else {
          prt('[pikafish] The stdout isolate sent $message');
        }
      },
    );

    _start().then(
      (success) {
        if (_cleanedUp) return;

        //
        final state = success ? PikafishState.ready : PikafishState.error;
        _state._setValue(state);

        if (state == PikafishState.ready) {
          completer?.complete(this);
        } else {
          _cleanUp(1);
        }
      },
      onError: (error) {
        if (_cleanedUp) return;

        prt('[pikafish] The init isolate encountered an error $error');
        _cleanUp(1);
      },
    );
  }

  static Pikafish? _instance;

  /// Creates a C++ engine.
  ///
  /// This may throws a [StateError] if an active instance is being used.
  /// Owner must [dispose] it before a new instance can be created.
  factory Pikafish({PikafishEngineMode engineMode = PikafishEngineMode.auto}) {
    //
    if (_instance != null) {
      throw StateError('Multiple instances are not supported, yet.');
    }

    _instance = Pikafish._(engineMode: engineMode);

    return _instance!;
  }

  /// The current state of the underlying C++ engine.
  ValueListenable<PikafishState> get state => _state;

  /// The standard output stream.
  Stream<String> get stdout => _stdoutController.stream;

  /// The standard input sink.
  set stdin(String line) {
    //
    final stateValue = _state.value;

    if (stateValue != PikafishState.ready) {
      throw StateError('Pikafish is not ready ($stateValue)');
    }

    final officialEngine = _officialAndroidEngine;
    if (officialEngine != null) {
      prt('engine=< $line');
      officialEngine.write(line);
    } else if (_officialDesktopEngine != null) {
      prt('engine=< $line');
      final desktopEngine = _officialDesktopEngine!;
      desktopEngine.write(line);
    } else {
      final pointer = '$line\n'.toNativeUtf8();
      final result = nativeStdinWrite(pointer);
      calloc.free(pointer);
      if (result < 0) {
        throw StateError('nativeStdinWrite failed: $result');
      }
    }
  }

  /// Restarts the engine and returns the new ready instance.
  ///
  /// The current official engine variant is preserved unless [engineMode] is
  /// provided. On iOS, [engineMode] is ignored because iOS always uses FFI.
  static Future<Pikafish> restart({PikafishEngineMode? engineMode}) async {
    final current = _instance;
    final nextMode =
        engineMode ?? current?.engineMode ?? PikafishEngineMode.auto;

    if (current != null) {
      await current._shutdownForRestart();
    }

    return pikafishAsync(engineMode: nextMode);
  }

  /// Stops the C++ engine.
  void dispose() {
    unawaited(disposeAsync());
  }

  Future<void> disposeAsync(
      {Duration timeout = const Duration(seconds: 2)}) async {
    _disposed = true;

    if (_cleanedUp) {
      return _exitCompleter.future;
    }

    final officialEngine = _officialAndroidEngine;
    if (officialEngine != null) {
      await officialEngine.dispose();
      _cleanUp(0);
      return;
    }

    final desktopEngine = _officialDesktopEngine;
    if (desktopEngine != null) {
      await desktopEngine.dispose();
      _cleanUp(0);
      return;
    }

    if (_state.value == PikafishState.ready) {
      try {
        stdin = 'quit';
        await _exitCompleter.future.timeout(timeout);
        return;
      } on Object {
        // Fall through and force native shutdown below.
      }
    }

    _cleanUp(0);
  }

  void _cleanUp(int exitCode) {
    if (_cleanedUp) return;
    _cleanedUp = true;

    _nativeStdoutTimer?.cancel();
    _nativeStdoutTimer = null;

    final officialEngine = _officialAndroidEngine;
    if (officialEngine != null) {
      officialEngine.dispose();
    } else if (_officialDesktopEngine != null) {
      final desktopEngine = _officialDesktopEngine!;
      desktopEngine.dispose();
    } else {
      nativeShutdown();
      if (_threadedNativeEngine) {
        nativeJoinThreaded();
      }
    }

    if (_threadedNativeEngine) {
      _drainNativeStdout();
      if (_nativeStdoutRemainder.isNotEmpty && !_stdoutController.isClosed) {
        _stdoutController.sink.add(_nativeStdoutRemainder);
        _nativeStdoutRemainder = '';
      }
    }

    if (!_stdoutController.isClosed) {
      _stdoutController.close();
    }

    _mainSubscription.cancel();
    _stdoutSubscription.cancel();

    _state._setValue(
      exitCode == 0 ? PikafishState.disposed : PikafishState.error,
    );

    if (completer?.isCompleted == false) {
      completer
          ?.completeError(StateError('Pikafish exited with code $exitCode'));
    }

    _instance = null;

    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete();
    }
  }

  Future<void> _shutdownForRestart() async {
    final officialEngine = _officialAndroidEngine;
    if (officialEngine != null) {
      await officialEngine.dispose();
      _cleanUp(0);
      return;
    }

    final desktopEngine = _officialDesktopEngine;
    if (desktopEngine != null) {
      await desktopEngine.dispose();
      _cleanUp(0);
      return;
    }

    if (_state.value == PikafishState.ready) {
      stdin = 'quit';
      try {
        await _exitCompleter.future.timeout(const Duration(seconds: 2));
        return;
      } on TimeoutException {
        // Fall through and close the FFI pipes if the engine did not exit.
      }
    }

    _cleanUp(0);
  }

  Future<bool> _start() async {
    if (_disposed) return false;

    if (Platform.isAndroid) {
      final engine = OfficialAndroidEngine();
      _officialAndroidEngine = engine;
      _stdoutSubscription.cancel();
      _stdoutSubscription = engine.stdout.listen(
        (line) {
          if (!_stdoutController.isClosed) {
            _stdoutController.sink.add(line);
          }
        },
        onError: (Object error) {
          prt('[pikafish] Official Android engine output error: $error');
          _cleanUp(1);
        },
        onDone: () => _cleanUp(0),
      );
      return engine.start(engineMode);
    }

    if (Platform.isWindows || Platform.isLinux) {
      final engine = OfficialDesktopEngine();
      _officialDesktopEngine = engine;
      _stdoutSubscription.cancel();
      _stdoutSubscription = engine.stdout.listen(
        (line) {
          if (!_stdoutController.isClosed) {
            _stdoutController.sink.add(line);
          }
        },
        onError: (Object error) {
          prt('[pikafish] Official desktop engine output error: $error');
          _cleanUp(1);
        },
        onDone: () => _cleanUp(0),
      );
      return engine.start(engineMode);
    }

    if (Platform.isMacOS || Platform.isIOS) {
      final startResult = nativeStartThreaded();
      if (startResult != 0) {
        prt('[pikafish] nativeStartThreaded result=$startResult');
        return false;
      }

      _threadedNativeEngine = true;
      _startNativeStdoutPolling();
      return true;
    }

    final success = await compute(
      _spawnIsolates,
      [_mainPort.sendPort, _stdoutPort.sendPort],
    );
    if (_disposed && success) {
      nativeShutdown();
      return false;
    }

    return success;
  }

  void _startNativeStdoutPolling() {
    _nativeStdoutTimer?.cancel();
    _nativeStdoutTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        if (_cleanedUp) return;

        _drainNativeStdout();

        if (nativeIsRunning() == 0) {
          _drainNativeStdout();
          _cleanUp(nativeExitCode());
        }
      },
    );
  }

  void _drainNativeStdout() {
    while (!_stdoutController.isClosed) {
      final pointer = nativeStdoutTryRead();
      if (pointer.address == 0) return;

      final chunk = const Utf8Decoder(allowMalformed: true).convert(
        _readNativeBytes(pointer),
      );
      final data = _nativeStdoutRemainder + chunk;
      final lines = data.split('\n');
      _nativeStdoutRemainder = lines.removeLast();

      for (final line in lines) {
        if (!_stdoutController.isClosed) {
          _stdoutController.sink.add(line);
        }
      }
    }
  }
}

/// Creates a C++ engine asynchronously.
///
/// This method is different from the factory method [Pikafish.new] that
/// it will wait for the engine to be ready before returning the instance.
Future<Pikafish> pikafishAsync({
  PikafishEngineMode engineMode = PikafishEngineMode.auto,
}) {
  //
  if (Pikafish._instance != null) {
    return Future.error(StateError('Only one instance can be used at a time'));
  }

  final completer = Completer<Pikafish>();
  Pikafish._instance = Pikafish._(
    completer: completer,
    engineMode: engineMode,
  );

  return completer.future;
}

class _PikafishState extends ChangeNotifier
    implements ValueListenable<PikafishState> {
  //
  PikafishState _value = PikafishState.starting;

  @override
  PikafishState get value => _value;

  _setValue(PikafishState v) {
    if (v == _value) return;
    _value = v;
    notifyListeners();
  }
}

void _isolateMain(SendPort mainPort) async {
  await _allowIsolateDebugCheckIn();

  final exitCode = nativeMain();
  mainPort.send(exitCode);

  prt('[pikafish] nativeMain returns $exitCode');
}

void _isolateStdout(SendPort stdoutPort) async {
  await _allowIsolateDebugCheckIn();

  final lineSink = _PikafishStdoutLineSink(stdoutPort);
  final decoder =
      const Utf8Decoder(allowMalformed: true).startChunkedConversion(lineSink);

  while (true) {
    try {
      //
      final pointer = nativeStdoutRead();

      if (pointer.address == 0) {
        prt('[pikafish] nativeStdoutRead returns NULL');
        decoder.close();
        return;
      }

      decoder.add(_readNativeBytes(pointer));
    } catch (e) {
      prt('[pikafish] The stdout isolate encountered an error $e');
    }
  }
}

Uint8List _readNativeBytes(Pointer<Utf8> pointer) {
  final bytePointer = pointer.cast<Uint8>();
  var length = 0;
  while (bytePointer[length] != 0) {
    length++;
  }
  return Uint8List.fromList(bytePointer.asTypedList(length));
}

class _PikafishStdoutLineSink extends StringConversionSinkBase {
  _PikafishStdoutLineSink(this.stdoutPort);

  final SendPort stdoutPort;
  String _previous = '';

  @override
  void addSlice(String chunk, int start, int end, bool isLast) {
    final data = _previous + chunk.substring(start, end);
    final lines = data.split('\n');
    _previous = lines.removeLast();

    for (final line in lines) {
      stdoutPort.send(line);
    }

    if (isLast) {
      close();
    }
  }

  @override
  void close() {
    if (_previous.isNotEmpty) {
      stdoutPort.send(_previous);
      _previous = '';
    }
  }
}

Future<bool> _spawnIsolates(List<SendPort> mainAndStdout) async {
  //
  final initResult = nativeInit();

  if (initResult != 0) {
    prt('[pikafish] initResult=$initResult');
    return false;
  }

  try {
    await _spawnNativeIsolate(
      _isolateStdout,
      mainAndStdout[1],
      'pikafish_stdout',
    );
  } catch (error) {
    prt('[pikafish] Failed to spawn stdout isolate: $error');
    return false;
  }

  try {
    await _spawnNativeIsolate(
      _isolateMain,
      mainAndStdout[0],
      'pikafish_main',
    );
  } catch (error) {
    prt('[pikafish] Failed to spawn main isolate: $error');
    return false;
  }

  return true;
}

Future<void> _spawnNativeIsolate(
  void Function(SendPort) entryPoint,
  SendPort port,
  String debugName,
) async {
  final isolate = await Isolate.spawn(
    entryPoint,
    port,
    debugName: debugName,
    paused: kDebugMode,
  );

  if (kDebugMode) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    isolate.resume(isolate.pauseCapability!);
  }
}

Future<void> _allowIsolateDebugCheckIn() {
  return Future<void>.delayed(
    kDebugMode ? const Duration(milliseconds: 100) : Duration.zero,
  );
}

void prt(String message) {
  if (kDebugMode) {
    developer.log(message, name: 'pikafish_engine');
  }
}
