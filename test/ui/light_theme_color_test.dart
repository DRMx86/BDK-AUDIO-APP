import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:bdk_audio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _ColorFrames implements LightFrameRenderer {
  _ColorFrames(this.red);
  final bool red;
  @override
  void configure(List<int> payload) {}
  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) {
    final pixels = Uint8List(1024);
    for (var pixel = 0; pixel < 256; pixel++) {
      pixels[pixel * 4 + (red ? 0 : 2)] = 64;
      pixels[pixel * 4 + 3] = 255;
    }
    return pixels;
  }

  @override
  void dispose() {}
}

void main() {
  for (final gallery in [false, true]) {
    testWidgets(
      'Light theme preserves ${gallery ? 'effect tile' : 'main preview'} color changes',
      (tester) async {
        tester.view.physicalSize = const Size(420, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Future<double> colorDifference(bool red) async {
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: bdkTheme(Brightness.light),
                home: Scaffold(
                  body: MediaQuery(
                    data: const MediaQueryData(disableAnimations: true),
                    child: LightScreen(
                      key: ValueKey(red),
                      settings: const LedSettings(effect: 0, brightness: 70),
                      onChanged: (_) {},
                      rendererFactory: () => _ColorFrames(red),
                    ),
                  ),
                ),
              ),
            ),
          );
          for (var i = 0; i < 5; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          if (gallery) {
            await tester.scrollUntilVisible(find.text('Choose an effect'), 150);
            await tester.ensureVisible(find.text('Choose an effect'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Choose an effect'));
            for (var i = 0; i < 30; i++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await tester.pump();
            }
          }
          final target = find.byKey(
            ValueKey(gallery ? 'effect-1' : 'led-artwork'),
          );
          final rect = tester.getRect(target);
          final box =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final result = await tester.runAsync(() async {
            final image = await box.toImage(pixelRatio: 1);
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            var sum = 0, count = 0;
            // Interior only; white labels/icons contribute equally to R and B.
            for (
              var y = rect.top.toInt() + 20;
              y < rect.bottom.toInt() - 20;
              y++
            ) {
              for (
                var x = rect.left.toInt() + 20;
                x < rect.right.toInt() - 20;
                x++
              ) {
                final offset = (y * image.width + x) * 4;
                sum += data.getUint8(offset) - data.getUint8(offset + 2);
                count++;
              }
            }
            image.dispose();
            return sum / count;
          });
          expect(tester.takeException(), isNull);
          return result!;
        }

        final red = await colorDifference(true);
        final blue = await colorDifference(false);
        expect(
          red,
          greaterThan(gallery ? 5 : 25),
          reason: 'Red must remain visible, observed $red',
        );
        expect(
          blue,
          lessThan(gallery ? -5 : -25),
          reason: 'Blue must remain visible, observed $blue',
        );
      },
    );
  }
}
