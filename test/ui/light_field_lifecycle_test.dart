import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdk_audio/features/light/light_diffusion.dart';
import 'package:bdk_led_engine/bdk_led_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'new source frames coalesce while float textures decode without starving playback',
    (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      final source = await tester.runAsync(() => picture.toImage(16, 16));
      picture.dispose();
      final program = await tester.runAsync(LedDiffusion.load);
      final shader = program!.fragmentShader();
      final requests = <int>[];
      final pending = <Completer<ui.Image>>[];
      final images = <ui.Image>[];
      final data = NativeLightFields(
        core: Float32List(4),
        halo: Float32List(4),
      );
      NativeLightFields fields(Uint8List pixels, double sigma) {
        requests.add(pixels.first);
        return data;
      }

      Future<ui.Image> decoder(Float32List pixels, int width, int height) {
        final completer = Completer<ui.Image>();
        pending.add(completer);
        return completer.future;
      }

      Future<void> mount(int value) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 345,
                height: 300,
                child: FirmwareLightView(
                  image: source,
                  pixels: Uint8List.fromList([value]),
                  shader: shader,
                  fieldBuilder: fields,
                  decoder: decoder,
                  paintKey: const ValueKey('field-paint'),
                ),
              ),
            ),
          ),
        );
      }

      void complete(int offset) {
        for (var i = offset; i < offset + 2; i++) {
          final clone = source!.clone();
          images.add(clone);
          pending[i].complete(clone);
        }
      }

      await mount(1);
      await mount(2);
      await mount(3);
      expect(requests, [1]);
      complete(0);
      await tester.pump();
      await tester.pump();
      expect(requests, [1, 3]);
      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('field-paint')),
      );
      expect(
        (paint.painter! as FirmwareLightPainter).coreField,
        same(images.first),
      );
      await tester.pumpWidget(const SizedBox());
      complete(2);
      await tester.pump();
      await tester.pump();
      expect(images.every((image) => image.debugDisposed), isTrue);
      source!.dispose();
      shader.dispose();
    },
  );
  testWidgets(
    'unsupported field construction falls back without a build exception or retry loop',
    (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      final source = await tester.runAsync(() => picture.toImage(16, 16));
      picture.dispose();
      final program = await tester.runAsync(LedDiffusion.load);
      final shader = program!.fragmentShader();
      var requests = 0;
      NativeLightFields unsupported(Uint8List pixels, double sigma) {
        requests++;
        throw UnsupportedError('No float fields');
      }

      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 345,
                height: 300,
                child: FirmwareLightView(
                  image: source,
                  pixels: Uint8List(1024),
                  shader: shader,
                  fieldBuilder: unsupported,
                  paintKey: const ValueKey('field-paint'),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
      expect(requests, 1);
      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('field-paint')),
      );
      expect((paint.painter! as FirmwareLightPainter).coreField, isNull);
      await tester.pumpWidget(const SizedBox());
      source!.dispose();
      shader.dispose();
    },
  );
}
