import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:bdk_audio/features/light/light_diffusion.dart';
import 'package:bdk_led_engine/bdk_led_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a backend without float GPU targets retains continuous CPU fields',
    (tester) async {
      expect(ui.ImageFilter.isShaderFilterSupported, isFalse);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      final source = await tester.runAsync(() => picture.toImage(16, 16));
      picture.dispose();
      final program = await tester.runAsync(LedDiffusion.load);
      final shader = program!.fragmentShader();
      var fieldsBuilt = 0;
      NativeLightFields fallback(Uint8List pixels, double sigma) {
        fieldsBuilt++;
        return NativeLightFields(core: Float32List(4), halo: Float32List(4));
      }

      Future<ui.Image> decode(
        Float32List pixels,
        int width,
        int height,
      ) async => source!.clone();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 345,
            height: 300,
            child: FirmwareLightView(
              image: source,
              pixels: Uint8List(1024),
              shader: shader,
              gpuProgram: program,
              fieldBuilder: fallback,
              decoder: decode,
              paintKey: const ValueKey('fallback'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(fieldsBuilt, 1);
      expect(tester.takeException(), isNull);
      final painter =
          tester
                  .widget<CustomPaint>(find.byKey(const ValueKey('fallback')))
                  .painter!
              as FirmwareLightPainter;
      expect(painter.coreField, isNotNull);
      await tester.pumpWidget(const SizedBox());
      source!.dispose();
      shader.dispose();
    },
    skip: ui.ImageFilter.isShaderFilterSupported,
  );
}
