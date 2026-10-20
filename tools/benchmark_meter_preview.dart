import 'dart:convert';
import 'dart:io';

import 'package:bdk_audio/features/light/meter_preview.dart';

import '../test/support/meter_onset_fixtures.dart';

/// Host-only processor cost; fixture creation and onset scoring are excluded.
/// Round averages are reported honestly, not as individual update tail latency.
void main() {
  final fixtures = syntheticMeterFixtures(heldOut: true)
      .where((fixture) => fixture.rateHz == 100)
      .take(10)
      .toList();
  final packetsPerRound = fixtures.fold<int>(
    0,
    (count, fixture) => count + fixture.packets.length,
  );
  const warmupRounds = 5, measuredRounds = 20;
  var beats = 0;
  int runRound() {
    final stopwatch = Stopwatch()..start();
    for (final fixture in fixtures) {
      final processor = MeterPreviewProcessor();
      for (final packet in fixture.packets) {
        if (processor.update(packet, now: packet.receivedAt).beat) beats++;
      }
    }
    stopwatch.stop();
    return stopwatch.elapsedMicroseconds;
  }

  for (var round = 0; round < warmupRounds; round++) {
    runRound();
  }
  final rounds = [for (var i = 0; i < measuredRounds; i++) runRound()];
  final totalMicroseconds = rounds.fold<int>(0, (sum, value) => sum + value);
  final averages = [for (final time in rounds) time / packetsPerRound]..sort();
  stdout.writeln('METER_PROCESSOR_COST ${jsonEncode({
    'environment': 'host-only synthetic 100 Hz telemetry; warmed Dart VM',
    'operating_system': Platform.operatingSystem,
    'dart_version': Platform.version,
    'warmup_rounds': warmupRounds,
    'measured_rounds': measuredRounds,
    'measured_updates': packetsPerRound * measuredRounds,
    'total_microseconds': totalMicroseconds,
    'mean_microseconds_per_update':
        totalMicroseconds / (packetsPerRound * measuredRounds),
    'p95_round_mean_microseconds_per_update':
        averages[((averages.length - 1) * .95).ceil()],
    'observed_beats_including_warmup': beats,
  })}');
}
