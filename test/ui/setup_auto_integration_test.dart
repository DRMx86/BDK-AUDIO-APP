import 'package:bdk_audio/app.dart';
import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/connection/speaker_setup_controller.dart';
import 'package:bdk_audio/platform/audio_connection_adapter.dart';
import 'package:bdk_audio/protocol/speaker_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../session_test.dart' as fixtures;
import '../setup_controller_test.dart' show FakeAudio;

void main() {
  testWidgets(
    'Speaker Disconnect suppresses automatic reconnection through the app',
    (tester) async {
      final audio = FakeAudio()
        ..current = const AudioConnectionSnapshot(
          devices: [AudioDeviceIdentity(id: 'speaker', name: 'BDK SPEAKER')],
        );
      final transport = fixtures.FakeTransport();
      final link = fixtures.FakeLink('speaker');
      transport.links.add(link);
      link.onWrite = (_) => link.status(fixtures.fullStatus);
      final session = SpeakerSession(transport);
      final setup = SpeakerSetupController(
        session,
        audio,
        autoConnectEnabled: true,
        pollInterval: Duration.zero,
      );
      addTearDown(() async {
        await tester.runAsync(() async {
          setup.dispose();
          session.dispose();
          await transport.close();
        });
      });
      await tester.pumpWidget(BdkApp(session: session, setup: setup));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(setup.audioReady, isTrue);
      expect(transport.scanStarts, 1);
      transport.scanController.add(
        const DiscoveredSpeaker(
          id: 'speaker',
          name: 'BDK SPEAKER',
          services: [SpeakerProtocol.service],
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(session.state.value.connected, isTrue);
      await tester.tap(find.text('Speaker').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Disconnect'),
        160,
        scrollable: find.descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(find.text('Disconnect'));
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(session.state.value.connected, isFalse);
      expect(transport.scanStarts, 1);
      expect(link.writes, [
        [0xf0],
      ]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a hidden desktop window cancels a pending automatic connection',
    (tester) async {
      final audio = FakeAudio()
        ..current = const AudioConnectionSnapshot(
          devices: [AudioDeviceIdentity(id: 'speaker', name: 'BDK SPEAKER')],
        );
      final transport = fixtures.FakeTransport();
      final link = fixtures.FakeLink('speaker');
      link.onWrite = (_) => link.status(fixtures.fullStatus);
      transport.links.add(link);
      final session = SpeakerSession(transport);
      final setup = SpeakerSetupController(
        session,
        audio,
        autoConnectEnabled: true,
        pollInterval: Duration.zero,
      );
      addTearDown(() async {
        await tester.runAsync(() async {
          setup.dispose();
          session.dispose();
          await transport.close();
        });
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await tester.pumpWidget(BdkApp(session: session, setup: setup));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(transport.scanStarts, 1);
      transport.scanController.add(
        const DiscoveredSpeaker(
          id: 'speaker',
          name: 'BDK SPEAKER',
          services: [SpeakerProtocol.service],
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      try {
        expect(link.writes, isEmpty);
        expect(session.state.value.connected, isFalse);
        expect(transport.scanStarts, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
