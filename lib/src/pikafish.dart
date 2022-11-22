import 'dart:async';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'ffi.dart';
import 'pikafish_state.dart';

/// A wrapper for C++ engine.
class Pikafish {
  //
  final Completer<Pikafish>? completer;

  final _state = _PikafishState();

  final _stdoutController = StreamController<String>.broadcast();

  final _mainPort = ReceivePort();
  final _stdoutPort = ReceivePort();

  late StreamSubscription _mainSubscription;
  late StreamSubscription _stdoutSubscription;

  Pikafish._({this.completer}) {
    //
    _mainSubscription = _mainPort.listen(
      (message) => _cleanUp(message is int ? message : 1),
    );

    _stdoutSubscription = _stdoutPort.listen(
      (message) {
        if (message is String) {
          _stdoutController.sink.add(message);
        } else {
          debugPrint('[pikafish] The stdout isolate sent $message');
        }
      },
    );

    compute(_spawnIsolates, [_mainPort.sendPort, _stdoutPort.sendPort]).then(
      (success) {
        //
        final state = success ? PikafishState.ready : PikafishState.error;
        _state._setValue(state);

        if (state == PikafishState.ready) {
          completer?.complete(this);
        }
      },
      onError: (error) {
        debugPrint('[pikafish] The init isolate encountered an error $error');
        _cleanUp(1);
      },
    );
  }

  static Pikafish? _instance;

  /// Creates a C++ engine.
  ///
  /// This may throws a [StateError] if an active instance is being used.
  /// Owner must [dispose] it before a new instance can be created.
  factory Pikafish() {
    //
    if (_instance != null) {
      throw StateError('Multiple instances are not supported, yet.');
    }

    _instance = Pikafish._();

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

    debugPrint('engine=< $line');

    final pointer = '$line\n'.toNativeUtf8();
    nativeStdinWrite(pointer);
    calloc.free(pointer);
  }

  /// Stops the C++ engine.
  void dispose() {
    stdin = 'quit';
  }

  void _cleanUp(int exitCode) {
    //
    _stdoutController.close();

    _mainSubscription.cancel();
    _stdoutSubscription.cancel();

    _state._setValue(
      exitCode == 0 ? PikafishState.disposed : PikafishState.error,
    );

    _instance = null;
  }
}

/// Creates a C++ engine asynchronously.
///
/// This method is different from the factory method [Pikafish.new] that
/// it will wait for the engine to be ready before returning the instance.
Future<Pikafish> pikafishAsync() {
  //
  if (Pikafish._instance != null) {
    return Future.error(StateError('Only one instance can be used at a time'));
  }

  final completer = Completer<Pikafish>();
  Pikafish._instance = Pikafish._(completer: completer);

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

  debugPrint('[pikafish] nativeMain returns $exitCode');
}

void _isolateStdout(SendPort stdoutPort) {
  //
  String previous = '';

  while (true) {
    //
    final pointer = nativeStdoutRead();

    if (pointer.address == 0) {
      debugPrint('[pikafish] nativeStdoutRead returns NULL');
      return;
    }

    final data = previous + pointer.toDartString();
    final lines = data.split('\n');

    previous = lines.removeLast();

    for (final line in lines) {
      stdoutPort.send(line);
    }
  }
}

Future<bool> _spawnIsolates(List<SendPort> mainAndStdout) async {
  //
  final initResult = nativeInit();

  if (initResult != 0) {
    debugPrint('[pikafish] initResult=$initResult');
    return false;
  }

  try {
    await Isolate.spawn(_isolateStdout, mainAndStdout[1]);
  } catch (error) {
    debugPrint('[pikafish] Failed to spawn stdout isolate: $error');
    return false;
  }

  try {
    await Isolate.spawn(_isolateMain, mainAndStdout[0]);
  } catch (error) {
    debugPrint('[pikafish] Failed to spawn main isolate: $error');
    return false;
  }

  return true;
}
