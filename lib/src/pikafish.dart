import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'ffi.dart';
import 'official_android_engine.dart';
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

    prt('engine=< $line');

    final officialEngine = _officialAndroidEngine;
    if (officialEngine != null) {
      officialEngine.write(line);
    } else {
      final pointer = '$line\n'.toNativeUtf8();
      nativeStdinWrite(pointer);
      calloc.free(pointer);
    }
  }

  /// Restarts the engine and returns the new ready instance.
  ///
  /// The current Android engine variant is preserved unless [engineMode] is
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
    if (_state.value == PikafishState.ready) {
      stdin = 'quit';
    } else {
      _cleanUp(0);
    }
  }

  void _cleanUp(int exitCode) {
    if (_cleanedUp) return;
    _cleanedUp = true;

    final officialEngine = _officialAndroidEngine;
    if (officialEngine != null) {
      officialEngine.dispose();
    } else {
      nativeShutdown();
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

    return compute(_spawnIsolates, [_mainPort.sendPort, _stdoutPort.sendPort]);
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

void _isolateMain(SendPort mainPort) {
  //
  final exitCode = nativeMain();
  mainPort.send(exitCode);

  prt('[pikafish] nativeMain returns $exitCode');
}

void _isolateStdout(SendPort stdoutPort) {
  //
  String previous = '';

  while (true) {
    try {
      //
      final pointer = nativeStdoutRead();

      if (pointer.address == 0) {
        prt('[pikafish] nativeStdoutRead returns NULL');
        return;
      }

      final data = previous + pointer.toDartString();
      final lines = data.split('\n');

      previous = lines.removeLast();

      for (final line in lines) {
        stdoutPort.send(line);
      }
    } catch (e) {
      prt('[pikafish] The stdout isolate encountered an error $e');
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
    await Isolate.spawn(_isolateStdout, mainAndStdout[1]);
  } catch (error) {
    prt('[pikafish] Failed to spawn stdout isolate: $error');
    return false;
  }

  try {
    await Isolate.spawn(_isolateMain, mainAndStdout[0]);
  } catch (error) {
    prt('[pikafish] Failed to spawn main isolate: $error');
    return false;
  }

  return true;
}

void prt(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
