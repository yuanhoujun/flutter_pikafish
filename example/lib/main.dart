import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pikafish_engine/pikafish_engine.dart';

import 'src/output_widget.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<StatefulWidget> createState() => _AppState();
}

class _AppState extends State<MyApp> {
  late Pikafish pikafish;

  @override
  void initState() {
    super.initState();
    pikafish = Pikafish();
    pikafish.state.addListener(_setupNnueWhenReady);
  }

  @override
  void dispose() {
    pikafish.state.removeListener(_setupNnueWhenReady);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var commands = [
      'd',
      'isready',
      'go infinite',
      'go movetime 3000',
      'stop',
      'quit',
    ];
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Pikafish example app')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: AnimatedBuilder(
                animation: pikafish.state,
                builder: (_, __) => Text(
                  'pikafish.state=${pikafish.state.value}',
                  key: const ValueKey('pikafish.state'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: AnimatedBuilder(
                animation: pikafish.state,
                builder: (_, __) => ElevatedButton(
                  onPressed: pikafish.state.value == PikafishState.disposed
                      ? () {
                          final newInstance = Pikafish();
                          setState(() => pikafish = newInstance);
                        }
                      : null,
                  child: const Text('Reset Pikafish instance'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Custom UCI command',
                  hintText: 'go infinite',
                ),
                onSubmitted: (value) => pikafish.stdin = value,
                textInputAction: TextInputAction.send,
              ),
            ),
            ElevatedButton(
              onPressed: setupNnue,
              child: const Text('Set NNUE file'),
            ),
            Wrap(
              children: commands
                  .map(
                    (command) => Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton(
                        onPressed: () => pikafish.stdin = command,
                        child: Text(command),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            Expanded(child: OutputWidget(pikafish.stdout)),
          ],
        ),
      ),
    );
  }

  void setupNnue() async {
    await _setupNnue();
  }

  void _setupNnueWhenReady() {
    if (pikafish.state.value != PikafishState.ready) return;
    pikafish.state.removeListener(_setupNnueWhenReady);
    _setupNnue(pingReady: true);
  }

  Future<void> _setupNnue({bool pingReady = false}) async {
    //
    final appDocDir = await getApplicationDocumentsDirectory();
    final nnueFile = File('${appDocDir.path}/pikafish.nnue');
    final assetBytes = await rootBundle.load('assets/pikafish.nnue');
    final assetData = assetBytes.buffer.asUint8List();
    final assetMd5 = md5.convert(assetData).toString();

    if (!(await nnueFile.exists()) || await md5Sum(nnueFile) != assetMd5) {
      await nnueFile.create(recursive: true);
      await nnueFile.writeAsBytes(assetData, flush: true);
    }

    prt(await md5Sum(nnueFile) ?? "");

    pikafish.stdin = 'setoption name EvalFile value ${nnueFile.path}';
    if (pingReady) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      pikafish.stdin = 'isready';
      await Future<void>.delayed(const Duration(milliseconds: 300));
      pikafish.stdin = 'go movetime 300';
    }
  }
}

Future<String?> md5Sum(File file) async {
  if (!file.existsSync()) return null;

  try {
    final bytes = await file.readAsBytes();
    final digest = md5.convert(bytes);
    return digest.toString();
  } catch (e) {
    return null;
  }
}
