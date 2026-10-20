import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/connection/speaker_setup_controller.dart';
import 'package:bdk_audio/platform/audio_connection_adapter.dart';
import 'package:bdk_audio/protocol/speaker_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test.dart' as fixtures;
import 'setup_controller_test.dart' show FakeAudio;

const _id = 'AA:BB:CC:DD:EE:01';
const _audio = AudioConnectionSnapshot(
  devices: [AudioDeviceIdentity(id: _id, name: 'BDK SPEAKER')],
);

class _Harness {
  final audio = FakeAudio();
  final transport = fixtures.FakeTransport();
  late final session = SpeakerSession(transport);
  late final setup = SpeakerSetupController(
    session,
    audio,
    autoDiscoverEnabled: true,
    pollInterval: const Duration(seconds: 1),
  );

  void result(String id) => transport.scanController.add(
    DiscoveredSpeaker(
      id: id,
      name: 'BDK SPEAKER',
      services: [SpeakerProtocol.service],
    ),
  );

  Future<void> close(WidgetTester tester) => tester.runAsync(() async {
    await setup.cancel();
    setup.dispose();
    session.dispose();
    await transport.close();
  });
}

Future<void> _tick(WidgetTester tester, [int seconds = 0]) async {
  await tester.pump(Duration(seconds: seconds));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

void _case(String name, Future<void> Function(WidgetTester, _Harness) body) {
  testWidgets(name, (tester) async {
    final h = _Harness();
    try {
      await body(tester, h);
    } finally {
      h.setup.setActive(false);
      await h.close(tester);
    }
  });
}

void main() {
  _case('multiple audio choices remain accessible during ongoing checks', (
    tester,
    h,
  ) async {
    h.setup.setActive(true);
    await _tick(tester, 6);
    h.audio.current = const AudioConnectionSnapshot(
      devices: [
        AudioDeviceIdentity(id: _id, name: 'BDK SPEAKER'),
        AudioDeviceIdentity(id: 'other', name: 'Other speaker'),
      ],
    );
    await _tick(tester, 1);
    expect(h.setup.audio.devices, hasLength(2));
    expect(h.setup.selectedAudioId, isNull);
    expect(h.setup.checkingAudio, isFalse); // Selection UI must be actionable.
    expect(h.transport.scanStarts, 0);
    final reads = h.audio.reads;
    await _tick(tester, 2);
    expect(h.audio.reads, greaterThan(reads));
    h.setup.selectAudioDevice(_id);
    await _tick(tester);
    expect(h.setup.searching, isTrue);
    expect(h.transport.scanStarts, 1);
  });

  _case(
    'audio checking continues after help appears without opening settings',
    (tester, h) async {
      h.setup.setActive(true);
      await _tick(tester);
      await _tick(tester, 5);
      expect(h.setup.audioSearchCompleted, isTrue);
      expect(h.setup.checkingAudio, isTrue);
      final reads = h.audio.reads;
      await _tick(tester, 12);
      expect(h.audio.reads, greaterThan(reads));
      expect(h.setup.checkingAudio, isTrue);
      expect(h.transport.scanStarts, 0);
      expect(h.audio.settings, 0);
      await h.setup.openBluetoothSettings();
      expect(h.audio.settings, 1);
    },
  );

  _case('connecting audio later starts discovery without a retry tap', (
    tester,
    h,
  ) async {
    h.setup.setActive(true);
    await _tick(tester);
    await _tick(tester, 8);
    h.audio.current = _audio;
    await _tick(tester, 1);
    expect(h.setup.searching, isTrue);
    expect(h.setup.audioSearchCompleted, isFalse);
    expect(h.transport.scanStarts, 1);
    expect(h.audio.settings, 0);
  });

  _case('empty matching scan stays live beyond the legacy deadline', (
    tester,
    h,
  ) async {
    h.audio.current = _audio;
    h.setup.setActive(true);
    await _tick(tester);
    await _tick(tester, 5);
    expect(h.setup.searchCompleted, isTrue);
    expect(h.setup.searching, isTrue);
    await _tick(tester, 20);
    expect(h.setup.searching, isTrue);
    expect(h.transport.scanStarts, 1);
    expect(h.transport.scanStops, 0);
    h.result(
      'AA:BB:CC:DD:EE:02',
    ); // Nearby unrelated BDK cannot end this search.
    await _tick(tester);
    expect(h.setup.searching, isTrue);
    expect(h.setup.controlDevices, isEmpty);
    h.result(_id);
    await _tick(tester);
    expect(h.setup.searching, isFalse);
    expect(h.setup.controlDevices.single.id, _id);
    expect(h.session.state.value.connected, isFalse);
    expect(h.audio.settings, 0);
  });

  _case('cancel and background stop continuous discovery without revival', (
    tester,
    h,
  ) async {
    h.audio.current = _audio;
    h.setup.setActive(true);
    await _tick(tester);
    await _tick(tester, 6);
    await h.setup.cancel();
    await _tick(tester, 20);
    expect(h.setup.searching, isFalse);
    expect(h.transport.scanStarts, 1);
    h.setup.beginDiscovery();
    await _tick(tester);
    expect(h.setup.searching, isTrue);
    h.setup.setActive(false);
    await _tick(tester, 20);
    expect(h.setup.searching, isFalse);
    expect(h.setup.checkingAudio, isFalse);
    expect(h.transport.scanStarts, 2);
  });

  _case('permission and failed OS query never show an active fake scan', (
    tester,
    h,
  ) async {
    h.audio.current = const AudioConnectionSnapshot(permissionRequired: true);
    h.setup.setActive(true);
    await _tick(tester, 6);
    expect(h.setup.checkingAudio, isFalse);
    expect(h.transport.scanStarts, 0);
    h.audio.error = StateError('query failed');
    await _tick(tester, 1);
    expect(h.setup.checkingAudio, isFalse);
    expect(h.transport.scanStarts, 0);
    expect(h.audio.settings, 0);
  });
}
