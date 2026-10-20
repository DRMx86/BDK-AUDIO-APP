import 'dart:typed_data';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Frames implements LightFrameRenderer {
  var renders = 0;
  @override
  void configure(List<int> payload) {}
  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) {
    renders++;
    return Uint8List(1024);
  }

  @override
  void dispose() {}
}

void main() {
  for (final effect in [0, 1, 3]) {
    testWidgets(
      'choosing effect $effect resumes a paused preview without slider input',
      (tester) async {
        var settings = const LedSettings();
        final frames = _Frames();
        var created = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => LightScreen(
                  settings: settings,
                  rendererFactory: () => created++ == 0 ? frames : _Frames(),
                  onChanged: (value) => update(() => settings = value),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('preview-playback')));
        await tester.pump();
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('preview-playback')))
              .label,
          contains('Play preview'),
        );
        await tester.ensureVisible(find.text('Choose an effect'));
        await tester.tap(find.text('Choose an effect'));
        for (var i = 0; i < 25; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        await tester.ensureVisible(find.byKey(ValueKey('effect-$effect')));
        await tester.tap(find.byKey(ValueKey('effect-$effect')));
        await tester.pump();
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('preview-playback')))
              .label,
          contains('Pause preview'),
        );
        final start = frames.renders;
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 40));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(frames.renders, greaterThan(start + 2));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
