import 'dart:async';
import 'package:bdk_audio/features/codec/codec_adapter.dart';
import 'package:bdk_audio/features/codec/codec_controller.dart';
import 'package:bdk_audio/features/codec/codec_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'codec_test_support.dart';

void main() {
  late DateTime clock;
  late FakeCodecAdapter adapter;
  late CodecController controller;
  const requested = CodecPreference(
    codecType: 4,
    sampleRateMask: 8,
    bitsMask: 2,
    channelMask: 2,
  );
  setUp(() {
    clock = DateTime.fromMillisecondsSinceEpoch(100000);
    adapter = FakeCodecAdapter()
      ..onSnapshot = (id) async =>
          codecFixture(id: id ?? 'AA', stamp: clock.millisecondsSinceEpoch);
    controller = CodecController(
      adapter: adapter,
      deviceId: 'AA',
      now: () => clock,
      nativeTimeout: const Duration(milliseconds: 80),
      verificationTimeout: const Duration(milliseconds: 40),
      pollInterval: const Duration(milliseconds: 1),
    );
  });
  tearDown(() => controller.dispose());

  test(
    'initial profile connection retries until codec information is ready',
    () async {
      var reads = 0;
      adapter.onSnapshot = (id) async {
        reads++;
        return reads < 3
            ? CodecSnapshot(access: CodecAccess.initializing)
            : codecFixture(id: id!, stamp: 100000);
      };
      await controller.refresh();
      expect(controller.snapshot!.access, CodecAccess.ready);
      expect(controller.snapshot!.selectedDeviceId, 'AA');
      expect(controller.canEdit, isTrue);
      expect(reads, 3);
      expect(adapter.maxActiveCalls, 1);
      expect(adapter.writes, isEmpty);
    },
  );

  test('initial profile retries stop at the native deadline', () async {
    var reads = 0;
    adapter.onSnapshot = (_) async {
      reads++;
      return CodecSnapshot(access: CodecAccess.initializing);
    };
    await controller.refresh();
    expect(controller.phase, CodecOperationPhase.timedOut);
    expect(controller.busy, isFalse);
    expect(controller.canEdit, isFalse);
    final finishedReads = reads;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(reads, finishedReads);
    expect(adapter.writes, isEmpty);
  });

  test('disposing initialization cancels scheduled profile retries', () async {
    var reads = 0;
    adapter.onSnapshot = (_) async {
      reads++;
      return CodecSnapshot(access: CodecAccess.initializing);
    };
    final refresh = controller.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    controller.dispose();
    await refresh;
    final finishedReads = reads;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(reads, finishedReads);
    expect(adapter.disposed, 1);
    expect(adapter.writes, isEmpty);
  });

  testWidgets(
    'timed out queued refresh never runs after an earlier native read finishes',
    (tester) async {
      // Construct the controller in this test's fake-time zone: its initial
      // Future.value native lease must be drained by tester.pump as well.
      controller.dispose();
      adapter = FakeCodecAdapter();
      controller = CodecController(
        adapter: adapter,
        deviceId: 'AA',
        now: () => clock,
        nativeTimeout: const Duration(milliseconds: 80),
        verificationTimeout: const Duration(milliseconds: 40),
        pollInterval: const Duration(milliseconds: 1),
      );
      final nativeRead = Completer<CodecSnapshot>();
      var reads = 0;
      adapter.onSnapshot = (_) {
        reads++;
        return nativeRead.future;
      };
      final original = controller.refresh();
      await tester.pump();
      expect(reads, 1);
      expect(adapter.activeCalls, 1);
      final retry = controller.refresh();
      await tester.pump();
      await original;
      await tester.pump(const Duration(milliseconds: 81));
      await retry;
      expect(controller.phase, CodecOperationPhase.timedOut);
      expect(reads, 1);
      nativeRead.complete(codecFixture(stamp: 100000));
      await tester.pump();
      expect(reads, 1);
      expect(controller.phase, CodecOperationPhase.timedOut);
      expect(adapter.maxActiveCalls, 1);
    },
  );

  test(
    'delayed same-device broadcast can confirm after temporarily missing readback',
    () async {
      await controller.refresh();
      controller.setPreference(requested);
      var readbacks = 0;
      adapter.onApply = (_, _) async {
        clock = clock.add(const Duration(milliseconds: 10));
        return true;
      };
      adapter.onSnapshot = (_) async {
        if (adapter.writes.isEmpty) return codecFixture(stamp: 100000);
        readbacks++;
        if (readbacks < 3) {
          return CodecSnapshot(
            access: CodecAccess.apiUnavailable,
            devices: const [CodecAudioDevice(id: 'AA', name: 'BDK SPEAKER')],
            selectedDeviceId: 'AA',
            reason: 'Waiting for the next codec broadcast.',
          );
        }
        return codecFixture(rate: 8, stamp: 100010);
      };
      expect(await controller.applyPreference(), CodecApplyResult.confirmed);
      expect(controller.snapshot!.active!.sampleRateMask, 8);
      expect(readbacks, 3);
      expect(adapter.writes, hasLength(1));
      expect(adapter.maxActiveCalls, 1);
    },
  );

  test(
    'missing same-device readback expires without claiming confirmation',
    () async {
      await controller.refresh();
      controller.setPreference(requested);
      adapter.onSnapshot = (_) async => adapter.writes.isEmpty
          ? codecFixture(stamp: 100000)
          : CodecSnapshot(
              access: CodecAccess.apiUnavailable,
              devices: const [CodecAudioDevice(id: 'AA', name: 'BDK SPEAKER')],
              selectedDeviceId: 'AA',
            );
      expect(await controller.applyPreference(), CodecApplyResult.timedOut);
      expect(controller.phase, CodecOperationPhase.timedOut);
      expect(controller.requiresRefresh, isTrue);
      expect(controller.canEdit, isFalse);
      expect(adapter.writes, hasLength(1));
    },
  );

  test(
    'permission loss during verification refuses without readback retries',
    () async {
      await controller.refresh();
      controller.setPreference(requested);
      var readbacks = 0;
      adapter.onSnapshot = (_) async {
        if (adapter.writes.isEmpty) return codecFixture(stamp: 100000);
        readbacks++;
        return CodecSnapshot(access: CodecAccess.permissionRequired);
      };
      expect(await controller.applyPreference(), CodecApplyResult.refused);
      expect(controller.phase, CodecOperationPhase.refused);
      expect(controller.requiresRefresh, isTrue);
      expect(readbacks, 1);
      expect(adapter.writes, hasLength(1));
    },
  );

  test(
    'quality remains a draft and survives supported format changes',
    () async {
      await controller.refresh();
      controller.selectLdacQuality(LdacQuality.high);
      controller.selectSampleRate(8);
      expect(controller.preference!.ldacQuality, LdacQuality.high);
      expect(controller.snapshot!.active!.ldacQuality, LdacQuality.adaptive);
      expect(adapter.writes, isEmpty);
      controller.selectCodec(1);
      expect(controller.preference!.ldacQuality, isNull);
      expect(controller.ldacQualities, isEmpty);
    },
  );

  test(
    'stale local LDAC quality drafts remain editable without native writes',
    () async {
      await controller.refresh();
      expect(controller.ldacQualities, LdacQuality.values);
      clock = clock.add(const Duration(seconds: 6));
      expect(controller.ldacQualities, LdacQuality.values);
      controller.selectLdacQuality(LdacQuality.high);
      expect(controller.preference!.ldacQuality, LdacQuality.high);
      expect(controller.hasFreshObservation, isFalse);
      expect(adapter.writes, isEmpty);
    },
  );

  test(
    'submitted quality cannot confirm a matching format with the old quality',
    () async {
      await controller.refresh();
      controller.selectLdacQuality(LdacQuality.high);
      adapter.onApply = (_, _) async {
        clock = clock.add(const Duration(milliseconds: 1));
        return true;
      };
      expect(await controller.applyPreference(), CodecApplyResult.timedOut);
      expect(adapter.writes.single.cs1, 1000);
      expect(controller.snapshot!.active!.ldacQuality, LdacQuality.adaptive);
      expect(controller.requiresRefresh, isTrue);
    },
  );

  test('quality needs a fresh same-device readback after submission', () async {
    await controller.refresh();
    controller.selectLdacQuality(LdacQuality.balanced);
    var reads = 0;
    adapter.onApply = (_, _) async {
      clock = clock.add(const Duration(milliseconds: 10));
      return true;
    };
    adapter.onSnapshot = (_) async {
      if (adapter.writes.isEmpty) return codecFixture(stamp: 100000);
      reads++;
      return codecFixture(
        qualityCode: 1001,
        stamp: reads == 1 ? 100000 : 100010,
      );
    };
    expect(await controller.applyPreference(), CodecApplyResult.confirmed);
    expect(reads, 2);
    expect(adapter.writes.single.cs2, -7);
    expect(controller.snapshot!.active!.ldacQuality, LdacQuality.balanced);
  });

  test(
    'losing the recognized quality contract refuses before any write',
    () async {
      await controller.refresh();
      clock = clock.add(const Duration(seconds: 6));
      controller.selectLdacQuality(LdacQuality.high);
      adapter.onSnapshot = (_) async =>
          codecFixture(qualityCode: 1009, stamp: clock.millisecondsSinceEpoch);
      expect(await controller.applyPreference(), CodecApplyResult.refused);
      expect(adapter.writes, isEmpty);
    },
  );

  test(
    'default LDAC retains no explicit draft until a user chooses bitrate',
    () async {
      adapter.onSnapshot = (_) async =>
          codecFixture(qualityCode: 0, stamp: 100000);
      await controller.refresh();
      expect(controller.preference!.ldacQuality, isNull);
      expect(controller.snapshot!.active!.ldacQuality, isNull);
      expect(controller.ldacQualities, LdacQuality.values);
      controller.selectLdacQuality(LdacQuality.high);
      expect(controller.preference!.ldacQuality, LdacQuality.high);
      expect(controller.snapshot!.active!.cs1, 0);
      expect(adapter.writes, isEmpty);
    },
  );

  test(
    'explicit bitrate from default LDAC requires canonical quality readback',
    () async {
      adapter.onSnapshot = (_) async =>
          codecFixture(qualityCode: 0, stamp: 100000);
      await controller.refresh();
      controller.selectLdacQuality(LdacQuality.high);
      var readbacks = 0;
      adapter.onApply = (_, _) async {
        clock = clock.add(const Duration(milliseconds: 10));
        return true;
      };
      adapter.onSnapshot = (_) async {
        if (adapter.writes.isEmpty) {
          return codecFixture(qualityCode: 0, stamp: 100000);
        }
        readbacks++;
        return codecFixture(
          qualityCode: readbacks == 1 ? 0 : 1000,
          stamp: 100010,
        );
      };
      expect(await controller.applyPreference(), CodecApplyResult.confirmed);
      expect(readbacks, 2);
      expect(adapter.writes.single.cs1, 1000);
      expect(adapter.writes.single.cs2, -7);
      expect(controller.snapshot!.active!.ldacQuality, LdacQuality.high);
    },
  );

  test(
    'switching codec keeps a supported rate depth and channel preference',
    () async {
      adapter.onSnapshot = (_) async => codecFixture(
        stamp: clock.millisecondsSinceEpoch,
        capabilities: const [
          CodecConfiguration(
            codecType: 4,
            codecName: 'LDAC',
            sampleRateMask: 10,
            bitsMask: 2,
            channelMask: 2,
          ),
          CodecConfiguration(
            codecType: 8,
            codecName: 'Vendor codec',
            sampleRateMask: 10,
            bitsMask: 2,
            channelMask: 2,
          ),
        ],
      );
      await controller.refresh();
      controller.setPreference(requested);
      controller.selectCodec(8);
      expect(
        controller.preference,
        const CodecPreference(
          codecType: 8,
          sampleRateMask: 8,
          bitsMask: 2,
          channelMask: 2,
        ),
      );
      expect(adapter.writes, isEmpty);
    },
  );

  test(
    'quality write lease survives cancellation and rejects late old-device readback',
    () async {
      await controller.refresh();
      controller.selectLdacQuality(LdacQuality.high);
      final nativeWrite = Completer<bool>();
      adapter.onApply = (_, _) => nativeWrite.future;
      final apply = controller.applyPreference();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      expect(
        () => controller.selectLdacQuality(LdacQuality.balanced),
        throwsStateError,
      );
      final select = controller.selectDevice('BB');
      expect(await apply, CodecApplyResult.cancelled);
      expect(adapter.events, isNot(contains('snapshot:BB')));
      nativeWrite.complete(true);
      await select;
      expect(controller.snapshot!.selectedDeviceId, 'BB');
      expect(controller.phase, CodecOperationPhase.idle);
      expect(adapter.maxActiveCalls, 1);
      expect(adapter.writes.single.cs1, 1000);
    },
  );

  test(
    'preview mode refuses source-backed quality changes without native writes',
    () async {
      controller.dispose();
      adapter = FakeCodecAdapter()
        ..onSnapshot = (_) async => codecFixture(stamp: 100000);
      controller = CodecController(
        adapter: adapter,
        deviceId: 'AA',
        allowChanges: false,
        now: () => clock,
      );
      await controller.refresh();
      expect(
        () => controller.selectLdacQuality(LdacQuality.high),
        throwsStateError,
      );
      expect(await controller.applyPreference(), CodecApplyResult.disabled);
      expect(adapter.writes, isEmpty);
    },
  );

  test(
    'retained drafts remain editable after five seconds and submit rechecks current capabilities',
    () async {
      await controller.refresh();
      clock = clock.add(const Duration(seconds: 6));
      controller.setPreference(requested);
      var rate = 2;
      adapter.onSnapshot = (_) async =>
          codecFixture(rate: rate, stamp: clock.millisecondsSinceEpoch);
      adapter.onApply = (_, _) async {
        rate = 8;
        clock = clock.add(const Duration(milliseconds: 1));
        return true;
      };
      expect(await controller.applyPreference(), CodecApplyResult.confirmed);
      expect(adapter.writes, hasLength(1));
    },
  );

  test('normal consent can outlast the short native-call deadline', () async {
    final consent = Completer<void>();
    adapter.onConsent = () => consent.future;
    final request = controller.requestPermission();
    await Future<void>.delayed(const Duration(milliseconds: 95));
    expect(controller.phase, CodecOperationPhase.loading);
    consent.complete();
    await request;
    expect(controller.snapshot!.access, CodecAccess.ready);
  });

  test(
    'draft choices do not overwrite negotiated current configuration',
    () async {
      await controller.refresh();
      controller.setPreference(requested);
      expect(controller.preference, requested);
      expect(controller.snapshot!.active!.sampleRateMask, 2);
      expect(adapter.writes, isEmpty);
      expect(controller.sampleRates, [2, 8]);
    },
  );

  test('submitted true alone cannot confirm a request', () async {
    await controller.refresh();
    controller.setPreference(requested);
    adapter.onApply = (_, _) async {
      clock = clock.add(const Duration(milliseconds: 1));
      return true;
    };
    final result = await controller.applyPreference();
    expect(result, CodecApplyResult.timedOut);
    expect(controller.phase, CodecOperationPhase.timedOut);
    expect(controller.snapshot!.active!.sampleRateMask, 2);
    expect(controller.requiresRefresh, isTrue);
  });

  test(
    'old matching broadcast is ignored until fresh negotiated readback',
    () async {
      await controller.refresh();
      controller.setPreference(requested);
      var readbacks = 0;
      adapter.onApply = (_, _) async {
        clock = clock.add(const Duration(milliseconds: 10));
        return true;
      };
      adapter.onSnapshot = (id) async {
        if (adapter.writes.isEmpty) return codecFixture(stamp: 100000);
        readbacks++;
        return codecFixture(rate: 8, stamp: readbacks == 1 ? 100000 : 100010);
      };
      final phases = <CodecOperationPhase>[];
      controller.addListener(() => phases.add(controller.phase));
      expect(await controller.applyPreference(), CodecApplyResult.confirmed);
      expect(readbacks, 2);
      expect(phases, contains(CodecOperationPhase.verifying));
      expect(controller.snapshot!.active!.sampleRateMask, 8);
      expect(adapter.writes.single.cs1, 1003);
      expect(adapter.writes.single.cs2, -7);
    },
  );

  test('fresh capabilities are checked again before submission', () async {
    await controller.refresh();
    controller.setPreference(requested);
    adapter.onSnapshot = (_) async => codecFixture(
      stamp: clock.millisecondsSinceEpoch,
      capabilities: const [
        CodecConfiguration(
          codecType: 4,
          codecName: 'LDAC',
          sampleRateMask: 2,
          bitsMask: 2,
          channelMask: 2,
        ),
      ],
    );
    expect(await controller.applyPreference(), CodecApplyResult.refused);
    expect(adapter.writes, isEmpty);
  });

  test('native refusal cannot alter current state', () async {
    await controller.refresh();
    controller.setPreference(requested);
    adapter.onApply = (_, _) async => false;
    expect(await controller.applyPreference(), CodecApplyResult.refused);
    expect(controller.snapshot!.active!.sampleRateMask, 2);
  });

  test(
    'submission timeout keeps the native lease and requires refresh before another write',
    () async {
      await controller.refresh();
      controller.setPreference(requested);
      final pending = Completer<bool>();
      adapter.onApply = (_, _) => pending.future;
      expect(await controller.applyPreference(), CodecApplyResult.timedOut);
      expect(await controller.applyPreference(), CodecApplyResult.disabled);
      final refresh = controller.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      expect(adapter.activeCalls, 1);
      pending.complete(true);
      await refresh;
      expect(adapter.maxActiveCalls, 1);
      expect(controller.requiresRefresh, isFalse);
    },
  );

  test(
    'duplicate apply is rejected instead of overlapping native setters',
    () async {
      await controller.refresh();
      controller.setPreference(requested);
      final pending = Completer<bool>();
      adapter.onApply = (_, _) => pending.future;
      final first = controller.applyPreference();
      await Future<void>.delayed(Duration.zero);
      expect(await controller.applyPreference(), CodecApplyResult.disabled);
      pending.complete(false);
      expect(await first, CodecApplyResult.refused);
      expect(adapter.writes, hasLength(1));
      expect(adapter.maxActiveCalls, 1);
    },
  );

  test(
    'switching audio device rejects stale apply completion and serializes the next read',
    () async {
      await controller.refresh();
      controller.setPreference(requested);
      final pending = Completer<bool>();
      adapter.onApply = (_, _) => pending.future;
      final apply = controller.applyPreference();
      await Future<void>.delayed(Duration.zero);
      final switched = controller.selectDevice('BB');
      expect(await apply, CodecApplyResult.cancelled);
      expect(controller.snapshot, isNull);
      expect(adapter.events, isNot(contains('snapshot:BB')));
      pending.complete(true);
      await switched;
      expect(controller.snapshot!.selectedDeviceId, 'BB');
      expect(controller.phase, CodecOperationPhase.idle);
      expect(adapter.maxActiveCalls, 1);
    },
  );

  test('wrong-device readback never confirms another speaker', () async {
    await controller.refresh();
    controller.setPreference(requested);
    adapter.onApply = (_, _) async {
      clock = clock.add(const Duration(milliseconds: 1));
      return true;
    };
    adapter.onSnapshot = (_) async => codecFixture(
      id: adapter.writes.isEmpty ? 'AA' : 'BB',
      rate: 8,
      stamp: clock.millisecondsSinceEpoch,
    );
    expect(
      await controller.applyPreference(),
      isNot(CodecApplyResult.confirmed),
    );
    expect(controller.snapshot?.selectedDeviceId, isNot('BB'));
  });

  test(
    'read-only preview never invokes consent, association or apply',
    () async {
      controller.dispose();
      adapter = FakeCodecAdapter();
      controller = CodecController(adapter: adapter, allowChanges: false);
      await controller.refresh();
      await controller.requestPermission();
      await controller.associate();
      await controller.openBluetoothSettings();
      expect(await controller.applyPreference(), CodecApplyResult.disabled);
      expect(
        adapter.events.where((event) => !event.startsWith('snapshot:')),
        isEmpty,
      );
    },
  );

  test(
    'native error is visible and never treated as successful submission',
    () async {
      await controller.refresh();
      controller.setPreference(requested);
      adapter.onApply = (_, _) async => throw const CodecAdapterException(
        'codecUnavailable',
        'Android refused codec access.',
        details: 'SecurityException',
      );
      expect(await controller.applyPreference(), CodecApplyResult.refused);
      expect(controller.message, contains('Android refused'));
      expect(controller.errorDetails, contains('SecurityException'));
      expect(controller.snapshot!.active!.sampleRateMask, 2);
    },
  );

  test(
    'dispose rejects late readback and releases owned adapter once',
    () async {
      final pending = Completer<CodecSnapshot>();
      adapter.onSnapshot = (_) => pending.future;
      var notifications = 0;
      controller.addListener(() => notifications++);
      final refresh = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      final count = notifications;
      pending.complete(codecFixture(stamp: 100000));
      await refresh;
      expect(notifications, count);
      expect(adapter.disposed, 1);
      // Dispose is intentionally idempotent for screen/route cleanup.
      controller.dispose();
      expect(adapter.disposed, 1);
    },
  );
}
