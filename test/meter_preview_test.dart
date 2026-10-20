import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/meter_preview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/meter_onset_fixtures.dart';

void main() {
  final time = DateTime(2026);
  test(
    'missing stale and zero input produce silence with no synthetic beat',
    () {
      final p = MeterPreviewProcessor();
      expect(p.update(null, now: time).values, [0, 0, 0, -60, -60, -60, 0]);
      final zero = p.update(MeterLevels(0, 0, 0, time), now: time);
      expect(zero.audioActive, isFalse);
      expect(zero.beat, isFalse);
      expect(zero.values.take(3), [0, 0, 0]);
      expect(
        p
            .update(
              MeterLevels(100, 100, 100, time),
              now: time.add(const Duration(seconds: 1)),
            )
            .audioActive,
        isFalse,
      );
    },
  );
  test(
    'received levels drive source-mapped bands and bounded positive energy',
    () {
      final p = MeterPreviewProcessor();
      final sample = p.update(MeterLevels(50, 60, 70, time), now: time);
      expect(sample.audioActive, isTrue);
      expect(sample.values.length, 7);
      expect(sample.values.sublist(3, 6), [-30, -24, -18]);
      expect(sample.values.take(3).every((v) => v >= 0 && v <= 1), isTrue);
      expect(sample.values[0], greaterThan(0));
      expect(sample.values[1], sample.values[2]);
    },
  );
  test(
    'the same BLE notification never advances AGC or beat history twice',
    () {
      final p = MeterPreviewProcessor(), meter = MeterLevels(30, 50, 60, time);
      final a = p.update(meter, now: time),
          b = p.update(meter, now: time.add(const Duration(milliseconds: 20)));
      expect(b.values, a.values);
      expect(b.beat, a.beat);
    },
  );
  test(
    'beat estimates use changing received bass and respect refractory interval',
    () {
      final p = MeterPreviewProcessor();
      for (var i = 0; i < 70; i++) {
        p.update(
          MeterLevels(10, 10, 10, time.add(Duration(milliseconds: i * 30))),
          now: time.add(Duration(milliseconds: i * 30)),
        );
      }
      final peakTime = time.add(const Duration(milliseconds: 2200));
      final peak = p.update(MeterLevels(90, 100, 100, peakTime), now: peakTime);
      expect(peak.beat, isTrue);
      final next = peakTime.add(const Duration(milliseconds: 30));
      expect(
        p.update(MeterLevels(90, 100, 100, next), now: next).beat,
        isFalse,
      );
    },
  );

  test(
    'a sustained note produces one onset rather than refractory retriggers',
    () {
      final fixture = syntheticMeterFixtures(
        heldOut: false,
      ).firstWhere((fixture) => fixture.family == 'sustained');
      final p = MeterPreviewProcessor(), hits = <double>[];
      for (final packet in fixture.packets) {
        if (p.update(packet, now: packet.receivedAt).beat) {
          hits.add(fixture.timeOf(packet));
        }
      }
      final score = scoreOnsets(fixture, hits);
      expect(score.truePositive, 1);
      expect(score.falsePositive, 0, reason: 'held energy is not a new attack');
    },
  );

  test('a slow crescendo produces no abrupt onset', () {
    final fixture = syntheticMeterFixtures(
      heldOut: false,
    ).firstWhere((fixture) => fixture.family == 'crescendo');
    final p = MeterPreviewProcessor();
    for (final packet in fixture.packets) {
      expect(
        p.update(packet, now: packet.receivedAt).beat,
        isFalse,
        reason: 'a multi-second rise has no authored sharp attack',
      );
    }
  });

  test('30 Hz meter attacks remain observable alongside 60 and 100 Hz', () {
    for (final fixture in syntheticMeterFixtures(
      heldOut: false,
    ).where((fixture) => fixture.family.startsWith('band-'))) {
      final p = MeterPreviewProcessor(), hits = <double>[];
      for (final packet in fixture.packets) {
        if (p.update(packet, now: packet.receivedAt).beat) {
          hits.add(fixture.timeOf(packet));
        }
      }
      final score = scoreOnsets(fixture, hits);
      expect(score.truePositive, 3, reason: fixture.family);
      expect(score.falsePositive, 0, reason: fixture.family);
    }
  });

  test('out-of-order and future packets do not advance onset history', () {
    final p = MeterPreviewProcessor(), control = MeterPreviewProcessor();
    for (var i = 0; i < 25; i++) {
      final at = time.add(Duration(milliseconds: i * 33));
      final meter = MeterLevels(10, 10, 10, at);
      final expected = control.update(meter, now: at);
      final actual = p.update(meter, now: at);
      expect(actual.beat, expected.beat);
      final old = MeterLevels(
        100,
        100,
        100,
        at.subtract(const Duration(milliseconds: 1)),
      );
      expect(p.update(old, now: at), same(actual));
      final future = MeterLevels(
        100,
        100,
        100,
        at.add(const Duration(milliseconds: 1)),
      );
      expect(p.update(future, now: at).audioActive, isFalse);
    }
    final at = time.add(const Duration(milliseconds: 900));
    final attack = MeterLevels(90, 100, 100, at);
    expect(
      p.update(attack, now: at).beat,
      control.update(attack, now: at).beat,
    );
  });

  test('reset restores the behavior of a fresh processor', () {
    final reused = MeterPreviewProcessor(), fresh = MeterPreviewProcessor();
    final fixture = syntheticMeterFixtures(heldOut: false).first;
    for (final packet in fixture.packets) {
      reused.update(packet, now: packet.receivedAt);
    }
    reused.reset();
    for (final packet in fixture.packets) {
      final a = reused.update(packet, now: packet.receivedAt);
      final b = fresh.update(packet, now: packet.receivedAt);
      expect(a.values, b.values);
      expect(a.beat, b.beat);
      expect(a.audioActive, b.audioActive);
    }
  });

  test(
    'held energy after a long packet gap does not invent a second onset',
    () {
      final fixture = syntheticMeterFixtures(
        heldOut: false,
      ).firstWhere((fixture) => fixture.family == 'dropout');
      final p = MeterPreviewProcessor(), hits = <double>[];
      for (final packet in fixture.packets) {
        if (p.update(packet, now: packet.receivedAt).beat) {
          hits.add(fixture.timeOf(packet));
        }
      }
      final score = scoreOnsets(fixture, hits);
      expect(score.truePositive, 2);
      expect(score.falsePositive, 0);
      expect(fixture.hiddenOnsetsMs, [1450]);
    },
  );
}
