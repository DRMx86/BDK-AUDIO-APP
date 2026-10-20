import 'dart:async';

import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/connection/speaker_setup_controller.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/platform/audio_connection_adapter.dart';
import 'package:bdk_audio/protocol/speaker_protocol.dart';
import 'package:bdk_audio/persistence/saved_speaker_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test.dart' as fixtures;
import 'setup_controller_test.dart' show FakeAudio;

const _id = 'AA:BB:CC:DD:EE:01';
const _audio = AudioConnectionSnapshot(
  devices: [AudioDeviceIdentity(id: _id, name: 'BDK SPEAKER')],
);

class _MemorySpeakers implements SavedSpeakerStore {
  SavedSpeaker? value;
  Object? loadError, saveError;
  Completer<SavedSpeaker?>? loadGate;
  final saved = <SavedSpeaker>[];
  @override
  Future<SavedSpeaker?> load() async {
    if (loadError != null) throw loadError!;
    return loadGate == null ? value : await loadGate!.future;
  }

  @override
  Future<void> save(SavedSpeaker speaker) async {
    if (saveError != null) throw saveError!;
    saved.add(speaker);
    value = speaker;
  }
}

class _Harness {
  _Harness({
    bool enabled = true,
    SavedSpeakerStore? store,
    fixtures.FakeTransport? transport,
    DateTime Function()? now,
    Duration operationTimeout = const Duration(seconds: 1),
  }) : transport = transport ?? fixtures.FakeTransport() {
    session = SpeakerSession(
      this.transport,
      operationTimeout: operationTimeout,
      syncTimeout: const Duration(seconds: 1),
    );
    setup = SpeakerSetupController(
      session,
      audio,
      pollInterval: Duration.zero,
      autoConnectEnabled: enabled,
      savedSpeakerStore: store,
      now: now,
    );
  }
  final audio = FakeAudio();
  final fixtures.FakeTransport transport;
  final _links = <fixtures.FakeLink>{};
  late final SpeakerSession session;
  late final SpeakerSetupController setup;

  fixtures.FakeLink discover({
    String id = _id,
    bool reply = true,
    fixtures.FakeLink? deviceLink,
    List<String> services = const [SpeakerProtocol.service],
  }) {
    final link = deviceLink ?? fixtures.FakeLink(id);
    _links.add(link);
    if (reply) {
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

  Future<void> close(WidgetTester tester) async {
    await tester.runAsync(() async {
      setup.dispose();
      session.dispose();
      await transport.close();
      for (final link in _links.where(
        (link) => !transport.links.contains(link),
      )) {
        await link.close();
      }
    });
  }
}

Future<void> _tick(
  WidgetTester tester, [
  Duration duration = Duration.zero,
]) async {
  await tester.pump(duration);
  // Stream.cancel can return the SDK's cached root-zone Future._nullFuture.
  // Drain that real microtask queue separately from the virtual widget clock.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

class _DelayedStop extends fixtures.FakeTransport {
  Completer<void>? stopGate;
  @override
  Future<void> stopScan() async {
    scanStops++;
    await stopGate?.future;
  }
}

class _DelayedClose extends fixtures.FakeLink {
  _DelayedClose(super.deviceId);
  final gate = Completer<void>();
  @override
  Future<void> disconnect() {
    operations.add('disconnect');
    return gate.future;
  }
}

void main() {
  testWidgets(
    'verified audio automatically discovers and synchronizes its sole control device',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      expect(h.transport.scanStarts, 1);
      final wrong = h.discover(id: 'other');
      final matching = h.discover();
      await _tick(tester, const Duration(milliseconds: 1999));
      expect(matching.writes, isEmpty);
      await _tick(tester, const Duration(milliseconds: 1));
      expect(h.session.state.value.connected, isTrue);
      expect(h.session.state.value.deviceId, _id);
      expect(matching.writes, [
        [0xf0],
      ]);
      expect(wrong.writes, isEmpty);
    },
  );

  testWidgets('automatic connection still waits for a full status packet', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(() => h.close(tester));
    h.audio.current = _audio;
    h.setup.setActive(true);
    await _tick(tester);
    final link = h.discover(reply: false);
    await _tick(tester, const Duration(seconds: 2));
    expect(h.session.state.value.phase, ConnectionPhase.synchronizing);
    link.status([1, 0, 0, 0]);
    await _tick(tester);
    expect(h.session.state.value.connected, isFalse);
    link.status(fixtures.fullStatus);
    await _tick(tester);
    expect(h.session.state.value.connected, isTrue);
  });

  for (final mode in [
    'no audio',
    'permission',
    'manual',
    'disabled',
    'ambiguous',
  ]) {
    testWidgets('$mode never authorizes automatic BLE discovery', (
      tester,
    ) async {
      final h = _Harness(enabled: mode != 'disabled');
      addTearDown(() => h.close(tester));
      h.audio.current = switch (mode) {
        'permission' => const AudioConnectionSnapshot(
          devices: [AudioDeviceIdentity(id: _id, name: 'BDK SPEAKER')],
          permissionRequired: true,
        ),
        'manual' => const AudioConnectionSnapshot(canVerifyIdentity: false),
        'disabled' => _audio,
        'ambiguous' => const AudioConnectionSnapshot(
          devices: [
            AudioDeviceIdentity(id: _id, name: 'BDK A'),
            AudioDeviceIdentity(id: 'other', name: 'BDK B'),
          ],
        ),
        _ => const AudioConnectionSnapshot(),
      };
      h.setup.setActive(true);
      await _tick(tester);
      if (mode == 'manual') h.setup.confirmManagedAudio();
      await _tick(tester, const Duration(seconds: 10));
      expect(h.transport.scanStarts, 0);
      expect(h.session.state.value.connected, isFalse);
    });
  }

  testWidgets(
    'cancel suppresses pending and resumed automatic work until explicit search',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      final link = h.discover();
      await h.setup.cancel();
      await _tick(tester, const Duration(seconds: 3));
      h.setup.setActive(false);
      h.setup.setActive(true);
      await _tick(tester, const Duration(seconds: 3));
      expect(h.transport.scanStarts, 1);
      expect(link.writes, isEmpty);
      await h.setup.searchControls();
      h.transport.scanController.add(
        const DiscoveredSpeaker(
          id: _id,
          name: 'BDK SPEAKER',
          services: [SpeakerProtocol.service],
        ),
      );
      await _tick(tester, const Duration(seconds: 2));
      expect(h.session.state.value.connected, isTrue);
    },
  );

  testWidgets('background cancels a pending automatic connection', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(() => h.close(tester));
    h.audio.current = _audio;
    h.setup.setActive(true);
    await _tick(tester);
    final link = h.discover();
    h.setup.setActive(false);
    await _tick(tester, const Duration(seconds: 3));
    expect(link.writes, isEmpty);
    expect(h.setup.searching, isFalse);
    h.setup.setActive(true);
    await _tick(tester);
    h.transport.scanController.add(
      const DiscoveredSpeaker(
        id: _id,
        name: 'BDK SPEAKER',
        services: [SpeakerProtocol.service],
      ),
    );
    await _tick(tester, const Duration(seconds: 2));
    expect(h.session.state.value.connected, isTrue);
  });

  testWidgets(
    'saved renamed speaker disambiguates verified audio and is remembered only after full sync',
    (tester) async {
      final store = _MemorySpeakers()
        ..value = const SavedSpeaker(_id, 'Living room');
      final h = _Harness(store: store);
      addTearDown(() => h.close(tester));
      h.audio.current = const AudioConnectionSnapshot(
        devices: [
          AudioDeviceIdentity(id: 'other', name: 'BDK other'),
          AudioDeviceIdentity(id: _id, name: 'Living room'),
        ],
      );
      h.setup.setActive(true);
      await _tick(tester);
      expect(h.setup.selectedAudioId, _id);
      final link = h.discover(reply: false);
      await _tick(tester, const Duration(seconds: 2));
      expect(store.saved, isEmpty);
      link.status(fixtures.fullStatus);
      await _tick(tester);
      expect(store.saved.single.id, _id);
      expect(store.saved.single.name, 'BDK');
      expect(link.writes, [
        [0xf0],
      ]);
    },
  );

  testWidgets(
    'saved identity without matching connected audio never unlocks discovery',
    (tester) async {
      final store = _MemorySpeakers()
        ..value = const SavedSpeaker(_id, 'Living room');
      final h = _Harness(store: store);
      addTearDown(() => h.close(tester));
      h.audio.current = const AudioConnectionSnapshot(
        devices: [AudioDeviceIdentity(id: 'headphones', name: 'Headphones')],
      );
      h.setup.setActive(true);
      await _tick(tester, const Duration(seconds: 30));
      expect(h.setup.audioReady, isFalse);
      expect(h.transport.scanStarts, 0);
      expect(store.saved, isEmpty);
    },
  );

  testWidgets(
    'failed final audio recheck cannot remember an automatic connection',
    (tester) async {
      final store = _MemorySpeakers();
      final h = _Harness(store: store);
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      final link = h.discover();
      link.onWrite = (packet) {
        h.audio.current = const AudioConnectionSnapshot();
        link.status(fixtures.fullStatus);
      };
      await _tick(tester, const Duration(seconds: 2));
      expect(h.session.state.value.connected, isFalse);
      expect(store.saved, isEmpty);
    },
  );

  testWidgets(
    'storage failure leaves a healthy synchronized connection usable',
    (tester) async {
      final store = _MemorySpeakers()
        ..saveError = StateError('storage unavailable');
      final h = _Harness(store: store);
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      h.discover();
      await _tick(tester, const Duration(seconds: 2));
      expect(h.session.state.value.connected, isTrue);
      expect(h.setup.rememberWarning, contains('could not be remembered'));
      expect(h.setup.connecting, isFalse);
    },
  );

  testWidgets(
    'cancel during saved-speaker loading cannot start discovery later',
    (tester) async {
      final store = _MemorySpeakers()..loadGate = Completer<SavedSpeaker?>();
      final h = _Harness(store: store);
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      await h.setup.cancel();
      store.loadGate!.complete(const SavedSpeaker(_id, 'BDK'));
      await _tick(tester, const Duration(seconds: 5));
      expect(h.transport.scanStarts, 0);
      expect(store.saved, isEmpty);
    },
  );

  testWidgets('intentional disconnect does not immediately reconnect', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(() => h.close(tester));
    h.audio.current = _audio;
    h.setup.setActive(true);
    await _tick(tester);
    h.discover();
    await _tick(tester, const Duration(seconds: 2));
    expect(h.session.state.value.connected, isTrue);
    final closing = h.setup.disconnectControls();
    await _tick(tester);
    await closing;
    await _tick(tester, const Duration(seconds: 30));
    expect(h.transport.scanStarts, 1);
    expect(h.session.state.value.connected, isFalse);
  });

  testWidgets('connection failure retries at 2 4 8 seconds then stops', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(() => h.close(tester));
    h.audio.current = _audio;
    h.transport.connectError = StateError('link unavailable');
    h.setup.setActive(true);
    await _tick(tester);
    h.discover();
    await _tick(tester, const Duration(seconds: 2));
    for (var retry = 0; retry < 3; retry++) {
      expect(h.transport.scanStarts, retry + 1);
      await _tick(tester, Duration(milliseconds: (2000 << retry) - 1));
      expect(h.transport.scanStarts, retry + 1);
      await _tick(tester, const Duration(milliseconds: 1));
      expect(h.transport.scanStarts, retry + 2);
      h.discover();
      await _tick(tester, const Duration(seconds: 2));
    }
    expect(h.setup.message, contains('Search again'));
    await _tick(tester, const Duration(minutes: 1));
    expect(h.transport.scanStarts, 4);
  });

  testWidgets('empty discovery timeout also has a finite retry budget', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(() => h.close(tester));
    h.audio.current = _audio;
    h.setup.setActive(true);
    await _tick(tester);
    for (var retry = 0; retry < 3; retry++) {
      await _tick(tester, const Duration(seconds: 15));
      expect(h.setup.searching, isFalse);
      await _tick(tester, Duration(seconds: 2 << retry));
      expect(h.transport.scanStarts, retry + 2);
    }
    await _tick(tester, const Duration(minutes: 1));
    expect(h.setup.searching, isFalse);
    expect(h.transport.scanStarts, 4);
  });

  testWidgets(
    'audio loss during a delayed automatic recheck sends no status request',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      final link = h.discover();
      h.audio.gate = Completer<AudioConnectionSnapshot>();
      await _tick(tester, const Duration(seconds: 2));
      expect(h.setup.connecting, isTrue);
      final pending = h.audio.gate!;
      h.audio.gate = null;
      h.audio.current = const AudioConnectionSnapshot();
      pending.complete(h.audio.current);
      await _tick(tester);
      expect(h.session.state.value.connected, isFalse);
      expect(link.writes, isEmpty);
      expect(h.setup.audioReady, isFalse);
    },
  );

  testWidgets(
    'a new verified audio connection can recover after exhausted retries',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.transport.connectError = StateError('unavailable');
      h.setup.setActive(true);
      await _tick(tester);
      h.discover();
      await _tick(tester, const Duration(seconds: 2));
      for (var retry = 0; retry < 3; retry++) {
        await _tick(tester, Duration(seconds: 2 << retry));
        h.discover();
        await _tick(tester, const Duration(seconds: 2));
      }
      expect(h.transport.scanStarts, 4);
      h.audio.current = const AudioConnectionSnapshot();
      await h.setup.refresh();
      h.transport.connectError = null;
      h.audio.current = _audio;
      await h.setup.refresh();
      await _tick(tester);
      expect(h.transport.scanStarts, 5);
      h.transport.scanController.add(
        const DiscoveredSpeaker(
          id: _id,
          name: 'BDK',
          services: [SpeakerProtocol.service],
        ),
      );
      await _tick(tester, const Duration(seconds: 2));
      expect(h.session.state.value.connected, isTrue);
    },
  );

  testWidgets(
    'disposal during preference loading starts no later native audio query',
    (tester) async {
      final store = _MemorySpeakers()..loadGate = Completer<SavedSpeaker?>();
      final h = _Harness(store: store);
      h.setup.setActive(true);
      await _tick(tester);
      h.setup.dispose();
      store.loadGate!.complete(const SavedSpeaker(_id, 'BDK'));
      await _tick(tester);
      expect(h.audio.reads, 0);
      await tester.runAsync(() async {
        h.session.dispose();
        await h.transport.close();
      });
    },
  );

  testWidgets(
    'final audio confirmation cannot reuse a query started before full status',
    (tester) async {
      final store = _MemorySpeakers();
      final h = _Harness(store: store);
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      final oldQuery = Completer<AudioConnectionSnapshot>();
      final link = h.discover();
      link.onWrite = (_) {
        h.audio.gate = oldQuery;
        unawaited(h.setup.refresh());
        h.audio.current = const AudioConnectionSnapshot();
        link.status(fixtures.fullStatus);
      };
      await _tick(tester, const Duration(seconds: 2));
      expect(h.setup.connecting, isTrue);
      h.audio.gate = null;
      oldQuery.complete(_audio);
      await _tick(tester);
      expect(store.saved, isEmpty);
      expect(h.session.state.value.connected, isFalse);
    },
  );

  testWidgets('explicit search waits for cancelled native scan cleanup', (
    tester,
  ) async {
    final transport = _DelayedStop();
    final h = _Harness(transport: transport);
    addTearDown(() => h.close(tester));
    h.audio.current = _audio;
    h.setup.setActive(true);
    await _tick(tester);
    final gate = Completer<void>();
    transport.stopGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final stopping = h.setup.cancel();
    final restarting = h.setup.searchControls();
    await _tick(tester);
    expect(transport.scanStarts, 1);
    transport.stopGate = null;
    gate.complete();
    await stopping;
    await restarting;
    await _tick(tester);
    expect(transport.scanStarts, 2);
    await h.setup.cancel();
  });

  testWidgets('a stable connection resets backoff for a later real outage', (
    tester,
  ) async {
    final h = _Harness(now: tester.binding.clock.now);
    addTearDown(() => h.close(tester));
    h.audio.current = _audio;
    h.transport.connectError = StateError('initial failure');
    h.setup.setActive(true);
    await _tick(tester);
    h.discover();
    await _tick(tester, const Duration(seconds: 2));
    await _tick(tester, const Duration(seconds: 2));
    h.transport.connectError = null;
    h.transport.links.clear();
    final link = h.discover();
    await _tick(tester, const Duration(seconds: 2));
    expect(h.session.state.value.connected, isTrue);
    await _tick(tester, const Duration(seconds: 30));
    link.disconnectController.add(const BleDisconnect(reason: 'later outage'));
    await _tick(tester);
    await _tick(tester, const Duration(milliseconds: 1999));
    expect(h.transport.scanStarts, 2);
    await _tick(tester, const Duration(milliseconds: 1));
    expect(h.transport.scanStarts, 3);
    await h.setup.cancel();
  });

  testWidgets(
    'rapid ready and lost cycles do not reset the finite retry budget',
    (tester) async {
      final h = _Harness(now: tester.binding.clock.now);
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      var link = h.discover();
      await _tick(tester, const Duration(seconds: 2));
      for (var retry = 0; retry < 3; retry++) {
        expect(h.session.state.value.connected, isTrue);
        link.disconnectController.add(
          const BleDisconnect(reason: 'rapid outage'),
        );
        await _tick(tester);
        await _tick(tester, Duration(seconds: 2 << retry));
        expect(h.transport.scanStarts, retry + 2);
        h.transport.links.clear();
        link = h.discover();
        await _tick(tester, const Duration(seconds: 2));
      }
      link.disconnectController.add(
        const BleDisconnect(reason: 'rapid outage'),
      );
      await _tick(tester, const Duration(minutes: 1));
      expect(h.transport.scanStarts, 4);
      expect(h.setup.message, contains('Search again'));
    },
  );

  testWidgets(
    'uncertain native close stops automatic recovery until manual selection',
    (tester) async {
      final h = _Harness();
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      final link = h.discover();
      await _tick(tester, const Duration(seconds: 2));
      link.disconnectError = StateError('native close failed');
      link.disconnectController.add(const BleDisconnect(reason: 'lost'));
      await _tick(tester);
      expect(h.session.cleanupUncertain, isTrue);
      try {
        await _tick(tester, const Duration(seconds: 10));
        expect(h.transport.scanStarts, 1);
        expect(h.setup.message, contains('Choose your speaker'));
        h.transport.links.clear();
        await h.setup.searchControls();
        final replacement = h.discover();
        await _tick(tester, const Duration(seconds: 3));
        expect(
          replacement.writes,
          isEmpty,
          reason: 'Recovery still needs manual selection.',
        );
        final connecting = h.setup.connectControls(_id);
        await _tick(tester);
        await connecting;
        expect(h.session.state.value.connected, isTrue);
        expect(h.session.cleanupUncertain, isFalse);
        expect(replacement.writes, [
          [0xf0],
        ]);
      } finally {
        await h.setup.cancel();
      }
    },
  );

  testWidgets(
    'close timeout cancels an automatic scan already waiting on cleanup',
    (tester) async {
      final h = _Harness(operationTimeout: const Duration(seconds: 5));
      addTearDown(() => h.close(tester));
      h.audio.current = _audio;
      h.setup.setActive(true);
      await _tick(tester);
      final link = _DelayedClose(_id);
      addTearDown(() {
        if (!link.gate.isCompleted) link.gate.complete();
      });
      h.discover(deviceLink: link);
      await _tick(tester, const Duration(seconds: 2));
      link.disconnectController.add(const BleDisconnect(reason: 'lost'));
      await _tick(tester);
      await _tick(tester, const Duration(seconds: 2));
      expect(
        h.transport.scanStarts,
        1,
        reason: 'Old native close is still pending.',
      );
      try {
        await _tick(tester, const Duration(seconds: 3));
        expect(h.session.cleanupUncertain, isTrue);
        expect(
          h.transport.scanStarts,
          1,
          reason: 'Timeout cannot authorize the queued scan.',
        );
      } finally {
        link.gate.complete();
        await _tick(tester);
        await h.setup.cancel();
      }
    },
  );
}
