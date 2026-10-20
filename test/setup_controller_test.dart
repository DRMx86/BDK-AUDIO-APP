import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/connection/speaker_setup_controller.dart';
import 'package:bdk_audio/platform/audio_connection_adapter.dart';
import 'package:bdk_audio/protocol/speaker_protocol.dart';
import 'session_test.dart' as fixtures;

class FakeAudio implements AudioConnectionAdapter {
  AudioConnectionSnapshot current = const AudioConnectionSnapshot();
  int reads = 0, permissions = 0, settings = 0;
  Completer<AudioConnectionSnapshot>? gate;
  Object? error;
  @override
  Future<AudioConnectionSnapshot> snapshot() async {
    reads++;
    if (error != null) throw error!;
    return gate == null ? current : await gate!.future;
  }

  @override
  Future<void> requestPermission() async {
    permissions++;
  }

  @override
  Future<void> openBluetoothSettings() async {
    settings++;
  }
}

void main() {
  test('cancel during audio check cannot start a later scan', () async {
    final a = FakeAudio(), t = fixtures.FakeTransport();
    final real = SpeakerSession(t),
        c = SpeakerSetupController(real, a, pollInterval: Duration.zero);
    a.gate = Completer<AudioConnectionSnapshot>();
    final pending = c.searchControls();
    await Future<void>.delayed(Duration.zero);
    await c.cancel();
    a.gate!.complete(
      const AudioConnectionSnapshot(
        devices: [AudioDeviceIdentity(id: 'speaker', name: 'BDK SPEAKER')],
      ),
    );
    await pending;
    expect(t.scanStarts, 0);
    c.dispose();
    real.dispose();
    await t.close();
  });
  test(
    'cancel during audio recheck cannot start a later control connection',
    () async {
      final a = FakeAudio(), t = fixtures.FakeTransport();
      final s = SpeakerSession(t);
      final setup = SpeakerSetupController(s, a, pollInterval: Duration.zero);
      a.current = const AudioConnectionSnapshot(
        devices: [AudioDeviceIdentity(id: 'speaker', name: 'BDK SPEAKER')],
      );
      await setup.refresh();
      await setup.searchControls();
      t.scanController.add(
        const DiscoveredSpeaker(
          id: 'speaker',
          name: 'BDK SPEAKER',
          services: [SpeakerProtocol.service],
        ),
      );
      final link = fixtures.FakeLink('speaker');
      t.links.add(link);
      link.onWrite = (p) {
        if (p[0] == 0xf0) link.status(fixtures.fullStatus);
      };
      a.gate = Completer<AudioConnectionSnapshot>();
      final pending = setup.connectControls('speaker');
      await Future<void>.delayed(Duration.zero);
      await setup.cancel();
      a.gate!.complete(a.current);
      await pending;
      expect(s.state.value.connected, isFalse);
      setup.dispose();
      s.dispose();
      await t.close();
    },
  );
  test(
    'switching actual audio identity cancels the pending old control link',
    () async {
      final a = FakeAudio(), t = fixtures.FakeTransport();
      final s = SpeakerSession(t);
      final c = SpeakerSetupController(s, a, pollInterval: Duration.zero);
      a.current = const AudioConnectionSnapshot(
        devices: [AudioDeviceIdentity(id: 'A', name: 'BDK A')],
      );
      await c.refresh();
      await c.searchControls();
      t.scanController.add(
        const DiscoveredSpeaker(
          id: 'A',
          name: 'BDK A',
          services: [SpeakerProtocol.service],
        ),
      );
      final gate = Completer<void>(), link = fixtures.FakeLink('A');
      t.links.add(link);
      link.onSubscribe = (_) => gate.future;
      link.onWrite = (p) {
        if (p[0] == 0xf0) link.status(fixtures.fullStatus);
      };
      final pending = c.connectControls('A');
      await Future<void>.delayed(Duration.zero);
      expect(c.connecting, isTrue);
      a.current = const AudioConnectionSnapshot(
        devices: [AudioDeviceIdentity(id: 'B', name: 'BDK B')],
      );
      await c.refresh();
      gate.complete();
      await pending;
      expect(s.state.value.connected, isFalse);
      expect(c.selectedAudioId, 'B');
      c.dispose();
      s.dispose();
      await t.close();
    },
  );
  late FakeAudio audio;
  late fixtures.FakeTransport transport;
  late SpeakerSession session;
  late SpeakerSetupController setup;
  setUp(() {
    audio = FakeAudio();
    transport = fixtures.FakeTransport();
    session = SpeakerSession(transport);
    setup = SpeakerSetupController(session, audio, pollInterval: Duration.zero);
  });
  tearDown(() async {
    setup.dispose();
    session.dispose();
    await transport.close();
  });
  const audioDevice = AudioDeviceIdentity(
    id: 'AA:BB:CC:DD:EE:01',
    name: 'BDK SPEAKER',
  );
  Future<fixtures.FakeLink> connectExpectedAudio() async {
    audio.current = const AudioConnectionSnapshot(devices: [audioDevice]);
    await setup.searchControls();
    final link = fixtures.FakeLink(audioDevice.id);
    transport.links.add(link);
    link.onWrite = (p) {
      if (p[0] == 0xf0) link.status(fixtures.fullStatus);
    };
    transport.scanController.add(
      DiscoveredSpeaker(
        id: audioDevice.id,
        name: audioDevice.name,
        services: const [SpeakerProtocol.service],
      ),
    );
    await setup.connectControls(audioDevice.id);
    expect(session.state.value.connected, isTrue);
    return link;
  }

  test('shipping parity preserves the actionable connection failure', () async {
    audio.current = const AudioConnectionSnapshot(devices: [audioDevice]);
    await setup.searchControls();
    transport.scanController.add(
      DiscoveredSpeaker(
        id: audioDevice.id,
        name: audioDevice.name,
        services: const [SpeakerProtocol.service],
      ),
    );
    transport.connectError = const BleTransportException(
      'Speaker is missing the required STATUS notification characteristic.',
    );

    await setup.connectControls(audioDevice.id);

    expect(session.state.value.connected, isFalse);
    expect(setup.connecting, isFalse);
    expect(setup.message, contains('STATUS notification characteristic'));
  });

  test('audio loss closes an already ready control connection', () async {
    final link = await connectExpectedAudio();
    audio.current = const AudioConnectionSnapshot();
    await setup.refresh();
    expect(session.state.value.connected, isFalse);
    expect(setup.audioReady, isFalse);
    expect(link.operations, contains('disconnect'));
  });

  test(
    'connection completion rechecks audio even before the next poll',
    () async {
      audio.current = const AudioConnectionSnapshot(devices: [audioDevice]);
      await setup.searchControls();
      final link = fixtures.FakeLink(audioDevice.id);
      transport.links.add(link);
      link.onWrite = (p) {
        if (p[0] == 0xf0) {
          audio.current = const AudioConnectionSnapshot();
          link.status(fixtures.fullStatus);
        }
      };
      transport.scanController.add(
        DiscoveredSpeaker(
          id: audioDevice.id,
          name: audioDevice.name,
          services: const [SpeakerProtocol.service],
        ),
      );
      await setup.connectControls(audioDevice.id);
      expect(session.state.value.connected, isFalse);
      expect(setup.audioReady, isFalse);
    },
  );

  test(
    'switching audio closes controls belonging to the previous speaker',
    () async {
      await connectExpectedAudio();
      audio.current = const AudioConnectionSnapshot(
        devices: [AudioDeviceIdentity(id: 'other-speaker', name: 'BDK OTHER')],
      );
      await setup.refresh();
      expect(setup.selectedAudioId, 'other-speaker');
      expect(session.state.value.connected, isFalse);
    },
  );

  test(
    'failed audio recheck closes ready controls and invalidates identity',
    () async {
      await connectExpectedAudio();
      audio.error = StateError('Audio service unavailable');
      await setup.refresh();
      expect(session.state.value.connected, isFalse);
      expect(setup.audioReady, isFalse);
      expect(setup.selectedAudioId, isNull);
    },
  );

  test(
    'failed audio check cannot reuse a prior identity to scan or connect',
    () async {
      audio.current = const AudioConnectionSnapshot(devices: [audioDevice]);
      await setup.searchControls();
      final link = fixtures.FakeLink(audioDevice.id);
      transport.links.add(link);
      link.onWrite = (p) {
        if (p[0] == 0xf0) link.status(fixtures.fullStatus);
      };
      transport.scanController.add(
        DiscoveredSpeaker(
          id: audioDevice.id,
          name: audioDevice.name,
          services: const [SpeakerProtocol.service],
        ),
      );
      audio.error = StateError('Audio service unavailable');
      await setup.connectControls(audioDevice.id);
      await setup.searchControls();
      expect(session.state.value.connected, isFalse);
      expect(setup.audioReady, isFalse);
      expect(link.writes, isEmpty);
      expect(transport.scanStarts, 1);
    },
  );
  test(
    'no connected audio blocks BLE discovery and preserves pairing state',
    () async {
      await setup.refresh();
      await setup.searchControls();
      expect(setup.audioReady, isFalse);
      expect(transport.scanStarts, 0);
      expect(setup.message, contains('audio'));
    },
  );
  test(
    'connected audio needs no codec association to unlock control discovery',
    () async {
      audio.current = const AudioConnectionSnapshot(
        devices: [audioDevice],
        message: 'Codec association required',
      );
      await setup.refresh();
      expect(setup.audioReady, isTrue);
      await setup.searchControls();
      expect(transport.scanStarts, 1);
      transport.scanController.add(
        const DiscoveredSpeaker(
          id: 'aa:bb:cc:dd:ee:01',
          name: 'BDK SPEAKER',
          services: [SpeakerProtocol.service],
        ),
      );
      transport.scanController.add(
        const DiscoveredSpeaker(
          id: 'aa:bb:cc:dd:ee:02',
          name: 'Other BDK',
          services: [SpeakerProtocol.service],
        ),
      );
      expect(setup.controlDevices.map((d) => d.id), ['aa:bb:cc:dd:ee:01']);
      await session.stopScan();
      expect(setup.searchCompleted, isTrue);
    },
  );
  test(
    'an unrelated audio device never silently unlocks a nearby speaker',
    () async {
      audio.current = const AudioConnectionSnapshot(
        devices: [AudioDeviceIdentity(id: 'headphones', name: 'Headphones')],
      );
      await setup.refresh();
      expect(setup.audioReady, isFalse);
      expect(setup.selectedAudioId, isNull);
    },
  );
  test(
    'connect rechecks audio and rejects a stale or different-device candidate',
    () async {
      audio.current = const AudioConnectionSnapshot(devices: [audioDevice]);
      await setup.refresh();
      await setup.searchControls();
      transport.scanController.add(
        const DiscoveredSpeaker(
          id: 'aa:bb:cc:dd:ee:01',
          name: 'BDK SPEAKER',
          services: [SpeakerProtocol.service],
        ),
      );
      audio.current = const AudioConnectionSnapshot();
      await setup.connectControls('aa:bb:cc:dd:ee:01');
      expect(session.state.value.connected, isFalse);
      expect(setup.audioReady, isFalse);
      expect(setup.controlDevices, isEmpty);
    },
  );
  test(
    'audio loss stops a running scan without claiming any control connection',
    () async {
      audio.current = const AudioConnectionSnapshot(devices: [audioDevice]);
      await setup.refresh();
      await setup.searchControls();
      audio.current = const AudioConnectionSnapshot();
      await setup.refresh();
      expect(transport.scanStops, greaterThan(0));
      expect(setup.audioReady, isFalse);
      expect(setup.searching, isFalse);
    },
  );
  test(
    'OS-managed audio requires explicit confirmation and still verifies BLE sync',
    () async {
      audio.current = const AudioConnectionSnapshot(canVerifyIdentity: false);
      await setup.refresh();
      expect(setup.audioReady, isFalse);
      setup.confirmManagedAudio();
      expect(setup.audioReady, isTrue);
      await setup.searchControls();
      expect(transport.scanStarts, 1);
      final link = fixtures.FakeLink('speaker');
      transport.links.add(link);
      link.onWrite = (p) {
        if (p[0] == 0xf0) link.status(fixtures.fullStatus);
      };
      transport.scanController.add(
        const DiscoveredSpeaker(
          id: 'speaker',
          name: 'BDK SPEAKER',
          services: [SpeakerProtocol.service],
        ),
      );
      await setup.connectControls('speaker');
      expect(session.state.value.connected, isTrue);
    },
  );
  test(
    'empty completed scan exposes recovery and a retry clears the empty state',
    () async {
      audio.current = const AudioConnectionSnapshot(devices: [audioDevice]);
      await setup.refresh();
      await setup.searchControls();
      await session.stopScan();
      expect(setup.searchCompleted, isTrue);
      expect(setup.controlDevices, isEmpty);
      await setup.searchControls();
      expect(setup.searchCompleted, isFalse);
      expect(setup.searching, isTrue);
      await setup.openBluetoothSettings();
      expect(audio.settings, 1);
    },
  );
}
