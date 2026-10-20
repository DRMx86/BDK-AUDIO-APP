import 'dart:async';

import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test.dart' as fixtures;

class _DelayedStopTransport extends fixtures.FakeTransport {
  final stopped = Completer<void>();
  @override
  Future<void> stopScan() async {
    await super.stopScan();
    await stopped.future;
  }
}

void main() {
  test(
    'continuous scan error stops native work before replacement starts',
    () async {
      final transport = _DelayedStopTransport();
      final session = SpeakerSession(transport);
      try {
        await session.scan(continuous: true);
        transport.scanController.addError(StateError('radio failed'));
        await Future<void>.delayed(Duration.zero);
        expect(session.state.value.phase, ConnectionPhase.error);
        expect(transport.scanStops, 1);
        expect(session.state.value.connected, isFalse);
        final replacement = session.scan(continuous: true);
        await Future<void>.delayed(Duration.zero);
        expect(transport.scanStarts, 1);
        transport.stopped.complete();
        await replacement;
        expect(transport.scanStarts, 2);
        expect(session.state.value.phase, ConnectionPhase.scanning);
        await session.stopScan();
      } finally {
        if (!transport.stopped.isCompleted) transport.stopped.complete();
        session.dispose();
        await transport.close();
      }
    },
  );
}
