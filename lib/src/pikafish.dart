import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

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

  StreamSubscription<String>? _stdoutSubscription;
  final _exitCompleter = Completer<void>();
  bool _cleanedUp = false;
  OfficialAndroidEngine? _officialAndroidEngine;
  OfficialDesktopEngine? _officialDesktopEngine;
  bool _disposed = false;
  bool _threadedNativeEngine = false;
  Timer? _nativeStdoutTimer;
  String _nativeStdoutRemainder = '';

  Pikafish._({this.completer, required this.engineMode}) {
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

        prt('[pikafish] Engine initialization encountered an error $error');
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

  /// Requests an immediate engine shutdown without waiting for cleanup.
  ///
  /// Desktop process engines are terminated after receiving `quit`. Embedded
  /// engines only receive `quit`; the host process will exit immediately after
  /// this call.
  void terminateImmediately() {
    _disposed = true;

    final androidEngine = _officialAndroidEngine;
    if (androidEngine != null) {
      unawaited(androidEngine.terminateImmediately());
      return;
    }

    final desktopEngine = _officialDesktopEngine;
    if (desktopEngine != null) {
      desktopEngine.terminateImmediately();
      return;
    }

    if (_state.value == PikafishState.ready) {
      try {
        stdin = 'quit';
      } on Object {
        // The host application is exiting, so notification is best effort.
      }
    }
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
      await desktopEngine.dispose(timeout: timeout);
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

    _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

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
      _stdoutSubscription?.cancel();
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
      _stdoutSubscription?.cancel();
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

    prt('[pikafish] Unsupported platform: ${Platform.operatingSystem}');
    return false;
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

      final chunk =
          utf8.decode(_readNativeBytes(pointer), allowMalformed: true);
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

Uint8List _readNativeBytes(Pointer<Utf8> pointer) {
  final bytePointer = pointer.cast<Uint8>();
  var length = 0;
  while (bytePointer[length] != 0) {
    length++;
  }
  return Uint8List.fromList(bytePointer.asTypedList(length));
}

void prt(String message) {
  if (kDebugMode) {
    developer.log(message, name: 'pikafish_engine');
  }
}
