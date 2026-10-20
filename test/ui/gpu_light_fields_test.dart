import 'dart:ui' as ui;

import 'package:bdk_audio/features/light/gpu_light_fields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Skia rejects GPU float fields instead of silently using RGBA8',
    (tester) async {
      await tester.runAsync(() async {
        final first = GpuLightFieldRenderer.load();
        final second = GpuLightFieldRenderer.load();
        expect(identical(first, second), isTrue);
        expect(await first, isNull);
        expect(GpuLightFieldRenderer.lastProbe['accepted'], isFalse);
        expect(
          GpuLightFieldRenderer.lastProbe['status'],
          'unsupported_backend',
        );
      });
    },
    skip: ui.ImageFilter.isShaderFilterSupported,
  );

  testWidgets(
    'constructor cannot bypass unsupported backend protection',
    (tester) async {
      await tester.runAsync(() async {
        // Existing compiled asset supplies a real program, without depending on
        // native effect libraries or permitting an unsafe float32 field pass.
        final program = await ui.FragmentProgram.fromAsset(
          'shaders/led_diffusion.frag',
        );
        expect(() => GpuLightFieldRenderer(program), throwsUnsupportedError);
      });
    },
    skip: ui.ImageFilter.isShaderFilterSupported,
  );

  testWidgets('probe diagnostics are read-only and cached', (tester) async {
    await tester.runAsync(() async {
      await GpuLightFieldRenderer.load();
      expect(
        () => GpuLightFieldRenderer.lastProbe['accepted'] = true,
        throwsUnsupportedError,
      );
    });
  });

  testWidgets('owned GPU image disposal preserves borrowed image handles', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = _sourceImage();
      final fields = GpuLightImages(source.clone(), source.clone());
      final retained = fields.core.clone();
      fields.dispose();
      fields.dispose();
      expect(source.debugDisposed, isFalse);
      expect(retained.debugDisposed, isFalse);
      expect(fields.core.debugDisposed, isTrue);
      expect(fields.halo.debugDisposed, isTrue);
      expect(await retained.toByteData(), isNotNull);
      retained.dispose();
      source.dispose();
    });
  });

  testWidgets(
    'Impeller fields survive source and renderer disposal',
    (tester) async {
      await tester.runAsync(() async {
        final program = await GpuLightFieldRenderer.load();
        expect(
          program,
          isNotNull,
          reason: '${GpuLightFieldRenderer.lastProbe}',
        );
        final renderer = GpuLightFieldRenderer(program!);
        final source = _sourceImage();
        final fields = renderer.render(source, 1.7);
        source.dispose();
        renderer.dispose();
        renderer.dispose();
        expect(fields.core.width, 256);
        expect(fields.core.height, 256);
        expect(fields.halo.width, 128);
        expect(fields.halo.height, 128);
        expect(
          await fields.core.toByteData(
            format: ui.ImageByteFormat.rawExtendedRgba128,
          ),
          isNotNull,
        );
        expect(
          await fields.halo.toByteData(
            format: ui.ImageByteFormat.rawExtendedRgba128,
          ),
          isNotNull,
        );
        fields.dispose();
        final lateSource = _sourceImage();
        expect(() => renderer.render(lateSource, 1.7), throwsStateError);
        lateSource.dispose();
      });
    },
    skip: !ui.ImageFilter.isShaderFilterSupported,
  );
}

ui.Image _sourceImage() {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(8, 8, 1, 1),
    ui.Paint()
      ..color = const ui.Color(0xff804020)
      ..isAntiAlias = false,
  );
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(16, 16);
  } finally {
    picture.dispose();
  }
}
