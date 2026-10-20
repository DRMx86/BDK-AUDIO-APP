import 'dart:async';
import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/transfers/sound_transfer_controller.dart';
import 'package:bdk_audio/features/transfers/sound_transfer_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'sound_transfer_test_support.dart';

Future<void> turn() => Future<void>.delayed(Duration.zero);

void main() {
  late SoundTestRig rig;
  late SoundTransferController controller;
  setUp(() async {
    rig = SoundTestRig();
    await rig.connect();
    controller = SoundTransferController(
      session: rig.session,
      packetTimeout: const Duration(milliseconds: 30),
      completionTimeout: const Duration(milliseconds: 40),
      overallTimeout: const Duration(seconds: 2),
    );
  });
  tearDown(() async {
    controller.dispose();
    await rig.close();
  });

  test('shipping parity reads presence after upload COMPLETE', () async {
    rig.link.soundFlags = 0;
    rig.link.fullStatus();
    rig.link.onWrite = (packet) async {
      if (packet.first == 0x12 || packet.first == 0x13) {
        rig.link.status([0x31]);
      }
      if (packet.first == 0x14) {
        // The upload receipt has no slot flags. Only the later requested
        // full status reveals the installed sound.
        rig.link.soundFlags = 4;
        rig.link.status([0x32]);
      }
    };

    expect(
      await controller.upload(soundType: 2, wav: soundWav()),
      SoundTransferResult.completed,
    );

    expect(rig.link.writes.last, [0xf0]);
    expect(controller.state.value.observedSoundFlags, 4);
    expect(rig.session.state.value.soundFlags, 4);
    expect(rig.link.disconnectCalls, 0);
  });

  test(
    'shipping parity retains COMPLETE when presence readback times out',
    () async {
      rig.link.autoStatus = false;
      rig.respondUpload();

      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.completed,
      );

      expect(controller.state.value.phase, SoundTransferPhase.completed);
      expect(controller.state.value.message, contains('presence'));
      expect(controller.state.value.observedSoundFlags, isNull);
      expect(rig.session.state.value.connected, isTrue);
      expect(rig.link.disconnectCalls, 0);
    },
  );

  test(
    'shipping parity does not turn absent readback into confirmed presence',
    () async {
      rig.link.soundFlags = 0;
      rig.link.fullStatus();
      rig.respondUpload();

      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.completed,
      );

      expect(controller.state.value.observedSoundFlags, 0);
      expect(controller.state.value.message, contains('presence'));
      expect(rig.session.state.value.soundFlags, 0);
      expect(rig.link.disconnectCalls, 0);
    },
  );

  test(
    'shipping parity does not carry a completed receipt into a new connection',
    () async {
      rig.respondUpload();
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.completed,
      );

      await rig.session.disconnect();
      await rig.reconnect();

      expect(controller.state.value.phase, SoundTransferPhase.idle);
      expect(controller.state.value.operation, isNull);
    },
  );

  test(
    'shipping parity clears pending presence receipts before a new connection',
    () async {
      controller.dispose();
      controller = SoundTransferController(
        session: rig.session,
        packetTimeout: const Duration(seconds: 1),
      );
      final oldLink = rig.link;
      final requested = Completer<void>(), oldAtt = Completer<void>();
      oldLink.autoStatus = false;
      oldLink.onWrite = (packet) async {
        if (packet.first == 0x12 || packet.first == 0x13) {
          oldLink.status([0x31]);
        }
        if (packet.first == 0x14) oldLink.status([0x32]);
        if (packet.first == 0xf0) {
          requested.complete();
          await oldAtt.future;
        }
      };

      final upload = controller.upload(soundType: 0, wav: soundWav());
      await requested.future;
      expect(controller.state.value.uploadCompleted, isTrue);
      expect(controller.state.value.phase, SoundTransferPhase.verifying);
      expect(oldAtt.isCompleted, isFalse);

      // Snapshot synchronously: session cancellation may drain the old lease
      // before reconnect, but its receipt must clear at disconnection itself.
      final disconnect = rig.session.disconnect();
      final atDisconnect = controller.state.value;
      await disconnect;
      await rig.reconnect();
      final atReconnect = controller.state.value;
      expect(oldAtt.isCompleted, isFalse);

      // Native callbacks may still arrive from the old link after a new one
      // has synchronized. Neither the old reply nor ATT may revive its receipt.
      oldLink.status([6, 1]);
      oldAtt.complete();
      expect(await upload, SoundTransferResult.completed);
      await turn();
      final afterLateCallbacks = controller.state.value;
      final snapshots = [atDisconnect, atReconnect, afterLateCallbacks];
      expect(
        snapshots.map((value) => value.phase),
        everyElement(SoundTransferPhase.idle),
      );
      expect(
        snapshots.map((value) => value.uploadCompleted),
        everyElement(isFalse),
      );
      expect(
        snapshots.map((value) => value.presenceConfirmed),
        everyElement(isFalse),
      );
      expect(snapshots.map((value) => value.operation), everyElement(isNull));
    },
  );

  test(
    'upload uses the real session lease and succeeds only on worker COMPLETE at END',
    () async {
      rig.respondUpload();
      final wav = soundWav(dataBytes: 600);
      expect(
        await controller.upload(soundType: 2, wav: wav),
        SoundTransferResult.completed,
      );
      expect(rig.link.writes.map((packet) => packet.first), [
        0x12,
        0x13,
        0x13,
        0x13,
        0x14,
        0xf0,
      ]);
      expect(rig.link.writes.first, [0x12, 2, 132, 2, 0]);
      expect(
        rig.link.writes
            .where((packet) => packet.first == 0x13)
            .expand((packet) => packet.skip(2)),
        wav,
      );
      expect(rig.link.maxActiveWrites, 1);
      expect(rig.link.withResponses, everyElement(isTrue));
      expect(controller.state.value.acknowledgedBytes, 644);
      expect(controller.state.value.phase, SoundTransferPhase.completed);
      expect(rig.link.disconnectCalls, 0);
      expect(rig.session.state.value.connected, isTrue);
    },
  );

  test(
    'START READY before ATT completion cannot release the next packet',
    () async {
      final gate = Completer<void>();
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x12) {
          rig.link.status([0x31]);
          await gate.future;
        }
        if (packet.first == 0x13) rig.link.status([0x31]);
        if (packet.first == 0x14) rig.link.status([0x32]);
      };
      final transfer = controller.upload(soundType: 0, wav: soundWav());
      await turn();
      expect(rig.link.writes, hasLength(1));
      expect(controller.state.value.acknowledgedBytes, 0);
      gate.complete();
      expect(await transfer, SoundTransferResult.completed);
    },
  );

  test(
    'DATA READY waits for ATT and retains exclusive ownership against setting writes',
    () async {
      final gate = Completer<void>();
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x12) rig.link.status([0x31]);
        if (packet.first == 0x13) {
          rig.link.status([0x31]);
          if (packet[1] == 0) await gate.future;
        }
        if (packet.first == 0x14) rig.link.status([0x32]);
      };
      final transfer = controller.upload(
        soundType: 0,
        wav: soundWav(dataBytes: 600),
      );
      await turn();
      expect(rig.link.writes.map((packet) => packet.first), [0x12, 0x13]);
      expect(controller.state.value.acknowledgedBytes, 0);
      await expectLater(
        rig.session.setEq(const EqGains.zero()),
        throwsA(isA<Exception>()),
      );
      gate.complete();
      expect(await transfer, SoundTransferResult.completed);
      expect(rig.link.maxActiveWrites, 1);
    },
  );

  test(
    'END COMPLETE before its ATT callback still cannot complete upload',
    () async {
      final gate = Completer<void>();
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x12 || packet.first == 0x13) {
          rig.link.status([0x31]);
        }
        if (packet.first == 0x14) {
          rig.link.status([0x32]);
          await gate.future;
        }
      };
      var done = false;
      final transfer = controller.upload(soundType: 0, wav: soundWav()).then((
        value,
      ) {
        done = true;
        return value;
      });
      await turn();
      expect(done, isFalse);
      expect(controller.state.value.phase, SoundTransferPhase.finishing);
      gate.complete();
      expect(await transfer, SoundTransferResult.completed);
    },
  );

  test(
    'generic END ACK and reported100 percent never replace SOUND_COMPLETE',
    () async {
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x12 || packet.first == 0x13) {
          rig.link.status([0x31]);
        }
        if (packet.first == 0x14) {
          rig.link.status([0x10, 0x14]);
          rig.link.status([0x30, 100]);
        }
      };
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.failed,
      );
      expect(
        controller.state.value.errorFamily,
        SoundTransferErrorFamily.timeout,
      );
      expect(controller.state.value.phase, SoundTransferPhase.failed);
      expect(controller.state.value.requiresReconnect, isTrue);
      expect(rig.link.disconnectCalls, 1);
    },
  );

  test(
    'wrong-stage COMPLETE and duplicate READY bursts cannot skip data packets',
    () async {
      rig.link.status([0x31]);
      rig.link.status([0x32]);
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x12 || packet.first == 0x13) {
          rig.link.status([0x32]);
          rig.link.status([0x31]);
          rig.link.status([0x31]);
        }
      };
      expect(
        await controller.upload(soundType: 0, wav: soundWav(dataBytes: 600)),
        SoundTransferResult.failed,
      );
      expect(
        rig.link.writes.where((packet) => packet.first == 0x13),
        hasLength(3),
      );
      expect(
        rig.link.writes.where((packet) => packet.first == 0x14),
        hasLength(1),
      );
    },
  );

  test(
    'worker FAILED preserves its raw family/code and forces a new connection',
    () async {
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x12) rig.link.status([0x31]);
        if (packet.first == 0x13) rig.link.status([0x33, 7]);
      };
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.failed,
      );
      expect(
        controller.state.value.errorFamily,
        SoundTransferErrorFamily.worker,
      );
      expect(controller.state.value.errorCode, 7);
      expect(controller.state.value.previousSoundMayBeLost, isTrue);
      expect(rig.link.disconnectCalls, 1);
      expect(rig.link.writes.any((packet) => packet.first == 0x14), isFalse);
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.disabled,
      );
    },
  );

  test(
    'generic error is correlated to the pending command and retains its raw code',
    () async {
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x12) {
          rig.link.status([0x11, 5, 3]);
          rig.link.status([0x31]);
        }
        if (packet.first == 0x13) rig.link.status([0x11, 0x13, 0x21]);
      };
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.failed,
      );
      expect(
        controller.state.value.errorFamily,
        SoundTransferErrorFamily.command,
      );
      expect(controller.state.value.errorCode, 0x21);
    },
  );

  test(
    'manual cancellation during a pending ATT write disconnects without an abort packet',
    () async {
      final gate = Completer<void>();
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x12) await gate.future;
      };
      final transfer = controller.upload(soundType: 0, wav: soundWav());
      await turn();
      final cancelled = controller.cancel();
      gate.complete();
      await cancelled;
      expect(await transfer, SoundTransferResult.cancelled);
      expect(rig.link.disconnectCalls, 1);
      expect(rig.link.writes.map((packet) => packet.first), [0x12]);
      expect(controller.state.value.requiresReconnect, isTrue);
    },
  );

  test(
    'audio disconnect cancels transfer and never emits another data packet',
    () async {
      rig.link.onWrite = (_) async {};
      final transfer = controller.upload(soundType: 0, wav: soundWav());
      await turn();
      await controller.onAudioDisconnected();
      expect(await transfer, SoundTransferResult.cancelled);
      expect(rig.link.writes, hasLength(1));
      expect(rig.link.disconnectCalls, 1);
    },
  );

  test(
    'stale notifications from the old link cannot confirm a new transfer epoch',
    () async {
      final old = rig.link;
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.failed,
      );
      final fresh = await rig.reconnect();
      final transfer = controller.upload(soundType: 0, wav: soundWav());
      await turn();
      old.status([0x31]);
      old.status([0x32]);
      old.status([0x33, 9]);
      await turn();
      expect(fresh.writes, hasLength(1));
      fresh.onWrite = (packet) async {
        if (packet.first == 0x13) fresh.status([0x31]);
        if (packet.first == 0x14) fresh.status([0x32]);
      };
      fresh.status([0x31]);
      expect(await transfer, SoundTransferResult.completed);
    },
  );

  test(
    'mute requires matching command ACK and matching sound flags, in either order',
    () async {
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x10) {
          rig.link.status([6, 0x8f]);
          rig.link.status([0x10, 0x11]);
        }
      };
      var done = false;
      final result = controller.setMuted(true).then((value) {
        done = true;
        return value;
      });
      await turn();
      expect(done, isFalse);
      rig.link.status([0x10, 0x10]);
      expect(await result, SoundTransferResult.completed);
      expect(controller.state.value.observedSoundFlags, 0x8f);
    },
  );

  test(
    'mute ACK without direct flags uses a leased status request before success',
    () async {
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x10) {
          rig.link.soundFlags = 0x8f;
          rig.link.status([0x10, 0x10]);
        }
      };
      expect(await controller.setMuted(true), SoundTransferResult.completed);
      expect(rig.link.writes.map((packet) => packet.first), [0x10, 0xf0]);
      expect(controller.state.value.observedSoundFlags, 0x8f);
    },
  );

  test(
    'delete confirms only the requested presence bit after its ACK',
    () async {
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x11) {
          rig.link.status([0x10, 0x11]);
          rig.link.status([6, 13]);
        }
      };
      expect(await controller.delete(1), SoundTransferResult.completed);
      expect(controller.state.value.observedSoundFlags, 13);
      expect(rig.link.writes.single, [0x11, 1]);
    },
  );

  test(
    'ATT and command ACK without sound status cannot claim mute/delete success',
    () async {
      rig.link.autoStatus = false;
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x10) rig.link.status([0x10, 0x10]);
      };
      expect(await controller.setMuted(true), SoundTransferResult.failed);
      expect(controller.state.value.requiresReconnect, isTrue);
      expect(rig.link.disconnectCalls, 1);
    },
  );

  test(
    'preview guard performs no transfer, status-request or disconnect writes',
    () async {
      controller.dispose();
      controller = SoundTransferController(
        session: rig.session,
        allowChanges: false,
      );
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.disabled,
      );
      expect(await controller.delete(1), SoundTransferResult.disabled);
      expect(await controller.setMuted(true), SoundTransferResult.disabled);
      expect(rig.link.writes, isEmpty);
      expect(rig.link.disconnectCalls, 0);
    },
  );

  test(
    'invalid prepared WAV is rejected independently before acquiring or mutating a link',
    () async {
      final invalid = soundWav()..[22] = 2;
      expect(
        await controller.upload(soundType: 0, wav: invalid),
        SoundTransferResult.failed,
      );
      expect(
        controller.state.value.errorFamily,
        SoundTransferErrorFamily.validation,
      );
      expect(rig.link.writes, isEmpty);
      expect(rig.link.disconnectCalls, 0);
      expect(rig.session.state.value.connected, isTrue);
    },
  );

  test(
    'caller mutation after start cannot alter the owned WAV bytes sent later',
    () async {
      final wav = soundWav(), original = wav.toList();
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x13) rig.link.status([0x31]);
        if (packet.first == 0x14) rig.link.status([0x32]);
      };
      final transfer = controller.upload(soundType: 0, wav: wav);
      await turn();
      wav.fillRange(0, wav.length, 255);
      rig.link.status([0x31]);
      expect(await transfer, SoundTransferResult.completed);
      expect(
        rig.link.writes
            .where((packet) => packet.first == 0x13)
            .expand((packet) => packet.skip(2)),
        original,
      );
    },
  );

  test(
    'a busy shared setting writer is not disconnected or overwritten',
    () async {
      final eq = rig.session.setEq(const EqGains.zero());
      await turn();
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.failed,
      );
      expect(rig.link.disconnectCalls, 0);
      expect(rig.link.writes.map((packet) => packet.first), [1]);
      rig.link.status([0x10, 1]);
      await eq;
    },
  );

  test(
    'dispose cancels an active transfer without late state notifications',
    () async {
      var notifications = 0;
      controller.state.addListener(() => notifications++);
      final transfer = controller.upload(soundType: 0, wav: soundWav());
      await turn();
      controller.dispose();
      final count = notifications;
      expect(await transfer, SoundTransferResult.cancelled);
      expect(notifications, count);
      expect(rig.link.disconnectCalls, 1);
      rig.link.status([0x31]);
      rig.link.status([0x32]);
      await turn();
      expect(notifications, count);
    },
  );

  test(
    'BLE loss while waiting aborts the lease and cannot continue on delayed responses',
    () async {
      final transfer = controller.upload(soundType: 0, wav: soundWav());
      await turn();
      rig.link.disconnectController.add(
        const BleDisconnect(reason: 'radio lost'),
      );
      expect(await transfer, SoundTransferResult.failed);
      rig.link.status([0x31]);
      await turn();
      expect(rig.link.writes, hasLength(1));
      expect(
        controller.state.value.errorFamily,
        SoundTransferErrorFamily.connection,
      );
    },
  );

  test(
    'completed notification cannot cancel an already confirmed upload',
    () async {
      rig.respondUpload();
      controller.state.addListener(() {
        if (controller.state.value.phase == SoundTransferPhase.completed) {
          unawaited(controller.cancel());
        }
      });
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.completed,
      );
      expect(rig.link.disconnectCalls, 0);
      expect(controller.state.value.phase, SoundTransferPhase.completed);
    },
  );

  test(
    'successful worker terminal boundary permits a second upload without reconnect',
    () async {
      rig.respondUpload();
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.completed,
      );
      rig.link.status([0x31]);
      rig.link.status([0x32]);
      expect(
        await controller.upload(soundType: 1, wav: soundWav()),
        SoundTransferResult.completed,
      );
      expect(
        rig.link.writes.where((packet) => packet.first == 0x14),
        hasLength(2),
      );
      expect(rig.link.disconnectCalls, 0);
    },
  );

  test(
    'own busy operation rejects parallel commands without replacing progress',
    () async {
      final upload = controller.upload(soundType: 2, wav: soundWav());
      await turn();
      expect(await controller.setMuted(true), SoundTransferResult.busy);
      expect(await controller.delete(1), SoundTransferResult.busy);
      expect(controller.state.value.soundType, 2);
      expect(rig.link.writes.map((packet) => packet.first), [0x12]);
      await controller.cancel();
      expect(await upload, SoundTransferResult.cancelled);
    },
  );

  test(
    'READY followed by ATT failure never sends DATA or reports success',
    () async {
      rig.link.onWrite = (packet) async {
        rig.link.status([0x31]);
        throw StateError('ATT rejected');
      };
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.failed,
      );
      expect(rig.link.writes.map((packet) => packet.first), [0x12]);
      expect(controller.state.value.requiresReconnect, isTrue);
      expect(rig.link.disconnectCalls, 1);
    },
  );

  test(
    'deadline disconnects a never-completing ATT write and releases cancellation',
    () async {
      final gate = Completer<void>();
      rig.link.onWrite = (_) => gate.future;
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.failed,
      );
      expect(
        controller.state.value.errorFamily,
        SoundTransferErrorFamily.timeout,
      );
      expect(rig.link.disconnectCalls, 1);
      rig.link.status([0x31]);
      rig.link.status([0x32]);
      gate.complete();
      await turn();
      expect(rig.link.writes.map((packet) => packet.first), [0x12]);
    },
  );

  test(
    'overall deadline bounds a responsive but slow multi-packet worker',
    () async {
      controller.dispose();
      controller = SoundTransferController(
        session: rig.session,
        packetTimeout: const Duration(milliseconds: 200),
        overallTimeout: const Duration(milliseconds: 30),
      );
      rig.link.onWrite = (packet) async {
        await Future<void>.delayed(const Duration(milliseconds: 15));
        if (packet.first == 0x12 || packet.first == 0x13) {
          rig.link.status([0x31]);
        }
        if (packet.first == 0x14) rig.link.status([0x32]);
      };
      expect(
        await controller.upload(soundType: 0, wav: soundWav(dataBytes: 600)),
        SoundTransferResult.failed,
      );
      expect(
        controller.state.value.errorFamily,
        SoundTransferErrorFamily.timeout,
      );
      expect(rig.link.writes.any((packet) => packet.first == 0x14), isFalse);
      expect(rig.link.disconnectCalls, 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    },
  );

  test(
    'contradicting flags before readback ATT completes cannot confirm mute',
    () async {
      rig.link.autoStatus = false;
      rig.link.onWrite = (packet) async {
        if (packet.first == 0x10) rig.link.status([0x10, 0x10]);
        if (packet.first == 0xf0) {
          rig.link.status([6, 0x8f]);
          rig.link.status([6, 15]);
        }
      };
      expect(await controller.setMuted(true), SoundTransferResult.failed);
      expect(controller.state.value.observedSoundFlags, 15);
      expect(controller.state.value.requiresReconnect, isTrue);
    },
  );

  test('status alone and wrong-command ACK cannot confirm delete', () async {
    rig.link.onWrite = (packet) async {
      rig.link.status([6, 13]);
      rig.link.status([0x10, 0x10]);
    };
    expect(await controller.delete(1), SoundTransferResult.failed);
    expect(
      controller.state.value.errorFamily,
      SoundTransferErrorFamily.timeout,
    );
    expect(rig.link.writes.single, [0x11, 1]);
  });

  test(
    'worker FAILED between packet windows prevents the next DATA write',
    () async {
      rig.respondUpload();
      controller.state.addListener(() {
        if (controller.state.value.phase == SoundTransferPhase.uploading &&
            controller.state.value.acknowledgedBytes == 0) {
          rig.link.status([0x33, 8]);
        }
      });
      expect(
        await controller.upload(soundType: 0, wav: soundWav()),
        SoundTransferResult.failed,
      );
      expect(rig.link.writes.map((packet) => packet.first), [0x12]);
      expect(
        controller.state.value.errorFamily,
        SoundTransferErrorFamily.worker,
      );
      expect(controller.state.value.errorCode, 8);
    },
  );

  test(
    '20-byte baseline session is rejected even though packetization supports that capacity',
    () async {
      final small = SoundTestRig(capacity: 20);
      await expectLater(small.connect(), throwsA(isA<Exception>()));
      expect(small.link.writes, isEmpty);
      await small.close();
    },
  );
}
