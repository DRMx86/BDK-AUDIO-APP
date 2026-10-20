import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/connection/universal_ble_transport.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'session_test.dart' show NativePlatform;

class _UnclosedNative extends NativePlatform {
  _UnclosedNative(this.throwOnDisconnect);
  final bool throwOnDisconnect;
  @override
  Future<void> disconnect(String deviceId) async {
    disconnectCalls++;
    if (throwOnDisconnect) throw StateError('native close rejected');
    // A returned call alone does not prove disconnection.
  }
}

void main() {
  for (final throws in [false, true]) {
    test(
      'failed discovery propagates native cleanup uncertainty when close ${throws ? 'throws' : 'stays connected'}',
      () async {
        final native = _UnclosedNative(throws)..services = [];
        UniversalBle.setInstance(native);
        final adapter = UniversalBleTransport(
          timeout: const Duration(milliseconds: 50),
        );
        final session = SpeakerSession(
          adapter,
          operationTimeout: const Duration(seconds: 1),
        );
        try {
          await expectLater(
            session.connect('aa:bb:cc:dd:ee:01'),
            throwsA(isA<Exception>()),
          );
          expect(native.connections, 1);
          expect(native.disconnectCalls, greaterThanOrEqualTo(1));
          expect(native.writes, isEmpty);
          expect(session.state.value.phase, ConnectionPhase.error);
          expect(
            session.cleanupUncertain,
            isTrue,
            reason: 'No returned BleLink must not erase failed native cleanup.',
          );
          expect(
            session.state.value.message,
            contains('compatible BDK speaker service'),
          );
        } finally {
          session.dispose();
        }
      },
    );
  }
}
