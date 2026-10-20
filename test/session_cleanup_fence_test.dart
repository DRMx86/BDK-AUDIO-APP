import 'dart:async';

import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test.dart' show FakeLink, FakeTransport, fullStatus;

class _GatedCloseLink extends FakeLink {
  _GatedCloseLink(super.deviceId);

  final closeGate = Completer<void>();
  int disposals = 0;

  @override
  Future<void> disconnect() async {
    operations.add('disconnect');
    await closeGate.future;
  }

  @override
  void dispose() => disposals++;
}

class _Transport extends FakeTransport {
  final connectionAttempts = <String>[];

  @override
  Future<BleLink> connect(String id) {
    connectionAttempts.add(id);
    return super.connect(id);
  }
}

void main() {
  late _Transport transport;
  late _GatedCloseLink oldLink;
  late FakeLink replacement;
  late SpeakerSession session;

  setUp(() {
    transport = _Transport();
    oldLink = _GatedCloseLink('speaker-a');
    replacement = FakeLink('speaker-b');
    for (final link in [oldLink, replacement]) {
      link.onWrite = (packet) {
        if (packet.first == 0xf0) link.status(fullStatus);
      };
    }
    transport.links.addAll([oldLink, replacement]);
    session = SpeakerSession(
      transport,
      operationTimeout: const Duration(milliseconds: 60),
    );
  });

  tearDown(() async {
    if (!oldLink.closeGate.isCompleted) oldLink.closeGate.complete();
    session.dispose();
    await transport.close();
  });

  Future<void> loseOldLink() async {
    await session.connect(oldLink.deviceId);
    oldLink.disconnectController.add(
      const BleDisconnect(reason: 'supervision timeout'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(session.state.value.phase, ConnectionPhase.error);
    expect(oldLink.operations, contains('disconnect'));
    expect(oldLink.disposals, 0);
  }

  test('replacement connect waits for failed link cleanup', () async {
    await loseOldLink();
    final connecting = session.connect(replacement.deviceId);
    await Future<void>.delayed(Duration.zero);

    expect(transport.connectionAttempts, ['speaker-a']);
    expect(replacement.writes, isEmpty);

    oldLink.closeGate.complete();
    await Future<void>.delayed(Duration.zero);
    await connecting;
    expect(oldLink.disposals, 1);
    expect(transport.connectionAttempts, ['speaker-a', 'speaker-b']);
    expect(session.state.value.deviceId, 'speaker-b');
    expect(session.state.value.connected, isTrue);

    oldLink.status([1, 12, 12, 12]);
    oldLink.disconnectController.add(const BleDisconnect(reason: 'late loss'));
    expect(session.state.value.connected, isTrue);
    expect(session.state.value.eq.values, [0, -1, 2]);
  });

  test('scan waits for failed link cleanup', () async {
    await loseOldLink();
    final scanning = session.scan();
    await Future<void>.delayed(Duration.zero);
    expect(transport.scanStarts, 0);

    oldLink.closeGate.complete();
    await Future<void>.delayed(Duration.zero);
    await scanning;
    expect(oldLink.disposals, 1);
    expect(transport.scanStarts, 1);
    await session.stopScan();
  });

  test('error phase listener cannot bypass cleanup fence', () async {
    await session.connect(oldLink.deviceId);
    Future<void>? scanning;
    void scanOnError() {
      if (session.state.value.phase == ConnectionPhase.error) {
        scanning = session.scan();
        scanning!.ignore();
      }
    }

    session.state.addListener(scanOnError);
    oldLink.disconnectController.add(const BleDisconnect(reason: 'link lost'));
    await Future<void>.delayed(Duration.zero);
    expect(scanning, isNotNull);
    expect(transport.scanStarts, 0);
    session.state.removeListener(scanOnError);

    oldLink.closeGate.complete();
    await Future<void>.delayed(Duration.zero);
    await scanning;
    expect(transport.scanStarts, 1);
    await session.stopScan();
  });

  for (final dispose in [false, true]) {
    test(
      '${dispose ? 'dispose' : 'disconnect'} cancels connect waiting for cleanup',
      () async {
        await loseOldLink();
        final connecting = session.connect(replacement.deviceId);
        final rejected = expectLater(
          connecting,
          throwsA(isA<SpeakerSessionException>()),
        );
        await Future<void>.delayed(Duration.zero);
        Future<void>? disconnecting;
        if (dispose) {
          session.dispose();
        } else {
          disconnecting = session.disconnect();
        }
        oldLink.closeGate.complete();
        await Future<void>.delayed(Duration.zero);
        await rejected;
        await disconnecting;
        expect(transport.connectionAttempts, ['speaker-a']);
        expect(replacement.writes, isEmpty);
      },
    );

    test(
      '${dispose ? 'dispose' : 'stopScan'} cancels scan waiting for cleanup',
      () async {
        await loseOldLink();
        final scanning = session.scan();
        await Future<void>.delayed(Duration.zero);
        if (dispose) {
          session.dispose();
        } else {
          await session.stopScan();
        }
        oldLink.closeGate.complete();
        await Future<void>.delayed(Duration.zero);
        await scanning;
        expect(transport.scanStarts, 0);
      },
    );
  }

  test('native cleanup is bounded and reports uncertain disconnect', () async {
    await session.connect(oldLink.deviceId);
    var finished = false;
    final disconnecting = session.disconnect().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await disconnecting;
    expect(oldLink.disposals, 1);
    expect(session.state.value.connected, isFalse);
    expect(session.state.value.message, contains('native disconnect failed'));
    expect(session.state.value.message, contains('TimeoutException'));
    expect(session.cleanupUncertain, isTrue);
  });

  test('failed link cleanup timeout warns before manual recovery', () async {
    await loseOldLink();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(session.state.value.phase, ConnectionPhase.error);
    expect(session.state.value.message, contains('native disconnect failed'));
    expect(session.state.value.message, contains('TimeoutException'));
    expect(session.cleanupUncertain, isTrue);

    await session.connect(replacement.deviceId);
    expect(session.state.value.connected, isTrue);
    expect(session.cleanupUncertain, isFalse);
  });

  test(
    'link loss cancels active ACK and queued command before native close',
    () async {
      await session.connect(oldLink.deviceId);
      final active = session.setEq(EqGains(1, 0, 0));
      final queued = session.setLed(const LedSettings(effect: 21));
      final failures = Future.wait([
        expectLater(
          active.timeout(const Duration(milliseconds: 20)),
          throwsA(isA<SpeakerSessionException>()),
        ),
        expectLater(
          queued.timeout(const Duration(milliseconds: 20)),
          throwsA(isA<SpeakerSessionException>()),
        ),
      ]);
      oldLink.disconnectController.add(
        const BleDisconnect(reason: 'link lost'),
      );
      await failures;
      expect(oldLink.closeGate.isCompleted, isFalse);
      expect(oldLink.disposals, 0);
      expect(oldLink.writes.where((packet) => packet.first == 5), isEmpty);
    },
  );

  test('link loss cancels exclusive lease before native close', () async {
    await session.connect(oldLink.deviceId);
    final waiting = Completer<void>();
    final transfer = session.withExclusiveWriter<void>((_) => waiting.future);
    final failure = expectLater(
      transfer.timeout(const Duration(milliseconds: 20)),
      throwsA(isA<SpeakerSessionException>()),
    );
    oldLink.disconnectController.add(const BleDisconnect(reason: 'link lost'));
    await failure;
    expect(oldLink.closeGate.isCompleted, isFalse);
    expect(oldLink.disposals, 0);
    waiting.complete();
  });
}
