import 'dart:typed_data';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Frames implements LightFrameRenderer {
  final beats = <bool>[];
  @override
  void configure(List<int> payload) {}
  @override
  void dispose() {}
  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) {
    beats.add(beat);
    return Uint8List(1024);
  }
}

void main() {
  for (final switchEffect in [false, true]) {
    testWidgets(
      'withdrawing an onset identity clears its queued event; effect=$switchEffect',
      (tester) async {
        final frames = _Frames();
        DateTime? onset;
        var effect = 0;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return LightScreen(
                    settings: LedSettings(effect: effect),
                    onChanged: (_) {},
                    connected: true,
                    meter: MeterLevels(80, 80, 80, DateTime.now()),
                    previewAudio: const [.5, .3, .2, -10, -20, -30, .5],
                    previewAudioActive: true,
                    previewBeat: onset != null,
                    previewBeatAt: onset,
                    rendererFactory: () => frames,
                  );
                },
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump();
        update(() => onset = DateTime.now());
        await tester.pump(const Duration(milliseconds: 10));
        update(() {
          onset = null;
          if (switchEffect) effect = 1;
        });
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 40));
        expect(frames.beats.where((beat) => beat), isEmpty);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      },
    );
  }

  for (final age in [
    const Duration(milliseconds: 600),
    const Duration(seconds: -5),
  ]) {
    testWidgets('an onset with age $age cannot fire with fresh level data', (
      tester,
    ) async {
      final frames = _Frames();
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LightScreen(
              settings: const LedSettings(),
              onChanged: (_) {},
              connected: true,
              meter: MeterLevels(80, 80, 80, now),
              previewAudio: const [.5, .3, .2, -10, -20, -30, .5],
              previewAudioActive: true,
              previewBeat: true,
              previewBeatAt: now.subtract(age),
              rendererFactory: () => frames,
            ),
          ),
        ),
      );
      expect(frames.beats, isNotEmpty);
      expect(frames.beats.where((beat) => beat), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    });
  }

  testWidgets(
    'one onset identity is consumed once across later level packets',
    (tester) async {
      final frames = _Frames();
      final onset = DateTime.now();
      var meter = MeterLevels(80, 80, 80, onset);
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return LightScreen(
                  settings: const LedSettings(),
                  onChanged: (_) {},
                  connected: true,
                  meter: meter,
                  previewAudio: const [.5, .3, .2, -10, -20, -30, .5],
                  previewAudioActive: true,
                  previewBeat: true,
                  previewBeatAt: onset,
                  rendererFactory: () => frames,
                );
              },
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        update(() => meter = MeterLevels(75 - i, 70, 65, DateTime.now()));
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(frames.beats.length, greaterThan(1));
      expect(frames.beats.where((beat) => beat), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    },
  );
}
