import 'package:bdk_audio/app.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/connection/speaker_setup_controller.dart';
import 'package:bdk_audio/features/codec/audio_quality_screen.dart';
import 'package:bdk_audio/platform/audio_connection_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../codec_test_support.dart';
import '../session_test.dart' as fixtures;
import '../setup_controller_test.dart' show FakeAudio;

void main() {
  testWidgets('audio config follows all tabs and pauses behind full details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final transport = fixtures.FakeTransport();
    final link = fixtures.FakeLink('speaker');
    transport.links.add(link);
    link.onWrite = (_) => link.status(fixtures.fullStatus);
    final session = SpeakerSession(transport);
    await session.connect('speaker');
    final audio = FakeAudio()
      ..current = const AudioConnectionSnapshot(
        devices: [AudioDeviceIdentity(id: 'speaker', name: 'BDK SPEAKER')],
      );
    final setup = SpeakerSetupController(
      session,
      audio,
      pollInterval: Duration.zero,
    );
    await setup.refresh();
    final adapters = <FakeCodecAdapter>[];
    addTearDown(() async {
      setup.dispose();
      session.dispose();
      await transport.close();
    });
    await tester.pumpWidget(
      BdkApp(
        session: session,
        setup: setup,
        codecAdapterFactory: () {
          final adapter = FakeCodecAdapter();
          adapters.add(adapter);
          return adapter;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    final summary = find.byKey(const ValueKey('audio-config-summary'));
    expect(summary, findsOneWidget);
    expect(find.textContaining('LDAC · 48 kHz · 24-bit'), findsOneWidget);
    for (final tab in ['Light', 'Speaker', 'Sound']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 320));
      expect(
        summary,
        findsOneWidget,
        reason: '$tab retains the current config',
      );
      expect(tester.takeException(), isNull);
    }
    final readsBeforeDetail = adapters.first.events.length;
    final openDetails = tester.widget<TextButton>(summary).onPressed!;
    openDetails();
    openDetails();
    await tester.pumpAndSettle();
    expect(
      find.byType(AudioQualityScreen, skipOffstage: false),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 6));
    expect(adapters.first.events.length, readsBeforeDetail);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(summary, findsOneWidget);
    expect(adapters.first.events.length, greaterThan(readsBeforeDetail));
    expect(adapters.expand((adapter) => adapter.writes), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
