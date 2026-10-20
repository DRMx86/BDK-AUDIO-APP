import 'dart:math' as math;

import 'package:bdk_audio/domain/speaker_state.dart';

/// Authored amplitude envelopes sampled and quantized into the existing three
/// BLE meter values. These fixtures are synthetic telemetry, not recorded music.
/// Labels belong to envelope attacks, independently of either detector.
class SyntheticMeterFixture {
  const SyntheticMeterFixture({
    required this.name,
    required this.family,
    required this.rateHz,
    required this.packets,
    required this.onsetsMs,
    this.hiddenOnsetsMs = const [],
  });

  static final epoch = DateTime(2026);
  final String name, family;
  final int rateHz;
  final List<MeterLevels> packets;
  final List<double> onsetsMs;

  /// Attacks entirely inside missing telemetry, excluded from observable recall.
  final List<double> hiddenOnsetsMs;

  double timeOf(MeterLevels packet) =>
      packet.receivedAt.difference(epoch).inMicroseconds / 1000;
}

class _Random {
  _Random(this.value);
  int value;
  double next() {
    value = (1664525 * value + 1013904223) & 0xffffffff;
    return value / 0x100000000;
  }
}

double _ramp(double value) => value.clamp(0.0, 1.0).toDouble();

double _pulse(double time, double onset, double attack, double decay) {
  final age = time - onset;
  if (age < 0 || age > attack + decay * 7) return 0;
  return age < attack ? age / attack : math.exp(-(age - attack) / decay);
}

int _wire(double amplitude) => amplitude <= .001
    ? 0
    : ((20 * math.log(amplitude.clamp(.001, 1.0)) / math.ln10 + 60) / .6)
          .round()
          .clamp(1, 100)
          .toInt();

SyntheticMeterFixture _sample({
  required String name,
  required String family,
  required int rateHz,
  required int seed,
  required double durationMs,
  required List<double> onsetsMs,
  required List<double> Function(double) envelope,
  List<(double, double)> gaps = const [],
  List<double> hiddenOnsetsMs = const [],
  bool jitter = true,
}) {
  final random = _Random(seed), packets = <MeterLevels>[];
  final period = 1000 / rateHz;
  for (var index = 0; index * period <= durationMs; index++) {
    final offset = index == 0 || !jitter
        ? 0.0
        : (random.next() - .5) * period * .28;
    final time = index * period + offset;
    if (gaps.any((gap) => time >= gap.$1 && time < gap.$2)) continue;
    final amplitudes = envelope(time);
    final values = List.generate(3, (band) {
      // Bounded, deterministic meter noise, before the documented .6 dB step.
      final noise = (random.next() - .5) * .001;
      return _wire(amplitudes[band] + noise);
    });
    packets.add(
      MeterLevels(
        values[0],
        values[1],
        values[2],
        SyntheticMeterFixture.epoch.add(
          Duration(microseconds: (time * 1000).round()),
        ),
      ),
    );
  }
  return SyntheticMeterFixture(
    name: name,
    family: family,
    rateHz: rateHz,
    packets: packets,
    onsetsMs: List.unmodifiable(onsetsMs),
    hiddenOnsetsMs: List.unmodifiable(hiddenOnsetsMs),
  );
}

/// Development uses one declared seed and nominal cadence. Holdout uses
/// different attack times/dynamics, seeds, and 30/60/100 notifications/second.
/// The names 30/60/100 on MeterLevels remain frequency-band meanings.
List<SyntheticMeterFixture> syntheticMeterFixtures({required bool heldOut}) {
  final fixtures = <SyntheticMeterFixture>[];
  final rates = heldOut ? [30, 60, 100] : [30];
  final seeds = heldOut ? [271, 941, 1723] : [41];
  for (final rate in rates) {
    for (final seed in seeds) {
      final random = _Random(seed);
      final shift = heldOut ? random.next() * 91 : 0.0;
      void add(
        String family,
        double duration,
        List<double> onsets,
        List<double> Function(double) envelope, {
        List<(double, double)> gaps = const [],
        List<double> hidden = const [],
      }) {
        fixtures.add(
          _sample(
            name: '$family-${heldOut ? "holdout" : "development"}-$rate-$seed',
            family: family,
            rateHz: rate,
            seed: seed,
            durationMs: duration,
            onsetsMs: onsets,
            envelope: envelope,
            gaps: gaps,
            hiddenOnsetsMs: hidden,
          ),
        );
      }

      final sustainedAt = 600 + shift;
      add('sustained', 2600, [sustainedAt], (time) {
        final level =
            .72 *
            _ramp((time - sustainedAt) / 24) *
            (1 - _ramp((time - 2180) / 160));
        return [.003 + level * .32, .003 + level, .002 + level * .61];
      });
      add('crescendo', 4600, [], (time) {
        final position = _ramp((time - 500) / 3300);
        // Smooth endpoints and a multi-second rise, with no authored attacks.
        final level = .75 * position * position * (3 - 2 * position);
        return [.003 + level * .42, .003 + level, .002 + level * .7];
      });
      final dynamicsAt = [
        650,
        1140,
        1570,
        2170,
        2570,
        3200,
        3690,
      ].map((value) => value.toDouble() + shift).toList();
      final amplitudes = heldOut
          ? [.12, .68, .095, .58, .075, .47, .15]
          : [.15, .75, .11, .63, .09, .53, .19];
      add('dynamics', 4400, dynamicsAt, (time) {
        var level = 0.0;
        for (var i = 0; i < dynamicsAt.length; i++) {
          level += amplitudes[i] * _pulse(time, dynamicsAt[i], 22, 105);
        }
        return [.004 + level * .25, .004 + level, .003 + level * .63];
      });
      final irregularAt = [
        600,
        1010,
        1270,
        1810,
        2010,
        2660,
        2950,
        3570,
      ].map((value) => value.toDouble() + shift).toList();
      add('irregular', 4300, irregularAt, (time) {
        var level = 0.0;
        for (var i = 0; i < irregularAt.length; i++) {
          level +=
              (.19 + (i % 3) * .14) *
              _pulse(time, irregularAt[i], (18 + i % 3 * 7).toDouble(), 70);
        }
        return [.004 + level * .4, .004 + level, .003 + level * .7];
      });
      for (var band = 0; band < 3; band++) {
        final onsets = [600.0 + shift, 1380.0 + shift, 2260.0 + shift];
        add('band-${[30, 60, 100][band]}', 3000, onsets, (time) {
          var level = 0.0;
          for (final onset in onsets) {
            level += .32 * _pulse(time, onset, 24, 105);
          }
          return List.generate(3, (i) => .003 + (i == band ? level : 0));
        });
      }
      add('noise-bed', 3000, [], (time) {
        final wobble = math.sin(time * .011) * .0015;
        return [.027 + wobble, .036 - wobble, .025 + wobble * .7];
      });
      final dropoutAt = 600.0 + shift, nextAt = 2550.0 + shift;
      add(
        'dropout',
        3400,
        [dropoutAt, nextAt],
        (time) {
          final held =
              .44 *
              _ramp((time - dropoutAt) / 25) *
              (1 - _ramp((time - 2100) / 130));
          // This separate short attack is completely hidden by the long gap.
          final hidden = time >= 1450 && time < 1570 ? .22 : 0.0;
          final level = held + hidden + .35 * _pulse(time, nextAt, 25, 100);
          return [.003 + level * .3, .003 + level, .003 + level * .6];
        },
        gaps: [(1250, 1880)],
        hidden: [1450],
      );
      add('short-loss', 4300, irregularAt, (time) {
        var level = 0.0;
        for (final onset in irregularAt) {
          level += .29 * _pulse(time, onset, 25, 105);
        }
        return [.003 + level * .35, .003 + level, .003 + level * .7];
      }, gaps: [(1440, 1495), (3100, 3175)]);
    }
  }
  return fixtures;
}

/// Frozen pre-refinement detector, copied before product changes. It receives
/// the same valid, fresh, unique packets; source audio AGC is irrelevant here.
class PreviousMeterBeatDetector {
  DateTime? _lastReceived, _lastBeat;
  double _bassSmooth = 0, _bassAverage = 0;

  bool update(MeterLevels meter) {
    final elapsed = _lastReceived == null
        ? 30
        : meter.receivedAt.difference(_lastReceived!).inMilliseconds;
    _lastReceived = meter.receivedAt;
    final db = meter.db;
    final linear = List<double>.generate(
      3,
      (i) => meter.values[i] == 0 ? 0 : math.pow(10, db[i] / 20).toDouble(),
    );
    final active = meter.values.any((v) => v > 0);
    final beatBass = linear[1] + linear[2];
    final steps = (elapsed / 10).round().clamp(1, 5);
    for (var i = 0; i < steps; i++) {
      if (beatBass >= .012) {
        _bassSmooth += .35 * (beatBass - _bassSmooth);
        _bassAverage += .01 * (_bassSmooth - _bassAverage);
      } else {
        _bassSmooth *= .9;
        _bassAverage *= .999;
      }
    }
    final ratio = _bassAverage > 1e-6
        ? _bassSmooth / (_bassAverage + 1e-6)
        : 0.0;
    final beat =
        active &&
        beatBass >= .012 &&
        ratio > 1.6 &&
        (_lastBeat == null ||
            meter.receivedAt.difference(_lastBeat!).inMilliseconds > 90);
    if (beat) _lastBeat = meter.receivedAt;
    return beat;
  }
}

class OnsetScore {
  OnsetScore(
    this.truePositive,
    this.falsePositive,
    this.falseNegative,
    this.errorsMs,
    this.packetErrorsMs,
  );
  final int truePositive, falsePositive, falseNegative;
  final List<double> errorsMs, packetErrorsMs;

  double get precision => truePositive + falsePositive == 0
      ? 1
      : truePositive / (truePositive + falsePositive);
  double get recall => truePositive + falseNegative == 0
      ? 1
      : truePositive / (truePositive + falseNegative);
  double get f1 => precision + recall == 0
      ? 0
      : 2 * precision * recall / (precision + recall);

  Map<String, Object> get report => {
    'tp': truePositive,
    'fp': falsePositive,
    'fn': falseNegative,
    'precision': precision,
    'recall': recall,
    'f1': f1,
    'median_absolute_error_ms': percentile(errorsMs, .5),
    'p95_absolute_error_ms': percentile(errorsMs, .95),
    'p95_after_first_observable_packet_ms': percentile(packetErrorsMs, .95),
  };

  static double percentile(List<double> values, double quantile) {
    if (values.isEmpty) return 0;
    final sorted = values.map((value) => value.abs()).toList()..sort();
    return sorted[((sorted.length - 1) * quantile).ceil()];
  }

  static OnsetScore combine(Iterable<OnsetScore> scores) {
    var tp = 0, fp = 0, fn = 0;
    final errors = <double>[], packetErrors = <double>[];
    for (final score in scores) {
      tp += score.truePositive;
      fp += score.falsePositive;
      fn += score.falseNegative;
      errors.addAll(score.errorsMs);
      packetErrors.addAll(score.packetErrorsMs);
    }
    return OnsetScore(tp, fp, fn, errors, packetErrors);
  }
}

/// One-to-one matching to authored labels, with a fixed [-20, +100] ms window.
/// Every unmatched pulse, including a sustained-note retrigger, is a false hit.
OnsetScore scoreOnsets(SyntheticMeterFixture fixture, List<double> detections) {
  final used = <int>{}, errors = <double>[], packetErrors = <double>[];
  var matched = 0;
  for (final onset in fixture.onsetsMs) {
    int? best;
    for (var i = 0; i < detections.length; i++) {
      if (used.contains(i)) continue;
      final error = detections[i] - onset;
      if (error < -20 || error > 100) continue;
      if (best == null || error.abs() < (detections[best] - onset).abs()) {
        best = i;
      }
    }
    if (best == null) continue;
    used.add(best);
    matched++;
    errors.add(detections[best] - onset);
    final observable = fixture.packets
        .map(fixture.timeOf)
        .firstWhere((time) => time >= onset);
    packetErrors.add(detections[best] - observable);
  }
  return OnsetScore(
    matched,
    detections.length - matched,
    fixture.onsetsMs.length - matched,
    errors,
    packetErrors,
  );
}
