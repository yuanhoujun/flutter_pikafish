import 'dart:io';

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
    //
    final appDocDir = await getApplicationDocumentsDirectory();
    final nnueFile = File('${appDocDir.path}/pikafish.nnue');

    if (!(await nnueFile.exists())) {
      await nnueFile.create(recursive: true);
      final bytes = await rootBundle.load('assets/pikafish.nnue');
      await nnueFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    }

    pikafish.stdin = 'setoption name EvalFile value ${nnueFile.path}';
  }
}
