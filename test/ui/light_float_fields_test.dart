import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdk_audio/features/light/light_diffusion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Independent separable Gaussian fixture, retaining fractional light levels.
Float32List _field(int width, double start, double end, double sigma) {
  final data = Float32List(width * width * 4);
  for (var y = 0; y < width; y++) {
    final py = start + y * (end - start) / (width - 1);
    for (var x = 0; x < width; x++) {
      final px = start + x * (end - start) / (width - 1);
      var horizontal = 0.0, vertical = 0.0;
      for (var i = 0; i < 16; i++) {
        final dx = (px - i - .5) / sigma;
        final dy = (py - i - .5) / sigma;
        if (i < 8) horizontal += math.exp(-.5 * dx * dx);
        vertical += math.exp(-.5 * dy * dy);
      }
      final value =
          (128 / 255) * horizontal * vertical / (2 * math.pi * sigma * sigma);
      final offset = (y * width + x) * 4;
      data[offset] = data[offset + 1] = data[offset + 2] = value;
      data[offset + 3] = 1;
    }
  }
  return data;
}

void main() {
  testWidgets('light fields keep fractional values through texture decoding', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final values = Float32List.fromList([.12345, .23456, .34567, 1]);
      final image = await decodeLightField(values, 1, 1);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawExtendedRgba128,
      ))!;
      for (var i = 0; i < 4; i++) {
        expect(
          bytes.getFloat32(i * 4, Endian.host),
          closeTo(values[i], .00001),
        );
      }
      image.dispose();
    });
  });

  testWidgets('cached float fields match continuous source reconstruction', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final pixels = Uint8List(1024);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final offset = (y * 16 + x) * 4;
          pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = x < 8
              ? 128
              : 0;
          pixels[offset + 3] = 255;
        }
      }
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        16,
        16,
        ui.PixelFormat.rgba8888,
        decoded.complete,
      );
      final source = await decoded.future;
      final core = await decodeLightField(_field(256, -4, 20, .8), 256, 256);
      final halo = await decodeLightField(
        _field(128, 0, 16, 640 / 345),
        128,
        128,
      );
      final program = await LedDiffusion.load();
      Future<ByteData> paint(bool cached) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final shader = program.fragmentShader();
        FirmwareLightPainter(
          image: source,
          shader: shader,
          coreField: cached ? core : null,
          haloField: cached ? halo : null,
          titleShade: true,
        ).paint(canvas, const Size(345, 300));
        final picture = recorder.endRecording();
        final image = await picture.toImage(345, 300);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        image.dispose();
        picture.dispose();
        shader.dispose();
        return data;
      }

      final direct = await paint(false), cached = await paint(true);
      var maximum = 0, total = 0;
      for (var y = 0; y < 300; y++) {
        for (var x = 0; x < 345; x++) {
          final offset = (y * 345 + x) * 4;
          final difference = (direct.getUint8(offset) - cached.getUint8(offset))
              .abs();
          maximum = math.max(maximum, difference);
          total += difference;
        }
      }
      expect(maximum, lessThanOrEqualTo(1));
      expect(total / (345 * 300), lessThan(.08));
      source.dispose();
      core.dispose();
      halo.dispose();
    });
  });
}
