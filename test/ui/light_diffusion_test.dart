import 'dart:ui' as ui;
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('square light source diffuses smoothly into the wider card', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final sourceRecorder = ui.PictureRecorder();
      final sourceCanvas = Canvas(sourceRecorder);
      sourceCanvas.drawRect(
        const Rect.fromLTWH(0, 0, 16, 16),
        Paint()..color = const Color(0xff003000),
      );
      final sourcePicture = sourceRecorder.endRecording();
      final source = await sourcePicture.toImage(16, 16);
      sourcePicture.dispose();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.black, BlendMode.src);
      FirmwareLightPainter(image: source).paint(canvas, const Size(680, 300));
      final picture = recorder.endRecording();
      final image = await picture.toImage(680, 300);
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      int green(int x) => data.getUint8((150 * 680 + x) * 4 + 1);
      // A 16-cell source should never have a one-pixel rectangular cutoff.
      final jumps = <int>[
        for (var x = 175; x < 205; x++) (green(x + 1) - green(x)).abs(),
        for (var x = 475; x < 505; x++) (green(x + 1) - green(x)).abs(),
      ];
      expect(jumps.every((jump) => jump <= 6), isTrue, reason: '$jumps');
      expect(green(10), greaterThan(0), reason: 'Glow fills the card sides.');
      image.dispose();
      picture.dispose();
      source.dispose();
    });
  });
}
