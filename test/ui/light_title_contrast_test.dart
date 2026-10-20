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

class _WhiteFrames implements LightFrameRenderer {
  @override
  void configure(List<int> payload) {}
  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) => Uint8List(1024)..fillRange(0, 1024, 255);
  @override
  void dispose() {}
}

Color _pixel(ByteData bytes, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

void main() {
  for (final scenario in [
    (width: 400.0, dpr: 1.0, scale: 1.0, effect: 21, name: 'Ambient'),
    (width: 320.0, dpr: 2.0, scale: 1.0, effect: 13, name: 'Frequency Spiral'),
    (width: 320.0, dpr: 2.0, scale: 2.0, effect: 13, name: 'Frequency Spiral'),
  ]) {
    testWidgets('${scenario.name} title contrasts with white LEDs at '
        '${scenario.width.toInt()}px, ${scenario.dpr.toInt()}x DPR, '
        '${scenario.scale.toInt()}x text', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.devicePixelRatio = scenario.dpr;
        tester.view.physicalSize = Size(
          scenario.width * scenario.dpr,
          900 * scenario.dpr,
        );
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final boundaryKey = GlobalKey();
        await tester.runAsync(() async {
          // Widget tests otherwise render the Ahem fallback, whose square
          // glyphs and shadows cannot establish the real title's contrast.
          for (final family in ['Manrope', 'SpaceGrotesk']) {
            final loader = FontLoader(family)
              ..addFont(rootBundle.load('assets/fonts/$family.ttf'));
            await loader.load();
          }
        });
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: bdkTheme(Brightness.dark),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scenario.scale),
                  ),
                  child: LightScreen(
                    settings: LedSettings(
                      effect: scenario.effect,
                      brightness: 100,
                    ),
                    onChanged: (_) {},
                    rendererFactory: _WhiteFrames.new,
                  ),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump();
        }
        final painter =
            tester
                    .widget<CustomPaint>(find.byKey(const ValueKey('led-core')))
                    .painter!
                as FirmwareLightPainter;
        expect(
          painter.image,
          isNotNull,
          reason: 'Measure a decoded frame, not the dark placeholder.',
        );
        expect(painter.image!.width, 16);
        expect(painter.image!.height, 16);
        await tester.runAsync(() async {
          final rgba = (await painter.image!.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          expect(
            rgba.buffer.asUint8List().every((byte) => byte == 255),
            isTrue,
            reason: 'Decoded source RGB and alpha must all be opaque white.',
          );
        });
        final title = find.descendant(
          of: find.byKey(const ValueKey('led-artwork')),
          matching: find.text(scenario.name),
        );
        expect(title, findsOneWidget);
        expect(title.hitTestable(), findsOneWidget);
        expect(
          tester.getSemantics(title).getSemanticsData().label,
          contains(scenario.name),
        );
        final titleRect = tester.getRect(title);
        final paragraph = tester.renderObject<RenderParagraph>(title);
        final original = paragraph.text as TextSpan;
        final style = original.style!;
        expect(style.color, Colors.white);
        expect(style.fontWeight, FontWeight.w700);
        if (scenario.scale == 2) {
          expect(
            titleRect.height,
            greaterThan(style.fontSize! * 3),
            reason: 'The enlarged long title must exercise wrapping.',
          );
        }
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        late ByteData actual, background, glyphMask;
        late int width, maskWidth, maskHeight;
        Future<ByteData> capture(String name) async {
          final image = await boundary.toImage(pixelRatio: scenario.dpr);
          width = image.width;
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          if (const bool.fromEnvironment('EXPORT_CONTRAST_ARTIFACTS')) {
            final png = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            final directory = Directory('artifacts/contrast')
              ..createSync(recursive: true);
            File(
              '${directory.path}/${scenario.effect}-${scenario.width.toInt()}-'
              '${scenario.scale.toInt()}-$name.png',
            ).writeAsBytesSync(png.buffer.asUint8List());
          }
          image.dispose();
          return pixels;
        }

        await tester.runAsync(() async {
          actual = await capture('white-frame');
          // A separate glyph mask ensures white-on-white glyphs cannot be
          // excluded as indistinguishable from uncovered background pixels.
          final textPainter =
              TextPainter(
                text: TextSpan(
                  text: original.text,
                  children: original.children,
                  style: style.copyWith(shadows: const []),
                ),
                textDirection: paragraph.textDirection,
                textAlign: paragraph.textAlign,
                textScaler: paragraph.textScaler,
                maxLines: paragraph.maxLines,
                locale: paragraph.locale,
                strutStyle: paragraph.strutStyle,
                textWidthBasis: paragraph.textWidthBasis,
                textHeightBehavior: paragraph.textHeightBehavior,
              )..layout(
                minWidth: paragraph.size.width,
                maxWidth: paragraph.size.width,
              );
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..scale(scenario.dpr);
          textPainter.paint(canvas, Offset.zero);
          final picture = recorder.endRecording();
          maskWidth = (paragraph.size.width * scenario.dpr).ceil();
          maskHeight = (paragraph.size.height * scenario.dpr).ceil();
          final image = await picture.toImage(maskWidth, maskHeight);
          glyphMask = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          image.dispose();
          picture.dispose();
          textPainter.dispose();
        });
        // Keep the original shadow as the most generous possible background
        // for the actual white foreground; change no production widget.
        paragraph.text = TextSpan(
          text: original.text,
          children: original.children,
          style: style.copyWith(color: Colors.transparent),
        );
        await tester.pump();
        await tester.runAsync(
          () async => background = await capture('shadow-background'),
        );
        paragraph.text = original;
        await tester.pump();
        final ratios = <double>[];
        final left = (titleRect.left * scenario.dpr).round();
        final top = (titleRect.top * scenario.dpr).round();
        for (var y = 0; y < maskHeight; y++) {
          for (var x = 0; x < maskWidth; x++) {
            if (_pixel(glyphMask, maskWidth, x, y) == Colors.white) {
              final foreground = _pixel(actual, width, left + x, top + y);
              expect(
                foreground,
                Colors.white,
                reason:
                    'The independent mask must align with actual title glyphs.',
              );
              ratios.add(
                _contrast(
                  foreground,
                  _pixel(background, width, left + x, top + y),
                ),
              );
            }
          }
        }
        expect(
          ratios,
          isNotEmpty,
          reason: 'Measure opaque glyph interiors, excluding antialiasing.',
        );
        ratios.sort();
        debugPrint(
          'TITLE CONTRAST ${scenario.name} ${scenario.width}px '
          '${scenario.dpr}x DPR ${scenario.scale}x text: '
          '${ratios.length} opaque glyph pixels, '
          '${ratios.first.toStringAsFixed(3)}..${ratios.last.toStringAsFixed(3)}:1, '
          'title bounds=$titleRect',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(
          ratios.first,
          greaterThanOrEqualTo(4.5),
          reason:
              'Keep at least 4.5:1 contrast for the normal-size title, '
              'and retain that margin when enlarged, including its shadow.',
        );
      } finally {
        semantics.dispose();
      }
    });
  }
}
