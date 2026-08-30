# flutter_pikafish
The Flutter plugin for PIKAFISH (base on Stockfish), A well-known Chinese chess open source engine.

## Branch scope

The `plus` branch is mobile-only and registers Android and iOS only. Keep the
official prebuilt `libpikafish_armv8_exec.so` and
`libpikafish_dotprod_exec.so` binaries unchanged on this branch. Desktop
support belongs to the dedicated `desktop` branch, and Android 16 KiB
page-size work belongs to its dedicated branch.

# Usages 

iOS project must have IPHONEOS_DEPLOYMENT_TARGET >=11.0.

Add dependency 

Update dependencies section inside pubspec.yaml:

``` yaml
  flutter_pikafish: ^<last-version>
```

Init engine

``` dart
import 'package:pikafish_engine/pikafish_engine.dart';

// Android automatically selects the official DotProd or ARMv8 executable.
// Other platforms continue to use FFI.
final pikafish = Pikafish();

// A backend can also be selected explicitly:
// Pikafish(engineMode: PikafishEngineMode.officialArmv8);
// Pikafish(engineMode: PikafishEngineMode.officialDotProd);
// iOS always uses the bundled FFI engine.

// state is a ValueListenable<PikafishState>
print(pikafish.state.value); # PikafishState.starting

// the engine takes a few moment to start
await Future.delayed(...)
print(pikafish.state.value); # PikafishState.ready
```

## Android packaging requirement

The official Android Pikafish files are standalone executables, even though
they use the `.so` extension so they can be bundled as native libraries.
They are launched with `ProcessBuilder`, rather than loaded with
`System.loadLibrary`.

The consuming Android application must enable legacy native library packaging.
This makes Android extract the bundled engine files into `nativeLibraryDir`
with executable permissions. This setting must be added to the consuming
application because the plugin's own Gradle configuration cannot enable it for
the final APK.

Add the following to `android/app/build.gradle.kts`:

```kotlin
android {
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}
```

Groovy `build.gradle` equivalent:

```groovy
android {
    packagingOptions {
        jniLibs {
            useLegacyPackaging true
        }
    }
}
```

After changing this setting, run `flutter clean` and reinstall the application.
Without it, engine startup fails with an error similar to:

```text
PlatformException(not_executable, Bundled engine is not executable: .../libpikafish_dotprod_exec.so)
```

UCI command 

Waits until the state is ready before sending commands.

``` dart
pikafish.stdin = 'isready';
pikafish.stdin = 'go movetime 3000';
pikafish.stdin = 'go infinite';
pikafish.stdin = 'stop';
```

Engine output is directed to a Stream<String>, add a listener to process results.

``` dart
pikafish.stdout.listen((line) {
  // do something useful
  print(line);
});
```

Dispose / Hot reload 

There are two active isolates when Pikafish engine is running.
That interferes with Flutter's hot reload feature so you need to dispose it before attempting to reload.

``` dart
// sends the UCI quit command
pikafish.stdin = 'quit';

// or even easier...
pikafish.dispose();
```

Note: only one instance can be created at a time.
The factory method Pikafish() will return null if it was called when an existing instance is active.
