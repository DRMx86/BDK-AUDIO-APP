import 'dart:async';
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
  _Harness({
    FakeAudio? adapter,
    bool useDefaultTiming = false,
    bool autoConnect = false,
  }) : audio = adapter ?? FakeAudio() {
    session = SpeakerSession(transport);
    setup = useDefaultTiming
        ? SpeakerSetupController(
            session,
            audio,
            pollInterval: Duration.zero,
            autoDiscoverEnabled: true,
            autoConnectEnabled: autoConnect,
          )
        : SpeakerSetupController(
            session,
            audio,
            pollInterval: Duration.zero,
            autoDiscoverEnabled: true,
            autoConnectEnabled: autoConnect,
            minimumDiscoveryTime: const Duration(seconds: 2),
          );
  }
  final FakeAudio audio;
  final transport = fixtures.FakeTransport();
  late final SpeakerSession session;
  late final SpeakerSetupController setup;
  fixtures.FakeLink? link;

  void discover() {
    link ??= fixtures.FakeLink(_id);
    if (!transport.links.contains(link)) transport.links.add(link!);
    transport.scanController.add(
      const DiscoveredSpeaker(
        id: _id,
        name: 'BDK SPEAKER',
        services: [SpeakerProtocol.service],
      ),
    );
  }

  Future<void> close(WidgetTester tester) => tester.runAsync(() async {
    setup.dispose();
    session.dispose();
    await transport.close();
  });
}

class _DelayedPermissionAudio extends FakeAudio {
  final permissionGate = Completer<void>();
  @override
  Future<void> requestPermission() async {
    permissions++;
    await permissionGate.future;
  }
}

Future<void> _tick(
  WidgetTester tester, [
  Duration duration = Duration.zero,
]) async {
  await tester.pump(duration);
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

void main() {
  testWidgets('a late verified candidate connects before the help deadline', (
    tester,
  ) async {
    final h = _Harness(useDefaultTiming: true, autoConnect: true);
    addTearDown(() => h.close(tester));
    h.audio.current = _audio;
    h.setup.setActive(true);
    await _tick(tester);
    await _tick(tester, const Duration(seconds: 4));
    h.discover();
    h.link!.onWrite = (p) {
      if (p[0] == 0xf0) h.link!.status(fixtures.fullStatus);
    };
    await _tick(tester, const Duration(milliseconds: 499));
    await _tick(tester);
    await _tick(tester);
    try {
      expect(h.session.state.value.connected, isTrue);
      expect(h.transport.scanStarts, 1);
      expect(h.link!.writes, [
        [0xf0],
      ]);
    } finally {
      await h.setup.cancel();
    }
  });

  testWidgets(
    'default audio search and retry each stay active for five seconds',
    (tester) async {
      final h = _Harness(useDefaultTiming: true);
      addTearDown(() => h.close(tester));
      h.setup.setActive(true);
      await _tick(tester);
      await _tick(tester, const Duration(milliseconds: 4999));
      expect(h.setup.checkingAudio, isTrue);
      expect(h.setup.audioSearchCompleted, isFalse);
      await _tick(tester, const Duration(milliseconds: 1));
      expect(h.setup.audioSearchCompleted, isTrue);
      h.setup.beginDiscovery();
      await _tick(tester, const Duration(milliseconds: 4999));
      expect(h.setup.checkingAudio, isTrue);
      expect(h.setup.audioSearchCompleted, isFalse);
      await _tick(tester, const Duration(milliseconds: 1));
      expect(h.setup.audioSearchCompleted, isTrue);
      expect(h.transport.scanStarts, 0);
    },
  );

  testWidgets(
    'default BLE discovery reveals help after five seconds while staying live',
    (tester) async {
      final h = _Harness(useDefaultTiming: true);
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      await _tick(tester, const Duration(milliseconds: 4999));
      expect(h.setup.searching, isTrue);
      expect(h.setup.searchCompleted, isFalse);
      await _tick(tester, const Duration(milliseconds: 1));
      try {
        expect(h.setup.searching, isTrue);
        expect(h.setup.searchCompleted, isTrue);
        expect(h.setup.controlDevices, isEmpty);
      } finally {
        await h.setup.cancel();
      }
    },
  );

  testWidgets(
    'automatic exact matching connection skips the help exposure delay',
    (tester) async {
      final h = _Harness(useDefaultTiming: true, autoConnect: true);
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      h.discover();
      h.link!.onWrite = (p) {
        if (p[0] == 0xf0) h.link!.status(fixtures.fullStatus);
      };
      await _tick(tester, const Duration(milliseconds: 499));
      await _tick(tester);
      await _tick(tester);
      expect(h.session.state.value.connected, isTrue);
      expect(h.link!.writes, [
        [0xf0],
      ]);
    },
  );

  testWidgets('late permission approval cannot revoke a cancelled discovery', (
    tester,
  ) async {
    final audio = _DelayedPermissionAudio()
      ..current = const AudioConnectionSnapshot(permissionRequired: true);
    final h = _Harness(adapter: audio);
    addTearDown(() => h.close(tester));
    h.setup.setActive(true);
    await _tick(tester);
    final pending = h.setup.requestPermission();
    await _tick(tester);
    await h.setup.cancel();
    audio.current = _audio;
    audio.permissionGate.complete();
    await pending;
    await _tick(tester, const Duration(seconds: 3));
    try {
      expect(h.transport.scanStarts, 0);
      expect(h.setup.checkingAudio, isFalse);
    } finally {
      await h.setup.cancel();
    }
  });

  testWidgets(
    'permission refresh starts one discovery without resetting its owner',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = const AudioConnectionSnapshot(permissionRequired: true);
      h.setup.setActive(true);
      await _tick(tester);
      h.audio.current = _audio;
      await h.setup.requestPermission();
      await _tick(tester);
      h.discover();
      await _tick(tester, const Duration(seconds: 2));
      await _tick(tester, const Duration(seconds: 30));
      try {
        expect(h.transport.scanStarts, 1);
        expect(h.session.state.value.connected, isFalse);
        expect(h.link!.writes, isEmpty);
      } finally {
        await h.setup.cancel();
      }
    },
  );

  testWidgets(
    'slow initial audio query is drained before a fresh final check',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      final first = Completer<AudioConnectionSnapshot>();
      h.audio.gate = first;
      h.setup.setActive(true);
      await _tick(tester, const Duration(seconds: 2));
      expect(h.audio.reads, 1);
      expect(h.setup.checkingAudio, isTrue);
      h.audio.gate = null;
      first.complete(const AudioConnectionSnapshot());
      await _tick(tester);
      expect(h.audio.reads, 2);
      expect(h.setup.checkingAudio, isTrue);
      expect(h.transport.scanStarts, 0);
    },
  );

  testWidgets('read-only discovery starts on entry without connecting', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(() => h.close(tester));
    h.audio.current = _audio;
    h.setup.setActive(true);
    await _tick(tester);
    expect(h.transport.scanStarts, 1);
    expect(h.setup.searching, isTrue);
    expect(h.setup.connecting, isFalse);
    expect(h.session.state.value.connected, isFalse);
    await h.setup.cancel();
  });

  testWidgets(
    'an immediate candidate stays in real discovery for two seconds',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      h.discover();
      await _tick(tester, const Duration(milliseconds: 1999));
      expect(h.setup.searching, isTrue);
      expect(h.setup.searchCompleted, isFalse);
      expect(h.setup.controlDevices, hasLength(1));
      await _tick(tester, const Duration(milliseconds: 1));
      expect(h.setup.searching, isFalse);
      expect(h.setup.searchCompleted, isTrue);
      expect(h.setup.controlDevices, hasLength(1));
      expect(h.link!.writes, isEmpty);
      expect(h.session.state.value.connected, isFalse);
      expect(h.transport.scanStarts, 1);
    },
  );

  testWidgets(
    'no candidate reveals help and keeps scanning with no fake ready',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      await _tick(tester, const Duration(milliseconds: 1999));
      expect(h.setup.searching, isTrue);
      expect(h.setup.searchCompleted, isFalse);
      await _tick(tester, const Duration(milliseconds: 1));
      expect(h.setup.searching, isTrue);
      expect(h.setup.searchCompleted, isTrue);
      expect(h.setup.controlDevices, isEmpty);
      expect(h.session.state.value.connected, isFalse);
      await _tick(tester, const Duration(seconds: 30));
      expect(h.transport.scanStarts, 1);
      expect(h.setup.searching, isTrue);
    },
  );

  testWidgets(
    'audio discovery stays visible through a repeated OS check without BLE',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.setup.setActive(true);
      await _tick(tester);
      expect(h.setup.checkingAudio, isTrue);
      expect(h.transport.scanStarts, 0);
      final firstReads = h.audio.reads;
      await _tick(tester, const Duration(milliseconds: 1999));
      expect(h.setup.checkingAudio, isTrue);
      await _tick(tester, const Duration(milliseconds: 1));
      expect(h.audio.reads, greaterThan(firstReads));
      expect(h.setup.checkingAudio, isTrue);
      expect(h.setup.audioReady, isFalse);
      expect(h.setup.audioSearchCompleted, isTrue);
      expect(h.transport.scanStarts, 0);
      h.setup.beginDiscovery();
      await _tick(tester);
      expect(h.setup.audioSearchCompleted, isFalse);
      expect(h.setup.checkingAudio, isTrue);
      await _tick(tester, const Duration(seconds: 2));
      expect(h.setup.audioSearchCompleted, isTrue);
      expect(h.transport.scanStarts, 0);
    },
  );

  testWidgets('cancelled exposure timer cannot stop a newer discovery', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(() => h.close(tester));
    h.audio.current = _audio;
    h.setup.setActive(true);
    await _tick(tester);
    h.discover();
    await _tick(tester, const Duration(seconds: 1));
    await h.setup.cancel();
    await h.setup.searchControls();
    h.discover();
    await _tick(tester, const Duration(seconds: 1));
    expect(h.setup.searching, isTrue);
    await _tick(tester, const Duration(milliseconds: 999));
    expect(h.setup.searching, isTrue);
    await _tick(tester, const Duration(milliseconds: 1));
    expect(h.setup.searching, isFalse);
    expect(h.transport.scanStarts, 2);
    expect(h.link!.writes, isEmpty);
  });

  testWidgets(
    'background cancels discovery timers and late candidates do not revive it',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      h.discover();
      h.setup.setActive(false);
      await _tick(tester, const Duration(seconds: 3));
      h.discover();
      await _tick(tester);
      expect(h.setup.searching, isFalse);
      expect(h.setup.checkingAudio, isFalse);
      expect(h.session.state.value.connected, isFalse);
      expect(h.transport.scanStarts, 1);
    },
  );

  testWidgets(
    'leaving during the initial audio read cannot start a late scan',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.gate = Completer<AudioConnectionSnapshot>();
      h.setup.setActive(true);
      await _tick(tester);
      h.setup.setActive(false);
      h.audio.gate!.complete(_audio);
      await _tick(tester, const Duration(seconds: 4));
      expect(h.transport.scanStarts, 0);
      expect(h.setup.checkingAudio, isFalse);
    },
  );

  testWidgets(
    'permission guidance stops the finding cue and cannot authorize BLE',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = const AudioConnectionSnapshot(permissionRequired: true);
      h.setup.setActive(true);
      await _tick(tester);
      expect(h.setup.audio.permissionRequired, isTrue);
      expect(h.setup.checkingAudio, isFalse);
      expect(h.transport.scanStarts, 0);
      await _tick(tester, const Duration(seconds: 3));
      expect(h.transport.scanStarts, 0);
    },
  );
}
