import 'package:bdk_audio/app.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:bdk_audio/features/light/meter_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../session_test.dart' as fixtures;

void main() {
  testWidgets(
    'a detected beat survives notifications coalesced into one frame',
    (tester) async {
      final transport = fixtures.FakeTransport();
      final session = SpeakerSession(transport);
      session.state.value = const SpeakerState(
        phase: ConnectionPhase.ready,
        deviceId: 'speaker',
      );
      addTearDown(() async {
        session.dispose();
        await transport.close();
      });
      await tester.pumpWidget(BdkApp(session: session));
      await tester.pump();
      await tester.tap(find.text('Light').last);
      await tester.pump(const Duration(milliseconds: 320));

      final reference = MeterPreviewProcessor();
      final start = DateTime.now().subtract(const Duration(milliseconds: 400));
      for (var index = 0; index < 20; index++) {
        final meter = MeterLevels(
          10,
          10,
          10,
          start.add(Duration(milliseconds: index * 10)),
        );
        reference.update(meter, now: DateTime.now());
        session.state.value = session.state.value.copyWith(meter: meter);
      }
      final attack = MeterLevels(
        90,
        100,
        100,
        DateTime.now().subtract(const Duration(milliseconds: 60)),
      );
      expect(reference.update(attack, now: DateTime.now()).beat, isTrue);
      session.state.value = session.state.value.copyWith(meter: attack);
      final next = MeterLevels(
        90,
        100,
        100,
        attack.receivedAt.add(const Duration(milliseconds: 30)),
      );
      expect(reference.update(next, now: DateTime.now()).beat, isFalse);
      session.state.value = session.state.value.copyWith(meter: next);

      // Both notifications arrive before Flutter builds the next widget frame.
      await tester.pump();
      final light = tester.widget<LightScreen>(find.byType(LightScreen));
      expect(light.meter, same(next));
      expect(
        light.previewBeat,
        isTrue,
        reason: 'The later level packet must not erase the detected onset.',
      );
      expect(light.previewBeatAt, attack.receivedAt);
      session.state.value = session.state.value.copyWith(clearMeter: true);
      await tester.pump();
      final cleared = tester.widget<LightScreen>(find.byType(LightScreen));
      expect(cleared.previewBeat, isFalse);
      expect(cleared.previewBeatAt, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    },
  );
}
