import 'package:flutter/material.dart';
import 'package:bdk_led_engine/bdk_led_engine.dart';

void main() {
  final renderer = NativeLedEngine();
  renderer.configure([1, 100, 50, 255, 128, 0, 0, 128, 255, 0]);
  final frame = renderer.render(
    audio: [.7, .4, .2, -18, -24, -30, .7],
    beat: true,
    audioActive: true,
  );
  renderer.dispose();
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('BDK firmware renderer')),
        body: Center(
          child: Text(
            '16×16 RGBA: ${frame.length} bytes\nBeat Pulse pixel: ${frame.take(4).join(', ')}',
          ),
        ),
      ),
    ),
  );
}
