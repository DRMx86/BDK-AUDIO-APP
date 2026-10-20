import 'dart:convert';

import 'package:bdk_audio/features/light/meter_preview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/meter_onset_fixtures.dart';

void main() {
  for (final heldOut in [false, true]) {
    test('synthetic ${heldOut ? "holdout" : "development"} onset comparison', () {
      final currentScores = <OnsetScore>[], oldScores = <OnsetScore>[];
      final families = <String, List<OnsetScore>>{};
      for (final fixture in syntheticMeterFixtures(heldOut: heldOut)) {
        final current = MeterPreviewProcessor(),
            old = PreviousMeterBeatDetector();
        final currentHits = <double>[], oldHits = <double>[];
        for (final packet in fixture.packets) {
          if (current.update(packet, now: packet.receivedAt).beat) {
            currentHits.add(fixture.timeOf(packet));
          }
          if (old.update(packet)) oldHits.add(fixture.timeOf(packet));
        }
        final score = scoreOnsets(fixture, currentHits);
        currentScores.add(score);
        oldScores.add(scoreOnsets(fixture, oldHits));
        (families[fixture.family] ??= []).add(score);
      }
      final current = OnsetScore.combine(currentScores);
      final old = OnsetScore.combine(oldScores);
      // This machine-readable receipt is explicitly synthetic telemetry.
      // The held-out set has independent seeds/dynamics and is not tuning data.
      // ignore: avoid_print
      print(
        'SYNTHETIC_METER_ONSETS ${jsonEncode({'split': heldOut ? 'holdout' : 'development', 'baseline': old.report, 'candidate': current.report, 'families': families.map((name, scores) => MapEntry(name, OnsetScore.combine(scores).report))})}',
      );
      expect(current.f1, greaterThan(old.f1 + .1));
      expect(current.precision, greaterThanOrEqualTo(.95));
      expect(current.recall, greaterThanOrEqualTo(old.recall - .02));
      expect(current.recall, greaterThanOrEqualTo(.95));
      for (final family in ['sustained', 'crescendo', 'noise-bed', 'dropout']) {
        expect(
          OnsetScore.combine(families[family]!).falsePositive,
          0,
          reason: '$family must not fabricate repeated or missing-data beats',
        );
      }
      expect(
        OnsetScore.percentile(current.packetErrorsMs, .95),
        lessThanOrEqualTo(40),
      );
    });
  }
}
