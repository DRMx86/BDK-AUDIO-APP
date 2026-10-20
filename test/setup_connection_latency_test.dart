import 'dart:async';

import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/connection/speaker_setup_controller.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/persistence/saved_speaker_store.dart';
import 'package:bdk_audio/platform/audio_connection_adapter.dart';
import 'package:bdk_audio/protocol/speaker_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test.dart' as fixtures;
import 'setup_controller_test.dart' show FakeAudio;

const _id = 'AA:BB:CC:DD:EE:01';
const _verifiedAudio = AudioConnectionSnapshot(
  devices: [AudioDeviceIdentity(id: _id, name: 'BDK SPEAKER')],
);

class _PendingSave implements SavedSpeakerStore {
  final gate = Completer<void>();
  int saves = 0;
  @override
  Future<SavedSpeaker?> load() async => null;
  @override
  Future<void> save(SavedSpeaker speaker) async {
    saves++;
    await gate.future;
  }
}

class _Harness {
  _Harness({SavedSpeakerStore? store, bool automatic = true}) {
    setup = SpeakerSetupController(
      session,
      audio,
      autoConnectEnabled: automatic,
      autoDiscoverEnabled: true,
      pollInterval: Duration.zero,
      savedSpeakerStore: store,
    );
  }
  final audio = FakeAudio();
  final transport = fixtures.FakeTransport();
  late final session = SpeakerSession(transport);
  late final SpeakerSetupController setup;

  fixtures.FakeLink discover({
    String id = _id,
    bool fullStatus = true,
    List<String> services = const [SpeakerProtocol.service],
  }) {
    final link = fixtures.FakeLink(id);
    if (fullStatus) {
      link.onWrite = (packet) {
        if (packet.first == 0xf0) link.status(fixtures.fullStatus);
      };
    }
    transport.links.add(link);
    transport.scanController.add(
      DiscoveredSpeaker(id: id, name: 'BDK SPEAKER', services: services),
    );
    return link;
  }

  Future<void> close(WidgetTester tester) => tester.runAsync(() async {
    setup.dispose();
    session.dispose();
    await transport.close();
  });
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
  testWidgets(
    'verified exact service candidate connects within 500 ms without five-second dwell',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = _verifiedAudio;
      h.setup.setActive(true);
      await _tick(tester);
      expect(h.transport.scanStarts, 1);
      await _tick(tester, const Duration(milliseconds: 100));
      final unrelated = h.discover(id: 'AA:BB:CC:DD:EE:02');
      final link = h.discover();
      await _tick(tester, const Duration(milliseconds: 399));
      expect(h.session.state.value.connected, isTrue);
      expect(h.session.state.value.deviceId, _id);
      expect(h.setup.connecting, isFalse);
      expect(link.writes, [
        [0xf0],
      ]);
      expect(unrelated.writes, isEmpty);
    },
  );

  testWidgets(
    'fast discovery still requires complete requested speaker status',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = _verifiedAudio;
      h.setup.setActive(true);
      await _tick(tester);
      final link = h.discover(fullStatus: false);
      await _tick(tester, const Duration(milliseconds: 500));
      expect(h.session.state.value.phase, ConnectionPhase.synchronizing);
      expect(h.setup.connecting, isTrue);
      link.status([1, 0, 0, 0]);
      await _tick(tester);
      expect(h.session.state.value.connected, isFalse);
      link.status(fixtures.fullStatus);
      await _tick(tester);
      expect(h.session.state.value.connected, isTrue);
      expect(h.setup.connecting, isFalse);
    },
  );

  for (final mode in [
    'no audio',
    'permission required',
    'manual audio',
    'multiple audio identities',
    'wrong MAC',
    'missing advertised service',
    'ambiguous matching entries',
  ]) {
    testWidgets('$mode cannot authorize the fast automatic connection', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = switch (mode) {
        'no audio' => const AudioConnectionSnapshot(),
        'permission required' => const AudioConnectionSnapshot(
          devices: [AudioDeviceIdentity(id: _id, name: 'BDK SPEAKER')],
          permissionRequired: true,
        ),
        'manual audio' => const AudioConnectionSnapshot(
          canVerifyIdentity: false,
        ),
        'multiple audio identities' => const AudioConnectionSnapshot(
          devices: [
            AudioDeviceIdentity(id: _id, name: 'BDK SPEAKER'),
            AudioDeviceIdentity(id: 'other', name: 'BDK OTHER'),
          ],
        ),
        _ => _verifiedAudio,
      };
      h.setup.setActive(true);
      await _tick(tester);
      if (mode == 'manual audio') h.setup.confirmManagedAudio();
      final link = h.discover(
        id: mode == 'wrong MAC' ? 'AA:BB:CC:DD:EE:02' : _id,
        services: mode == 'missing advertised service'
            ? const []
            : const [SpeakerProtocol.service],
      );
      if (mode == 'ambiguous matching entries') {
        h.discover(id: _id.toLowerCase());
      }
      await _tick(tester, const Duration(milliseconds: 500));
      expect(h.session.state.value.connected, isFalse);
      expect(link.writes, isEmpty);
      await h.setup.cancel();
    });
  }

  testWidgets('empty search keeps five-second help and continues scanning', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(() => h.close(tester));
    h.audio.current = _verifiedAudio;
    h.setup.setActive(true);
    await _tick(tester);
    await _tick(tester, const Duration(milliseconds: 4999));
    expect(h.setup.searchCompleted, isFalse);
    expect(h.setup.searching, isTrue);
    await _tick(tester, const Duration(milliseconds: 1));
    expect(h.setup.searchCompleted, isTrue);
    expect(h.setup.searching, isTrue);
    expect(h.session.state.value.connected, isFalse);
    await h.setup.cancel();
  });

  for (final action in ['cancel', 'background', 'audio identity change']) {
    testWidgets(
      '$action invalidates a queued fast candidate before native use',
      (tester) async {
        final h = _Harness();
        addTearDown(() => h.close(tester));
        h.audio.current = _verifiedAudio;
        h.setup.setActive(true);
        await _tick(tester);
        final link = h.discover();
        switch (action) {
          case 'cancel':
            await h.setup.cancel();
            break;
          case 'background':
            h.setup.setActive(false);
            break;
          case 'audio identity change':
            h.audio.current = const AudioConnectionSnapshot();
            break;
        }
        await _tick(tester, const Duration(milliseconds: 500));
        expect(h.session.state.value.connected, isFalse);
        expect(link.writes, isEmpty);
        await h.setup.cancel();
      },
    );
  }

  testWidgets('read-only discovery never uses the automatic fast connection', (
    tester,
  ) async {
    final h = _Harness(automatic: false);
    addTearDown(() => h.close(tester));
    h.audio.current = _verifiedAudio;
    h.setup.setActive(true);
    await _tick(tester);
    final link = h.discover();
    await _tick(tester, const Duration(milliseconds: 500));
    expect(h.session.state.value.connected, isFalse);
    expect(link.writes, isEmpty);
    await h.setup.cancel();
  });

  testWidgets(
    'a pending preference save does not hold synchronized controls busy',
    (tester) async {
      final store = _PendingSave();
      final h = _Harness(store: store, automatic: false);
      addTearDown(() async {
        if (!store.gate.isCompleted) store.gate.complete();
        await h.close(tester);
      });
      h.audio.current = _verifiedAudio;
      await h.setup.refresh();
      await h.setup.searchControls();
      h.discover();
      final connecting = h.setup.connectControls(_id);
      await _tick(tester);
      expect(store.saves, 1);
      expect(h.session.state.value.connected, isTrue);
      expect(
        h.setup.connecting,
        isFalse,
        reason:
            'saving a preference is separate from verified control readiness',
      );
      store.gate.complete();
      await connecting;
    },
  );
}
