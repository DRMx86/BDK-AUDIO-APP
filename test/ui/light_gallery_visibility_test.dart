import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:bdk_audio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordedFrames implements LightFrameRenderer {
  _RecordedFrames(this.frames);
  final Map<int, Uint8List> frames;
  var effect = 0;
  @override
  void configure(List<int> payload) => effect = payload.first;
  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) => frames[effect] ?? (Uint8List(1024)..fillRange(0, 1024, 255));
  @override
  void dispose() {}
}

void main() {
  for (final theme in Brightness.values) {
    testWidgets('gallery retains sparse native color and readable labels in '
        '${theme.name} theme', (tester) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final frames = <int, Uint8List>{};
      await tester.runAsync(() async {
        for (final effect in [1, 3, 11, 15]) {
          frames[effect] = await File(
            'test/fixtures/led/effect-${effect.toString().padLeft(2, '0')}.rgba',
          ).readAsBytes();
          expect(frames[effect], hasLength(1024));
        }
        for (final family in ['Manrope', 'SpaceGrotesk']) {
          await (FontLoader(
            family,
          )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
        }
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: bdkTheme(theme),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: LightScreen(
                  settings: const LedSettings(effect: 15),
                  onChanged: (_) {},
                  rendererFactory: () => _RecordedFrames(frames),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> decodeFrames(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
      }

      await decodeFrames(5);
      await tester.scrollUntilVisible(find.text('Choose an effect'), 150);
      await tester.ensureVisible(find.text('Choose an effect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose an effect'));
      await decodeFrames(30);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      Future<(ByteData, int)> capture(String name) async {
        final image = await boundary.toImage(pixelRatio: 1);
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final width = image.width;
        if (const bool.fromEnvironment('EXPORT_GALLERY_ARTIFACTS')) {
          final directory = Directory('artifacts/gallery-visibility')
            ..createSync(recursive: true);
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          File(
            '${directory.path}/${theme.name}-$name.png',
          ).writeAsBytesSync(png.buffer.asUint8List());
        }
        image.dispose();
        return (pixels, width);
      }

      double worstContrast(ByteData data, int width, Rect rect, Color ink) {
        var result = double.infinity;
        final inkLuminance = ink.computeLuminance();
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
          for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
            final i = (y * width + x) * 4;
            final luminance = Color.fromARGB(
              255,
              data.getUint8(i),
              data.getUint8(i + 1),
              data.getUint8(i + 2),
            ).computeLuminance();
            result = math.min(
              result,
              (math.max(inkLuminance, luminance) + .05) /
                  (math.min(inkLuminance, luminance) + .05),
            );
          }
        }
        return result;
      }

      // Sparse native Meteor pixels must survive the thumbnail treatment.
      // Sample a blank band below the icon and above the title, avoiding the
      // cyan selection border, check, glyphs and their antialiasing entirely.
      final meteor = find.byKey(const ValueKey('effect-15'));
      await tester.ensureVisible(meteor);
      await tester.pumpAndSettle();
      final rect = tester.getRect(meteor);
      final raster = (await tester.runAsync(() => capture('meteor')))!;
      var chroma = 0, count = 0;
      for (var y = rect.top.ceil() + 108; y < rect.top.floor() + 130; y++) {
        for (var x = rect.left.ceil() + 20; x < rect.right.floor() - 20; x++) {
          final i = (y * raster.$2 + x) * 4;
          final rgb = [for (var c = 0; c < 3; c++) raster.$1.getUint8(i + c)];
          chroma += rgb.reduce(math.max) - rgb.reduce(math.min);
          count++;
        }
      }
      final meanChroma = chroma / count;
      expect(
        meanChroma,
        greaterThanOrEqualTo(6),
        reason:
            'Meteor must show visible native color in the empty tile '
            'band; measured mean RGB chroma $meanChroma/255.',
      );
      // Dense effects must not wash out labels when sparse effects brighten.
      // Effect 0 deliberately receives opaque white as the worst-case frame;
      // Beat Pulse uses the actual energetic native representative frame.
      for (final effect in [0, 1, 3, 11, 15]) {
        final tile = find.byKey(ValueKey('effect-$effect'));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        final label = find.descendant(of: tile, matching: find.byType(Text));
        final paragraph = tester.renderObject<RenderParagraph>(label);
        final text = paragraph.text as TextSpan;
        final ink = text.style!.color!;
        final labelRect = tester.getRect(label);
        paragraph.text = TextSpan(
          text: text.text,
          children: text.children,
          style: text.style!.copyWith(color: Colors.transparent),
        );
        await tester.pump();
        final background = (await tester.runAsync(
          () => capture('effect-$effect-label-background'),
        ))!;
        paragraph.text = text;
        await tester.pump();
        expect(
          worstContrast(background.$1, background.$2, labelRect, ink),
          greaterThanOrEqualTo(4.5),
          reason: 'Effect $effect title contrast',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
