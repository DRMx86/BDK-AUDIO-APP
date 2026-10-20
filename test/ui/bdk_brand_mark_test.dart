import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdk_audio/features/startup/bdk_brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('musical cue has a note head, tall stem and curved flag', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: BdkBrandMark()));
    final pixels = await _paintMark(tester);
    // These points distinguish an eighth note from the rejected straight bar.
    expect(_alpha(pixels, 5, 63), greaterThan(200)); // oval head
    expect(_alpha(pixels, 17, 40), greaterThan(200)); // stem
    expect(_alpha(pixels, 23, 35), greaterThan(200)); // curved flag
    expect(_alpha(pixels, 10, 40), 0); // open space beside the stem
    expect(_alpha(pixels, 32, 50), greaterThan(200)); // B remains primary
    expect(_alpha(pixels, 54, 36), 0); // upper letter counter stays open
    expect(find.bySemanticsLabel('BDK Audio musical B'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('drawing the musical cue leaves the B intact', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BdkBrandMark(noteProgress: 0)),
    );
    final pixels = await _paintMark(tester);
    expect(_alpha(pixels, 5, 63), 0);
    expect(_alpha(pixels, 17, 40), 0);
    expect(_alpha(pixels, 32, 50), greaterThan(200));
    expect(find.byType(Image), findsNothing);
  });
}

Future<ByteData> _paintMark(WidgetTester tester) async {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(BdkBrandMark),
      matching: find.byType(CustomPaint),
    ),
  );
  final recorder = ui.PictureRecorder();
  paint.painter!.paint(Canvas(recorder), const Size(100, 100));
  final picture = recorder.endRecording();
  final raster = (await tester.runAsync(() => picture.toImage(100, 100)))!;
  final bytes = (await tester.runAsync(
    () => raster.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  raster.dispose();
  picture.dispose();
  return bytes;
}

int _alpha(ByteData pixels, int x, int y) =>
    pixels.getUint8((y * 100 + x) * 4 + 3);
