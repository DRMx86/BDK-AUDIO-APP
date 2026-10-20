import 'package:bdk_audio/features/codec/codec_controller.dart';
import 'package:bdk_audio/features/codec/codec_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'codec_test_support.dart';

// Runtime guards make the first RED an assertion on missing feature behavior,
// while the new LhdcV5Quality type is introduced in the production step.
dynamic qualityFor(dynamic owner, int? target) {
  expect(() => owner.lhdcV5Qualities, returnsNormally);
  final choices = owner.lhdcV5Qualities as List;
  return choices.singleWhere((dynamic q) => q.nominalTargetKbps == target);
}

void main() {
  test(
    'known LHDC rate-only tuple cannot preserve a source-invalid fixed target',
    () {
      final snapshot = lhdcV5Fixture();
      const lowRate = CodecPreference(
        codecType: 15,
        sampleRateMask: 2,
        bitsMask: 2,
        channelMask: 2,
      );
      expect(snapshot.supports(lowRate), isFalse);
      expect(() => snapshot.configurationFor(lowRate), throwsArgumentError);
    },
  );

  test(
    'inconsistent lossless fixed-quality fields have no current nominal target',
    () {
      final snapshot = lhdcV5Fixture(cs1: 0x8008, cs3: 0x5c000080);
      expect(snapshot.active!.nominalTargetKbps, isNull);
      expect(snapshot.active!.lhdcV5NominalTargetKbps, isNull);
    },
  );
  test(
    'probed LHDC V5 fields identify the current nominal 1000 kbps target',
    () {
      final current = lhdcV5Fixture().active!;
      expect(() => (current as dynamic).lhdcV5Quality, returnsNormally);
      expect((current as dynamic).lhdcV5Quality.nominalTargetKbps, 1000);
      expect((current as dynamic).nominalTargetKbps, 1000);
      expect(current.ldacQuality, isNull);
      expect(current.ldacNominalTargetKbps, isNull);
    },
  );

  test(
    'LHDC quality needs both V5 fingerprints rather than name or codec index alone',
    () {
      for (final snapshot in [
        lhdcV5Fixture(name: 'LHDC'),
        lhdcV5Fixture(cs3: 0x4c000000),
        lhdcV5Fixture(cs3: 0),
        lhdcV5Fixture(cs1: 0xc008),
        lhdcV5Fixture(cs1: 0x800a),
        lhdcV5Fixture(cs1: 0),
        lhdcV5Fixture(rate: 4),
      ]) {
        expect(
          () => (snapshot.active as dynamic).lhdcV5Quality,
          returnsNormally,
        );
        expect((snapshot.active as dynamic).lhdcV5Quality, isNull);
        expect((snapshot as dynamic).lhdcV5Qualities, isEmpty);
      }
      expect(
        (lhdcV5Fixture(capabilities: const []) as dynamic).lhdcV5Qualities,
        isEmpty,
      );
    },
  );

  test(
    'LHDC quality changes preserve upper cs1 bits and every other opaque field',
    () {
      final snapshot = lhdcV5Fixture(
        cs1: 0x100008008,
        cs2: -7,
        cs3: 0x5c000006,
        cs4: -9,
      );
      final quality = qualityFor(snapshot, 500);
      final preference =
          (const CodecPreference(
                        codecType: 15,
                        sampleRateMask: 32,
                        bitsMask: 2,
                        channelMask: 2,
                      )
                      as dynamic)
                  .withLhdcV5Quality(quality)
              as CodecPreference;
      expect(snapshot.supports(preference), isTrue);
      final desired = snapshot.configurationFor(preference);
      expect(
        [desired.cs1, desired.cs2, desired.cs3, desired.cs4],
        [0x100008006, -7, 0x5c000006, -9],
      );
      expect(preference.matches(snapshot.active!), isFalse);
    },
  );

  for (final (rate, targets) in [
    (1, [64, 160, 192, 256, 320, 400, 500, 900, null]),
    (2, [64, 160, 192, 256, 320, 400, 500, 900, null]),
    (8, [256, 320, 400, 500, 900, 1000, null]),
    (32, [256, 320, 400, 500, 900, 1000, null]),
  ]) {
    test('LHDC source target requests respect rate mask $rate', () {
      final snapshot = lhdcV5Fixture(rate: rate);
      expect(() => (snapshot as dynamic).lhdcV5Qualities, returnsNormally);
      expect(
        ((snapshot as dynamic).lhdcV5Qualities as List)
            .map((dynamic q) => q.nominalTargetKbps)
            .toList(),
        targets,
      );
    });
  }

  test(
    'LHDC lossless exposes only adaptive requests without changing its features',
    () {
      final snapshot = lhdcV5Fixture(cs1: 0x8009, cs3: 0x5c000080);
      final adaptive = qualityFor(snapshot, null);
      expect((snapshot as dynamic).lhdcV5Qualities, hasLength(1));
      final preference =
          (const CodecPreference(
                        codecType: 15,
                        sampleRateMask: 32,
                        bitsMask: 2,
                        channelMask: 2,
                      )
                      as dynamic)
                  .withLhdcV5Quality(adaptive)
              as CodecPreference;
      final desired = snapshot.configurationFor(preference);
      expect(desired.cs1, 0x8009);
      expect(desired.cs3, 0x5c000080);
      expect((snapshot.active as dynamic).nominalTargetKbps, isNull);
    },
  );

  group('LHDC controller', () {
    late FakeCodecAdapter adapter;
    late CodecController controller;
    late DateTime clock;
    setUp(() {
      clock = DateTime.fromMillisecondsSinceEpoch(100000);
      adapter = FakeCodecAdapter()
        ..onSnapshot = (_) async =>
            lhdcV5Fixture(stamp: clock.millisecondsSinceEpoch);
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
      '192 to 48 kHz adjusts the visible local target to 900 and verifies that exact target',
      () async {
        await controller.refresh();
        controller.selectSampleRate(2);
        expect(controller.preference!.lhdcV5Quality, LhdcV5Quality.kbps900);
        expect(adapter.writes, isEmpty);
        expect(controller.snapshot!.active!.sampleRateMask, 32);
        var readbacks = 0;
        adapter.onApply = (_, _) async {
          clock = clock.add(const Duration(milliseconds: 10));
          return true;
        };
        adapter.onSnapshot = (_) async {
          if (adapter.writes.isEmpty) return lhdcV5Fixture(stamp: 100000);
          readbacks++;
          return lhdcV5Fixture(
            rate: 2,
            cs1: readbacks == 1 ? 0x8008 : 0x8007,
            stamp: 100010,
          );
        };
        expect(await controller.applyPreference(), CodecApplyResult.confirmed);
        expect(readbacks, 2);
        expect(adapter.writes.single.sampleRateMask, 2);
        expect(adapter.writes.single.cs1, 0x8007);
      },
    );

    test(
      'lossless format adjustment selects adaptive locally without feature writes',
      () async {
        adapter.onSnapshot = (_) async =>
            lhdcV5Fixture(cs1: 0x8008, cs3: 0x5c000080);
        await controller.refresh();
        controller.selectSampleRate(2);
        expect(controller.preference!.lhdcV5Quality, LhdcV5Quality.adaptive);
        expect(controller.snapshot!.active!.cs3, 0x5c000080);
        expect(adapter.writes, isEmpty);
      },
    );

    test(
      'stale local bitrate drafts are editable and apply still refuses vanished capabilities before write',
      () async {
        await controller.refresh();
        final target = qualityFor(controller, 500);
        clock = clock.add(const Duration(seconds: 6));
        expect(
          () => (controller as dynamic).selectLhdcV5Quality(target),
          returnsNormally,
        );
        expect((controller.preference as dynamic).lhdcV5Quality, target);
        expect(controller.hasFreshObservation, isFalse);
        expect(adapter.writes, isEmpty);
        adapter.onSnapshot = (_) async => lhdcV5Fixture(
          stamp: clock.millisecondsSinceEpoch,
          capabilities: const [],
        );
        expect(await controller.applyPreference(), CodecApplyResult.refused);
        expect(adapter.writes, isEmpty);
      },
    );

    test(
      'LHDC target confirms only after exact fresh same-device quality readback',
      () async {
        await controller.refresh();
        (controller as dynamic).selectLhdcV5Quality(
          qualityFor(controller, 500),
        );
        var reads = 0;
        adapter.onApply = (_, _) async {
          clock = clock.add(const Duration(milliseconds: 10));
          return true;
        };
        adapter.onSnapshot = (_) async {
          if (adapter.writes.isEmpty) return lhdcV5Fixture(stamp: 100000);
          reads++;
          return lhdcV5Fixture(
            cs1: reads == 1 ? 0x8008 : 0x8006,
            stamp: 100010,
          );
        };
        expect(await controller.applyPreference(), CodecApplyResult.confirmed);
        expect(reads, 2);
        expect(adapter.writes.single.cs1, 0x8006);
        expect(adapter.writes.single.cs3, 0x5c000000);
        expect((controller.snapshot!.active as dynamic).nominalTargetKbps, 500);
      },
    );

    test(
      'peer-clamped LHDC target never becomes a successful requested bitrate',
      () async {
        await controller.refresh();
        (controller as dynamic).selectLhdcV5Quality(
          qualityFor(controller, 500),
        );
        adapter.onApply = (_, _) async {
          clock = clock.add(const Duration(milliseconds: 10));
          return true;
        };
        adapter.onSnapshot = (_) async => adapter.writes.isEmpty
            ? lhdcV5Fixture(stamp: 100000)
            : lhdcV5Fixture(cs1: 0x8005, stamp: 100010);
        expect(await controller.applyPreference(), CodecApplyResult.timedOut);
        expect(controller.phase, CodecOperationPhase.timedOut);
        expect(adapter.writes, hasLength(1));
      },
    );
  });
}
