import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:bdk_led_engine/bdk_led_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NativeLedEngine engine() => NativeLedEngine(
    library: DynamicLibrary.open(
      Platform.environment['BDK_LED_LIBRARY'] ??
          '${Directory.current.path}/build/native_renderer/Release/bdk_led_engine.dll',
    ),
  );
  test(
    'float fields own their copies across reuse and renderer disposal',
    () {
      final renderer = engine();
      final source = Uint8List(1024);
      for (var i = 0; i < 1024; i += 4) {
        source[i] = 31;
        source[i + 3] = 255;
      }
      final first = renderer.lightFields(source, 1.5);
      final saved = Float32List.fromList(first.core);
      final center = (128 * 256 + 128) * 4;
      expect(first.core[center], closeTo(31 / 255, .00001));
      source.fillRange(0, 1024, 0);
      final second = renderer.lightFields(source, 2);
      expect(second.core[center], 0);
      expect(
        () => renderer.lightFields(source, double.nan),
        throwsArgumentError,
      );
      expect(() => renderer.lightFields(Uint8List(1), 1), throwsArgumentError);
      renderer.dispose();
      renderer.dispose();
      expect(first.core, orderedEquals(saved));
      expect(() => renderer.lightFields(source, 1), throwsStateError);
    },
    skip: !Platform.isWindows,
  );
  test(
    'Dart calls actual firmware pulse and disposal is safe',
    () {
      final renderer = engine();
      renderer.configure([1, 100, 50, 255, 128, 0, 0, 128, 255, 0]);
      final frame = renderer.render(
        audio: [.7, .4, .2, -18, -24, -30, .7],
        beat: true,
        audioActive: true,
      );
      expect(frame.length, 1024);
      for (var i = 0; i < frame.length; i += 4) {
        expect(frame.sublist(i, i + 4), [254, 195, 21, 255]);
      }
      renderer.dispose();
      renderer.dispose();
      expect(() => renderer.render(), throwsStateError);
    },
    skip: !Platform.isWindows,
  );
  test(
    'copied frames are stable and short audio is rejected',
    () {
      final renderer = engine();
      addTearDown(renderer.dispose);
      renderer.configure([21, 70, 50, 255, 128, 0, 0, 128, 255, 1]);
      final first = renderer.render(demo: true), copy = List<int>.of(first);
      renderer.render(demo: true);
      expect(first, copy);
      expect(() => renderer.render(audio: [1]), throwsArgumentError);
      expect(() => renderer.configure([0]), throwsArgumentError);
    },
    skip: !Platform.isWindows,
  );
  test(
    'Off ID255 stays black for demo and audio and can resume Ambient',
    () {
      final renderer = engine();
      addTearDown(renderer.dispose);
      renderer.configure([255, 70, 50, 255, 128, 0, 0, 128, 255, 1]);
      for (final demo in [true, false]) {
        final frame = renderer.render(
          demo: demo,
          audio: [1, 1, 1, 0, 0, 0, 1],
          beat: true,
          audioActive: true,
        );
        for (var i = 0; i < frame.length; i += 4) {
          expect(frame.sublist(i, i + 4), [0, 0, 0, 255]);
        }
      }
      expect(
        () => renderer.configure([255, 101, 50, 255, 128, 0, 0, 128, 255, 1]),
        throwsArgumentError,
      );
      renderer.configure([21, 70, 50, 255, 128, 0, 0, 128, 255, 1]);
      final resumed = renderer.render(demo: true);
      expect(
        [
          for (var i = 0; i < resumed.length; i++)
            if (i % 4 != 3) resumed[i],
        ].any((value) => value > 0),
        isTrue,
      );
    },
    skip: !Platform.isWindows,
  );
}
