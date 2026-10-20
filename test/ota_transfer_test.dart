import 'dart:async';
import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/updates/firmware_image.dart';
import 'package:bdk_audio/features/updates/ota_transfer_controller.dart';
import 'package:bdk_audio/features/updates/ota_transfer_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ota_transfer_fixture.dart';
import 'ota_transfer_test_support.dart';

Future<void> otaTurn() => Future<void>.delayed(Duration.zero);
void main() {
  late OtaTestRig rig;
  late OtaTransferController controller;
  late FirmwareImage image;
  setUp(() async {
    rig = OtaTestRig();
    await rig.connect();
    image = FirmwareImage.parse(otaImageBytes());
    controller = OtaTransferController(
      session: rig.session,
      packetTimeout: const Duration(milliseconds: 40),
      completionTimeout: const Duration(milliseconds: 50),
      abortTimeout: const Duration(milliseconds: 30),
      verificationTimeout: const Duration(milliseconds: 40),
      overallTimeout: const Duration(seconds: 2),
    );
  });
  tearDown(() async {
    controller.dispose();
    await rig.close();
  });
  test(
    'BEGIN READY and END COMPLETE bound ATT-only DATA and leave reported version unverified',
    () async {
      rig.respondTransfer();
      expect(await controller.transfer(image), OtaTransferResult.transferred);
      expect(rig.link.writes.map((p) => p.first), [0x20, 0x21, 0x21, 0x22]);
      expect(rig.link.writes.first, [0x20, 80, 1, 0, 0]);
      expect(
        rig.link.writes.where((p) => p.first == 0x21).expand((p) => p.skip(2)),
        image.bytes,
      );
      expect(rig.link.writes[1][1], 1);
      expect(rig.link.maxActiveWrites, 1);
      expect(rig.link.withResponses, everyElement(isTrue));
      expect(controller.state.value.phase, OtaTransferPhase.awaitingRestart);
      expect(controller.state.value.transferConfirmed, isTrue);
      expect(controller.state.value.attCompletedBytes, image.sizeBytes);
      expect(controller.canVerify, isFalse);
      expect(rig.link.disconnectCalls, 0);
      expect(controller.canTransfer, isFalse);
    },
  );
  test(
    'early READY still waits ATT and START generic ACK is not semantic READY',
    () async {
      final gate = Completer<void>();
      rig.link.onWrite = (p) async {
        if (p.first == 0x20) {
          rig.link.status([0x10, 0x20]);
          rig.link.status([0x21]);
          await gate.future;
        }
        if (p.first == 0x22) rig.link.status([0x22]);
      };
      final work = controller.transfer(image);
      await otaTurn();
      expect(rig.link.writes, hasLength(1));
      gate.complete();
      expect(await work, OtaTransferResult.transferred);
    },
  );
  test('generic BEGIN ACK alone times out without DATA', () async {
    rig.link.onWrite = (p) async {
      if (p.first == 0x20) rig.link.status([0x10, 0x20]);
    };
    expect(await controller.transfer(image), OtaTransferResult.failed);
    expect(rig.link.writes.map((p) => p.first), [0x20]);
    expect(controller.state.value.errorFamily, OtaTransferErrorFamily.timeout);
    expect(rig.link.disconnectCalls, 1);
  });
  test(
    'END COMPLETE before ATT callback does not release completion',
    () async {
      final gate = Completer<void>();
      rig.link.onWrite = (p) async {
        if (p.first == 0x20) rig.link.status([0x21]);
        if (p.first == 0x22) {
          rig.link.status([0x22]);
          await gate.future;
        }
      };
      var done = false;
      final work = controller.transfer(image).then((v) {
        done = true;
        return v;
      });
      await otaTurn();
      expect(done, isFalse);
      expect(controller.state.value.phase, OtaTransferPhase.finishing);
      gate.complete();
      expect(await work, OtaTransferResult.transferred);
    },
  );
  test(
    'missing COMPLETE and reported100 never become timer-based success',
    () async {
      rig.link.onWrite = (p) async {
        if (p.first == 0x20) rig.link.status([0x21]);
        if (p.first == 0x22) {
          rig.link.status([0x10, 0x22]);
          rig.link.status([0x20, 100]);
        }
      };
      expect(await controller.transfer(image), OtaTransferResult.failed);
      expect(controller.state.value.transferConfirmed, isFalse);
      expect(controller.state.value.requiresReconnect, isTrue);
      expect(rig.link.disconnectCalls, 1);
    },
  );
  test(
    'worker failure retains raw namespace code and stops subsequent DATA',
    () async {
      rig.link.onWrite = (p) async {
        if (p.first == 0x20) rig.link.status([0x21]);
        if (p.first == 0x21) rig.link.status([0x23, 0x12]);
      };
      expect(await controller.transfer(image), OtaTransferResult.failed);
      expect(controller.state.value.errorFamily, OtaTransferErrorFamily.worker);
      expect(controller.state.value.errorCode, 0x12);
      expect(rig.link.writes.map((p) => p.first), [0x20, 0x21]);
      expect(await controller.transfer(image), OtaTransferResult.disabled);
    },
  );
  test(
    'wrong-stage idle and duplicate READY/COMPLETE do not skip BEGIN or END',
    () async {
      rig.link.status([0x21]);
      rig.link.status([0x22]);
      rig.link.onWrite = (p) async {
        if (p.first == 0x20) {
          rig.link.status([0x22]);
          rig.link.status([0x21]);
          rig.link.status([0x21]);
        }
        if (p.first == 0x21) {
          rig.link.status([0x21]);
          rig.link.status([0x22]);
        }
      };
      expect(await controller.transfer(image), OtaTransferResult.failed);
      expect(rig.link.writes.last, [0x22]);
    },
  );
  test(
    'matched generic errors reject BEGIN and unrelated error is ignored',
    () async {
      rig.link.onWrite = (p) async {
        if (p.first == 0x20) {
          rig.link.status([0x11, 1, 3]);
          rig.link.status([0x11, 0x20, 0x10]);
        }
      };
      expect(await controller.transfer(image), OtaTransferResult.failed);
      expect(
        controller.state.value.errorFamily,
        OtaTransferErrorFamily.command,
      );
      expect(controller.state.value.errorCode, 0x10);
      expect(rig.link.writes, hasLength(1));
    },
  );
  test(
    'DATA ATT failure is not retried even after READY or progress',
    () async {
      rig.link.onWrite = (p) async {
        if (p.first == 0x20) rig.link.status([0x21]);
        if (p.first == 0x21) {
          rig.link.status([0x20, 50]);
          throw StateError('uncertain write');
        }
      };
      expect(await controller.transfer(image), OtaTransferResult.failed);
      expect(rig.link.writes.map((p) => p.first), [0x20, 0x21]);
      expect(rig.link.disconnectCalls, 1);
    },
  );
  test(
    'manual cancellation while BEGIN ATT pending skips unsafe ABORT and disconnects',
    () async {
      final gate = Completer<void>();
      rig.link.onWrite = (p) async {
        if (p.first == 0x20) await gate.future;
      };
      final work = controller.transfer(image);
      await otaTurn();
      final cancelled = controller.cancel();
      gate.complete();
      await cancelled;
      expect(await work, OtaTransferResult.cancelled);
      expect(rig.link.writes.map((p) => p.first), [0x20]);
      expect(rig.link.disconnectCalls, 1);
    },
  );
  test(
    'cancel after BEGIN ATT awaits matching ABORT ACK and ATT then disconnects',
    () async {
      rig.link.onWrite = (p) async {
        if (p.first == 0x23) rig.link.status([0x10, 0x23]);
      };
      final work = controller.transfer(image);
      await otaTurn();
      await controller.cancel();
      expect(await work, OtaTransferResult.cancelled);
      expect(rig.link.writes.map((p) => p.first), [0x20, 0x23]);
      expect(controller.state.value.abortConfirmed, isTrue);
      expect(controller.state.value.transferConfirmed, isFalse);
      expect(rig.link.disconnectCalls, 1);
    },
  );
  test('wrong ABORT ACK/COMPLETE cannot claim confirmed abort', () async {
    rig.link.onWrite = (p) async {
      if (p.first == 0x23) {
        rig.link.status([0x10, 0x22]);
        rig.link.status([0x22]);
      }
    };
    final work = controller.transfer(image);
    await otaTurn();
    await controller.cancel();
    expect(await work, OtaTransferResult.cancelled);
    expect(controller.state.value.abortConfirmed, isFalse);
    expect(rig.link.disconnectCalls, 1);
  });
  test(
    'new synchronized same-device epoch and fresh F0 verify only reported version',
    () async {
      rig.respondTransfer();
      expect(await controller.transfer(image), OtaTransferResult.transferred);
      final before = rig.link.writes.length;
      expect(
        await controller.verifyAfterReconnect(),
        OtaTransferResult.verificationUnavailable,
      );
      expect(rig.link.writes.length, before);
      await rig.session.disconnect();
      final fresh = await rig.reconnect();
      expect(controller.canVerify, isTrue);
      expect(
        await controller.verifyAfterReconnect(),
        OtaTransferResult.versionMatched,
      );
      expect(fresh.writes.single, [0xf0]);
      expect(controller.state.value.reportedVersion, '2.4.0');
      expect(controller.state.value.phase, OtaTransferPhase.versionMatched);
    },
  );
  test(
    'fresh mismatched version is explicit and no image rollback claim',
    () async {
      rig.respondTransfer();
      await controller.transfer(image);
      await rig.session.disconnect();
      await rig.reconnect(version: '1.0.0');
      expect(
        await controller.verifyAfterReconnect(),
        OtaTransferResult.versionMismatch,
      );
      expect(controller.state.value.transferConfirmed, isTrue);
      expect(controller.state.value.reportedVersion, '1.0.0');
      expect(
        controller.state.value.errorFamily,
        OtaTransferErrorFamily.verification,
      );
    },
  );
  test(
    'verification never reconnects to or writes a different speaker',
    () async {
      rig.respondTransfer();
      await controller.transfer(image);
      await rig.session.disconnect();
      final other = await rig.reconnect(id: 'BB');
      expect(controller.canVerify, isFalse);
      expect(
        await controller.verifyAfterReconnect(),
        OtaTransferResult.verificationUnavailable,
      );
      expect(other.writes, isEmpty);
      expect(other.disconnectCalls, 0);
    },
  );
  test(
    'cached or unsolicited version does not substitute for fresh FULL_STATUS response',
    () async {
      rig.respondTransfer();
      await controller.transfer(image);
      await rig.session.disconnect();
      final fresh = await rig.reconnect();
      fresh.autoStatus = false;
      fresh.onWrite = (p) async {
        if (p.first == 0xf0) fresh.status([4, ...'2.4.0'.codeUnits]);
      };
      expect(await controller.verifyAfterReconnect(), OtaTransferResult.failed);
      expect(
        controller.state.value.errorFamily,
        OtaTransferErrorFamily.timeout,
      );
      expect(fresh.disconnectCalls, 1);
    },
  );
  test(
    'explicit expected reported version is separate from app descriptor version',
    () async {
      rig.respondTransfer();
      await controller.transfer(image, expectedVersion: 'BDK-2.4');
      await rig.session.disconnect();
      await rig.reconnect(version: 'BDK-2.4');
      expect(
        await controller.verifyAfterReconnect(),
        OtaTransferResult.versionMatched,
      );
      expect(controller.state.value.expectedVersion, 'BDK-2.4');
    },
  );
  test('preview guard performs ZERO OTA F0 or disconnect operations', () async {
    controller.dispose();
    controller = OtaTransferController(
      session: rig.session,
      allowChanges: false,
    );
    expect(await controller.transfer(image), OtaTransferResult.disabled);
    expect(await controller.verifyAfterReconnect(), OtaTransferResult.disabled);
    await controller.cancel();
    await controller.onAudioDisconnected();
    controller.dispose();
    expect(rig.link.writes, isEmpty);
    expect(rig.link.disconnectCalls, 0);
  });
  test(
    'active lease excludes normal settings and a parallel OTA call',
    () async {
      final work = controller.transfer(image);
      await otaTurn();
      expect(await controller.transfer(image), OtaTransferResult.busy);
      await expectLater(
        rig.session.setEq(const EqGains.zero()),
        throwsA(isA<Exception>()),
      );
      await controller.cancel();
      expect(await work, OtaTransferResult.cancelled);
    },
  );
  test(
    'BLE loss and stale old-link responses cannot continue a transfer',
    () async {
      final old = rig.link;
      final work = controller.transfer(image);
      await otaTurn();
      old.disconnectController.add(const BleDisconnect(reason: 'lost'));
      expect(await work, OtaTransferResult.failed);
      final fresh = await rig.reconnect();
      rig.respondTransfer();
      old.status([0x21]);
      old.status([0x22]);
      old.status([0x23, 7]);
      expect(await controller.transfer(image), OtaTransferResult.transferred);
      expect(fresh.writes.last, [0x22]);
    },
  );
  test(
    'dispose cancels without late notifier changes or ownership of session',
    () async {
      final gate = Completer<void>();
      rig.link.onWrite = (p) async {
        if (p.first == 0x20) await gate.future;
      };
      var notices = 0;
      controller.state.addListener(() => notices++);
      final work = controller.transfer(image);
      await otaTurn();
      controller.dispose();
      final count = notices;
      gate.complete();
      expect(await work, OtaTransferResult.cancelled);
      expect(notices, count);
      expect(rig.link.disconnectCalls, 1);
      expect(rig.session.state.value.connected, isFalse);
    },
  );
  test(
    'W20 remains blocked by safe baseline session sync despite packetizer support',
    () async {
      final small = OtaTestRig(capacity: 20);
      await expectLater(small.connect(), throwsA(isA<Exception>()));
      expect(small.link.writes, isEmpty);
      await small.close();
    },
  );
  test('abort ACK before ATT cannot confirm cancellation early', () async {
    final gate = Completer<void>();
    rig.link.onWrite = (p) async {
      if (p.first == 0x23) {
        rig.link.status([0x10, 0x23]);
        await gate.future;
      }
    };
    final work = controller.transfer(image);
    await otaTurn();
    var done = false;
    final cancel = controller.cancel().then((_) => done = true);
    await otaTurn();
    expect(done, isFalse);
    expect(controller.state.value.abortConfirmed, isFalse);
    expect(rig.link.disconnectCalls, 0);
    gate.complete();
    await cancel;
    expect(await work, OtaTransferResult.cancelled);
    expect(controller.state.value.abortConfirmed, isTrue);
  });
  test(
    'never completing ABORT ATT has a finite deadline and then disconnects',
    () async {
      final gate = Completer<void>();
      rig.link.onWrite = (p) async {
        if (p.first == 0x23) await gate.future;
      };
      final work = controller.transfer(image);
      await otaTurn();
      await controller.cancel();
      expect(await work, OtaTransferResult.cancelled);
      expect(rig.link.disconnectCalls, 1);
      expect(controller.state.value.abortConfirmed, isFalse);
      gate.complete();
      await otaTurn();
    },
  );
  test(
    'terminal COMPLETE and ATT survive immediate expected disconnect',
    () async {
      rig.respondTransfer();
      var rebooted = false;
      controller.state.addListener(() {
        if (!rebooted &&
            controller.state.value.phase == OtaTransferPhase.awaitingRestart) {
          rebooted = true;
          unawaited(rig.session.disconnect());
        }
      });
      expect(await controller.transfer(image), OtaTransferResult.transferred);
      expect(controller.state.value.transferConfirmed, isTrue);
      await rig.reconnect();
      expect(
        await controller.verifyAfterReconnect(),
        OtaTransferResult.versionMatched,
      );
    },
  );
  test(
    'cancellation during terminal notification sends no ABORT or disconnect',
    () async {
      rig.respondTransfer();
      controller.state.addListener(() {
        if (controller.state.value.phase == OtaTransferPhase.awaitingRestart) {
          unawaited(controller.cancel());
        }
      });
      expect(await controller.transfer(image), OtaTransferResult.transferred);
      expect(rig.link.writes.any((p) => p.first == 0x23), isFalse);
      expect(rig.link.disconnectCalls, 0);
    },
  );
  test(
    'COMPLETE without END ATT followed by disconnect is uncertain not transferred',
    () async {
      final gate = Completer<void>();
      rig.link.onWrite = (p) async {
        if (p.first == 0x20) rig.link.status([0x21]);
        if (p.first == 0x22) {
          rig.link.status([0x22]);
          await gate.future;
        }
      };
      final work = controller.transfer(image);
      await otaTurn();
      rig.link.disconnectController.add(
        const BleDisconnect(reason: 'reboot too early'),
      );
      expect(await work, OtaTransferResult.failed);
      expect(controller.state.value.transferConfirmed, isFalse);
      gate.complete();
      await otaTurn();
    },
  );
  test(
    'old transfer cleanup never disconnects a newly selected speaker',
    () async {
      final old = rig.link;
      final gate = old.closeGate = Completer<void>();
      old.onWrite = (p) async {
        if (p.first == 0x20) throw StateError('old ATT failed');
      };
      final work = controller.transfer(image);
      await otaTurn();
      final fresh = await rig.reconnect(id: 'BB', version: '3.0.0');
      gate.complete();
      expect(await work, OtaTransferResult.failed);
      expect(rig.session.state.value.connected, isTrue);
      expect(rig.session.state.value.deviceId, 'BB');
      expect(fresh.disconnectCalls, 0);
      expect(fresh.writes, isEmpty);
    },
  );
  test(
    'delayed DATA command ERROR while END awaits completion is not ignored',
    () async {
      rig.link.onWrite = (p) async {
        if (p.first == 0x20) rig.link.status([0x21]);
        if (p.first == 0x22) rig.link.status([0x11, 0x21, 0x11]);
      };
      expect(await controller.transfer(image), OtaTransferResult.failed);
      expect(
        controller.state.value.errorFamily,
        OtaTransferErrorFamily.command,
      );
      expect(controller.state.value.errorCode, 0x11);
    },
  );
  test(
    'fresh FULL_STATUS still waits its ATT callback before matching reported version',
    () async {
      rig.respondTransfer();
      await controller.transfer(image);
      await rig.session.disconnect();
      final fresh = await rig.reconnect();
      final gate = Completer<void>();
      fresh.onWrite = (p) async {
        if (p.first == 0xf0) await gate.future;
      };
      var done = false;
      final work = controller.verifyAfterReconnect().then((value) {
        done = true;
        return value;
      });
      await otaTurn();
      expect(done, isFalse);
      expect(controller.state.value.phase, OtaTransferPhase.verifying);
      gate.complete();
      expect(await work, OtaTransferResult.versionMatched);
    },
  );
  test(
    'unknown fresh reported version remains unavailable instead of guessed success',
    () async {
      rig.respondTransfer();
      await controller.transfer(image);
      await rig.session.disconnect();
      await rig.reconnect(version: '');
      expect(
        await controller.verifyAfterReconnect(),
        OtaTransferResult.verificationUnavailable,
      );
      expect(controller.state.value.transferConfirmed, isTrue);
      expect(
        controller.state.value.phase,
        OtaTransferPhase.verificationUnavailable,
      );
    },
  );
  test('overall deadline bounds responsive but slow DATA writes', () async {
    controller.dispose();
    controller = OtaTransferController(
      session: rig.session,
      packetTimeout: const Duration(milliseconds: 100),
      overallTimeout: const Duration(milliseconds: 25),
    );
    rig.link.onWrite = (p) async {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      if (p.first == 0x20) rig.link.status([0x21]);
      if (p.first == 0x22) rig.link.status([0x22]);
    };
    expect(await controller.transfer(image), OtaTransferResult.failed);
    expect(controller.state.value.errorFamily, OtaTransferErrorFamily.timeout);
    expect(rig.link.writes.any((p) => p.first == 0x22), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  test(
    'shared setting lease contention never disconnects unrelated pending work',
    () async {
      final eq = rig.session.setEq(const EqGains.zero());
      await otaTurn();
      expect(await controller.transfer(image), OtaTransferResult.failed);
      expect(rig.link.disconnectCalls, 0);
      expect(rig.link.writes.map((p) => p.first), [1]);
      rig.link.status([0x10, 1]);
      await eq;
    },
  );
  test(
    'malformed expected version fails before any writer lease or mutation',
    () async {
      expect(
        await controller.transfer(image, expectedVersion: '\n'),
        OtaTransferResult.failed,
      );
      expect(
        controller.state.value.errorFamily,
        OtaTransferErrorFamily.validation,
      );
      expect(rig.link.writes, isEmpty);
      expect(rig.link.disconnectCalls, 0);
    },
  );
  test(
    'shared writer rejection preserves the last confirmed transfer receipt',
    () async {
      rig.respondTransfer();
      await controller.transfer(image);
      await rig.session.disconnect();
      await rig.reconnect();
      final eq = rig.session.setEq(const EqGains.zero());
      await otaTurn();
      expect(
        await controller.transfer(image, expectedVersion: 'new-attempt'),
        OtaTransferResult.failed,
      );
      rig.link.status([0x10, 1]);
      await eq;
      expect(controller.canVerify, isTrue);
      expect(
        await controller.verifyAfterReconnect(),
        OtaTransferResult.versionMatched,
      );
      expect(controller.state.value.expectedVersion, '2.4.0');
    },
  );
  test(
    'disabled preview state explicitly identifies policy without reconnect requirement',
    () async {
      controller.dispose();
      controller = OtaTransferController(
        session: rig.session,
        allowChanges: false,
      );
      expect(await controller.transfer(image), OtaTransferResult.disabled);
      expect(controller.state.value.errorFamily, OtaTransferErrorFamily.policy);
      expect(controller.state.value.requiresReconnect, isFalse);
      expect(rig.link.writes, isEmpty);
    },
  );
}
