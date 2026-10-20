import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bdk_audio/features/light/light_diffusion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _render(
  Color color, {
  double opacity = 1,
  bool shade = false,
  String pattern = 'uniform',
}) async {
  final sourceRecorder = ui.PictureRecorder();
  final sourceCanvas = Canvas(sourceRecorder)..drawColor(color, BlendMode.src);
  if (pattern == 'split') {
    sourceCanvas.drawRect(
      const Rect.fromLTWH(8, 0, 8, 16),
      Paint()..color = Colors.black,
    );
  } else if (pattern == 'single') {
    sourceCanvas.drawColor(Colors.black, BlendMode.src);
    sourceCanvas.drawRect(
      const Rect.fromLTWH(8, 8, 1, 1),
      Paint()..color = color,
    );
  }
  final sourcePicture = sourceRecorder.endRecording();
  final source = await sourcePicture.toImage(16, 16);
  sourcePicture.dispose();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawColor(const Color(0xff101010), BlendMode.src);
  final shader = (await LedDiffusion.load()).fragmentShader();
  FirmwareLightPainter(
    image: source,
    opacity: opacity,
    shader: shader,
    titleShade: shade,
    hasEmission: color != Colors.black && opacity > 0,
    uniformColor: pattern == 'uniform' ? color : null,
  ).paint(canvas, const Size(345, 300));
  final picture = recorder.endRecording();
  final result = await picture.toImage(345, 300);
  picture.dispose();
  shader.dispose();
  source.dispose();
  return result;
}

void main() {
  testWidgets('sparse dark margins retain a continuous matte gradient', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await _render(Colors.white, pattern: 'single', shade: true);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var maximumError = 0.0;
      for (var y = 110; y < 220; y++) {
        var sum = 0;
        for (var x = 10; x < 31; x++) {
          sum += bytes.getUint8((y * 345 + x) * 4 + 1);
        }
        final alpha = 153 * (1 - (((y + .5) / 300) - .35) / .4);
        final expected = 16 * (1 - alpha / 255);
        final error = (sum / 21 - expected).abs();
        if (error > maximumError) maximumError = error;
      }
      expect(maximumError, lessThan(.22));
      image.dispose();
    });
  });
  testWidgets(
    'dither preserves the continuous gradient mean instead of masking steps',
    (tester) async {
      await tester.runAsync(() async {
        final reference =
            jsonDecode(
                  await File(
                    'test/fixtures/led/uniform-dark-expected.json',
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        final expected = (reference['row_means'] as List).cast<num>();
        final image = await _render(const Color(0xff141414), shade: true);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var maximumError = 0.0;
        for (var y = 110; y < 220; y++) {
          var sum = 0;
          for (var x = 120; x < 225; x++) {
            sum += bytes.getUint8((y * 345 + x) * 4 + 1);
          }
          final error = (sum / 105 - expected[y - 110]).abs();
          if (error > maximumError) maximumError = error;
        }
        expect(
          maximumError,
          lessThan(.22),
          reason:
              'Grain added after quantization leaves the stepped mean. Observed error $maximumError RGB levels.',
        );
        image.dispose();
      });
    },
  );
  testWidgets('nonuniform source diffuses without cell-sized steps', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await _render(const Color(0xff808080), pattern: 'split');
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var maximum = 0;
      for (var x = 100; x < 240; x++) {
        final jump =
            (bytes.getUint8((150 * 345 + x + 1) * 4 + 1) -
                    bytes.getUint8((150 * 345 + x) * 4 + 1))
                .abs();
        if (jump > maximum) maximum = jump;
      }
      expect(
        maximum,
        lessThanOrEqualTo(8),
        reason:
            'A smooth source edge must not jump at each LED cell. Observed $maximum.',
      );
      image.dispose();
    });
  });

  testWidgets('an isolated source cell has one halo without repeated lobes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await _render(Colors.white, pattern: 'single');
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      double average(int center) {
        var sum = 0;
        for (var x = center - 3; x <= center + 3; x++) {
          sum += bytes.getUint8((160 * 345 + x) * 4 + 1);
        }
        return sum / 7;
      }

      expect(
        average(212),
        greaterThanOrEqualTo(average(236) - 1),
        reason:
            'Light must fade away from its source, not create a second halo.',
      );
      image.dispose();
    });
  });
  testWidgets('dark diffusion has no broad flat contour bands', (tester) async {
    await tester.runAsync(() async {
      final image = await _render(const Color(0xff141414), shade: true);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      if (const bool.fromEnvironment('BDK_CAPTURE_GRADIENT')) {
        await File(
          '${Directory.systemTemp.path}/bdk-gradient-quality.png',
        ).writeAsBytes(png.buffer.asUint8List());
      }
      var longest = 0, run = 0, last = -1;
      for (var y = 110; y < 220; y++) {
        final value = bytes.getUint8((y * 345 + 172) * 4 + 1);
        run = value == last ? run + 1 : 1;
        if (run > longest) longest = run;
        last = value;
      }
      expect(
        longest,
        lessThanOrEqualTo(3),
        reason:
            'Wide quantized plateaus create visible contour bands. Observed $longest pixels.',
      );
      image.dispose();
    });
  });

  testWidgets('black source and zero opacity add no synthetic light', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final entry in [(Colors.black, 1.0), (Colors.white, 0.0)]) {
        final image = await _render(entry.$1, opacity: entry.$2);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var dark = true;
        for (var offset = 0; offset < bytes.lengthInBytes; offset += 4) {
          dark &=
              bytes.getUint8(offset) == 16 &&
              bytes.getUint8(offset + 1) == 16 &&
              bytes.getUint8(offset + 2) == 16;
        }
        expect(dark, isTrue);
        image.dispose();
      }
    });
  });
}
