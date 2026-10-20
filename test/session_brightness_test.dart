import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'session_test.dart' show FakeTransport, FakeLink, fullStatus;

void main() {
  late FakeTransport transport;
  late FakeLink link;
  late SpeakerSession session;
  setUp(() async {
    transport = FakeTransport();
    link = FakeLink('speaker-a');
    transport.links.add(link);
    session = SpeakerSession(
      transport,
      ackTimeout: const Duration(milliseconds: 80),
    );
    link.onWrite = (packet) {
      if (packet.first == 0xf0) link.status(fullStatus);
    };
    await session.connect(link.deviceId);
  });
  tearDown(() async {
    session.dispose();
    await transport.close();
  });

  test(
    'brightness alone uses 07 and retains the running effect settings',
    () async {
      final before = session.state.value.led;
      link.onWrite = (packet) => link.status([0x10, packet.first]);
      await session.setLed(before.copyWith(brightness: 80));
      expect(link.writes.last, [7, 80]);
      expect(session.state.value.led, before.copyWith(brightness: 80));
      await session.setLed(before.copyWith(brightness: 0));
      expect(link.writes.last, [7, 0]);
    },
  );

  test('queued brightness uses 07 after an accepted effect change', () async {
    final desired = session.state.value.led.copyWith(effect: 21);
    link.onWrite = (packet) {
      if (packet.first == 7) link.status([0x10, 7]);
    };
    final effect = session.setLed(desired);
    final brightness = session.setLed(desired.copyWith(brightness: 25));
    link.status([0x10, 5]);
    await effect;
    await brightness;
    expect(link.writes.skip(1).map((p) => p.first), [5, 7]);
    expect(link.writes.last, [7, 25]);
    expect(session.state.value.led, desired.copyWith(brightness: 25));
  });

  test(
    'refused effect is not skipped by a subsequent brightness request',
    () async {
      final desired = session.state.value.led.copyWith(effect: 21);
      var count = 0;
      link.onWrite = (packet) {
        if (++count > 1) link.status([0x10, packet.first]);
      };
      final effect = session.setLed(desired);
      final refusal = expectLater(effect, throwsA(isA<Exception>()));
      final brightness = session.setLed(desired.copyWith(brightness: 25));
      link.status([0x11, 5, 2]);
      await refusal;
      await brightness;
      expect(link.writes.skip(1).map((p) => p.first), [5, 5]);
      expect(session.state.value.led, desired.copyWith(brightness: 25));
    },
  );

  test(
    'coalesced brightness keeps its last value and requires the matching ACK',
    () async {
      final before = session.state.value.led;
      var writes = 0;
      link.onWrite = (packet) {
        if (++writes > 1) link.status([0x10, packet.first]);
      };
      var firstDone = false;
      final first = session
          .setLed(before.copyWith(brightness: 80))
          .then((_) => firstDone = true);
      final second = session.setLed(before.copyWith(brightness: 30));
      final last = session.setLed(before.copyWith(brightness: 40));
      link.status([0x10, 5]);
      await Future<void>.delayed(Duration.zero);
      expect(firstDone, isFalse);
      link.status([0x10, 7]);
      await first;
      await second;
      await last;
      expect(link.writes.skip(1), [
        [7, 80],
        [7, 40],
      ]);
      expect(session.state.value.led.brightness, 40);
    },
  );
}
