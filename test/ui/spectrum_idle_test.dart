import 'dart:typed_data';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Frames implements LightFrameRenderer {
  final demos = <bool>[];
  @override
  void configure(List<int> payload) {}
  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) {
    demos.add(demo);
    return Uint8List(1024);
  }

  @override
  void dispose() {}
}

Future<void> _mount(
  WidgetTester tester,
  _Frames frames, {
  MeterLevels? meter,
  int effect = 0,
  bool active = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: LightScreen(
        settings: LedSettings(effect: effect),
        onChanged: (_) {},
        rendererFactory: () => frames,
        connected: true,
        meter: meter,
        previewAudio: const [0, 0, 0, -60, -60, -60, 0],
        previewAudioActive: active,
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'fresh confirmed silence enables Spectrum idle, expiry returns to waiting',
    (tester) async {
      final frames = _Frames();
      await _mount(tester, frames, meter: MeterLevels(0, 0, 0, DateTime.now()));
      expect(frames.demos.last, isTrue);
      expect(find.text('Preview · idle animation'), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump(const Duration(milliseconds: 40));
      expect(frames.demos.last, isFalse);
      expect(find.textContaining('waiting for audio levels'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final kind in [
    'missing',
    'stale',
    'positive',
    'active',
    'other effect',
  ]) {
    testWidgets('$kind never authorizes synthetic connected Spectrum input', (
      tester,
    ) async {
      final frames = _Frames(), now = DateTime.now();
      final meter = kind == 'missing'
          ? null
          : kind == 'stale'
          ? MeterLevels(0, 0, 0, now.subtract(const Duration(seconds: 1)))
          : kind == 'positive'
          ? MeterLevels(0, 1, 0, now)
          : MeterLevels(0, 0, 0, now);
      await _mount(
        tester,
        frames,
        meter: meter,
        active: kind == 'active',
        effect: kind == 'other effect' ? 1 : 0,
      );
      expect(frames.demos.last, isFalse);
      expect(find.text('Preview · idle animation'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
