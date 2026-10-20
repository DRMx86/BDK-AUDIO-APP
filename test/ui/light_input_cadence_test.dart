import 'dart:typed_data';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Frames implements LightFrameRenderer {
  final inputs = <List<double>?>[];
  final beats = <bool>[];
  final configurations = <List<int>>[];
  @override
  void configure(List<int> payload) => configurations.add(List.of(payload));
  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) {
    inputs.add(audio == null ? null : List.of(audio));
    beats.add(beat);
    return Uint8List(1024);
  }

  @override
  void dispose() {}
}

void main() {
  for (final property in ['brightness', 'speed']) {
    testWidgets('100Hz $property updates keep the 30FPS effect clock', (
      tester,
    ) async {
      final frames = _Frames();
      var settings = LedSettings(effect: property == 'speed' ? 21 : 0);
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return LightScreen(
                  settings: settings,
                  onChanged: (_) {},
                  rendererFactory: () => frames,
                );
              },
            ),
          ),
        ),
      );
      for (var i = 1; i <= 100; i++) {
        update(
          () => settings = property == 'brightness'
              ? settings.copyWith(brightness: 20 + i % 80)
              : settings.copyWith(speed: i),
        );
        await tester.pump(const Duration(milliseconds: 10));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(
        frames.inputs.length,
        inInclusiveRange(20, 33),
        reason:
            'Parameter updates must not advance effect state outside '
            'the elapsed frame clock.',
      );
      expect(frames.configurations.last, settings.toPayload());
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    });
  }
  testWidgets('clearing a meter discards a queued beat before the next frame', (
    tester,
  ) async {
    final frames = _Frames();
    var beat = false, hasMeter = true;
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
                rendererFactory: () => frames,
                connected: true,
                meter: hasMeter
                    ? MeterLevels(50, 50, 50, DateTime.now())
                    : null,
                previewAudio: [.5, .3, .2, -10, -20, -30, .5],
                previewBeat: beat,
                previewAudioActive: hasMeter,
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
    update(() => beat = true);
    await tester.pump(const Duration(milliseconds: 10));
    update(() {
      beat = false;
      hasMeter = false;
    });
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(frames.beats.where((value) => value), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  });
  testWidgets(
    '100Hz inputs retain latest levels without accelerating the 30FPS effect clock',
    (tester) async {
      final frames = _Frames();
      var input = 0;
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
                  rendererFactory: () => frames,
                  connected: true,
                  meter: MeterLevels(50, 50, 50, DateTime.now()),
                  previewAudio: [input / 100, .3, .2, -10, -20, -30, .5],
                  previewAudioActive: true,
                  // Keep the short pulse near the final pair of updates so the
                  // real timestamp stays fresh even on a heavily loaded host.
                  previewBeat: input == 99,
                );
              },
            ),
          ),
        ),
      );
      for (var i = 1; i <= 100; i++) {
        update(() => input = i);
        await tester.pump(const Duration(milliseconds: 10));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(frames.inputs.length, inInclusiveRange(20, 33));
      // Image decoding runs on a real engine queue while the widget clock is
      // fake. Let any in-flight frame finish, then advance the next frame tick.
      for (
        var attempt = 0;
        attempt < 10 && frames.inputs.last![0] != 1;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(frames.inputs.last![0], 1.0);
      expect(
        frames.beats.where((beat) => beat),
        hasLength(1),
        reason: 'A short beat between frame ticks is consumed exactly once.',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    },
  );
}
