import 'dart:math' as math;
import '../../domain/speaker_state.dart';

class PreviewAudioSample {
  const PreviewAudioSample(
    this.values, {
    this.beat = false,
    this.audioActive = false,
  });
  static const silent = PreviewAudioSample([0, 0, 0, -60, -60, -60, 0]);
  final List<double> values;
  final bool beat, audioActive;
}

/// App-side reconstruction from the existing three positive BLE meter values.
/// Uses the source band mapping and AGC with app-side onset detection.
/// Meter smoothing/quantization omit original DSP peaks/boost/history, so this
/// is a reactive preview, not a bit-exact physical LED mirror.
class MeterPreviewProcessor {
  final _peaks = <double>[-60, -60, -60];
  final _onsets = _MeterOnsetDetector();
  DateTime? _lastReceived;
  PreviewAudioSample _last = PreviewAudioSample.silent;
  void reset() {
    _lastReceived = null;
    _onsets.reset();
    _peaks.setAll(0, [-60, -60, -60]);
    _last = PreviewAudioSample.silent;
  }

  PreviewAudioSample update(MeterLevels? meter, {required DateTime now}) {
    if (meter == null || !meter.isFresh(now)) return PreviewAudioSample.silent;
    if (meter.receivedAt == _lastReceived) return _last;
    if (_lastReceived != null && meter.receivedAt.isBefore(_lastReceived!)) {
      return _last;
    }
    _lastReceived = meter.receivedAt;
    final db = meter.db;
    final linear = List<double>.generate(
      3,
      (i) => meter.values[i] == 0 ? 0 : math.pow(10, db[i] / 20).toDouble(),
    );
    // Source renderer uses 30+60 for bass, 100 for mid, and the upper meter
    // peak for high. The last two estimates share the observed third packet.
    final bands = [
      (linear[0] + linear[1]).clamp(0.0, 1.0),
      linear[2],
      linear[2],
    ];
    for (var i = 0; i < 3; i++) {
      final inputDb = bands[i] < .000001
          ? -120.0
          : 20 * math.log(bands[i]) / math.ln10;
      _peaks[i] = inputDb > _peaks[i]
          ? _peaks[i] + (inputDb - _peaks[i]) * .4
          : (_peaks[i] * .999 - 100 * .001).clamp(-100.0, 0.0);
      bands[i] *= math
          .pow(10, (-3 - _peaks[i]).clamp(0.0, 5.0) / 20)
          .toDouble();
    }
    final maximum = bands.reduce(math.max);
    if (maximum > .001 && maximum < .25) {
      for (var i = 0; i < 3; i++) {
        bands[i] *= .25 / maximum;
      }
    }
    for (var i = 0; i < 3; i++) {
      bands[i] = bands[i].clamp(0.0, 1.0);
    }
    final active = meter.values.any((v) => v > 0);
    final beat = _onsets.update(linear, meter.receivedAt);
    return _last = PreviewAudioSample(
      List.unmodifiable([...bands, ...db, bands[0]]),
      beat: beat,
      audioActive: active,
    );
  }
}

/// Causal onset estimates from the three observed meter envelopes only.
/// Timestamp-normalized positive flux rejects held energy; the slower envelope
/// distinguishes an attack from small quantization changes. No clock generates
/// beats between notifications, including during missing telemetry.
class _MeterOnsetDetector {
  final _fast = <double>[0, 0, 0], _slow = <double>[0, 0, 0];
  final _history = <(DateTime, double)>[];
  DateTime? _lastAt, _lastBeat, _quietSince;
  bool _armed = true;

  void reset() {
    _fast.fillRange(0, 3, 0);
    _slow.fillRange(0, 3, 0);
    _history.clear();
    _lastAt = null;
    _lastBeat = null;
    _quietSince = null;
    _armed = true;
  }

  bool update(List<double> linear, DateTime at) {
    // Compression allows a quieter attack to remain visible after a loud one.
    final compressed = [
      for (final value in linear) math.log(1 + 20 * value) / math.log(21),
    ];
    final elapsed = _lastAt == null
        ? null
        : at.difference(_lastAt!).inMicroseconds / 1000;
    _lastAt = at;
    if (elapsed == null || elapsed >= 500) {
      // A first packet or long gap has no observed preceding attack slope.
      _fast.setAll(0, compressed);
      _slow.setAll(0, compressed);
      _history.clear();
      _lastBeat = null;
      _quietSince = null;
      _armed = true;
      return false;
    }
    final dt = elapsed.clamp(.001, 499.999).toDouble();
    final fastAlpha = 1 - math.exp(-dt / 22);
    final slowAlpha = 1 - math.exp(-dt / 180);
    var flux = 0.0, contrast = 0.0;
    for (var band = 0; band < 3; band++) {
      final previous = _fast[band];
      _fast[band] += fastAlpha * (compressed[band] - previous);
      _slow[band] += slowAlpha * (compressed[band] - _slow[band]);
      flux = math.max(flux, (_fast[band] - previous) * 1000 / dt);
      contrast = math.max(contrast, _fast[band] - _slow[band]);
    }
    _history.removeWhere(
      (sample) => at.difference(sample.$1).inMilliseconds > 1500,
    );
    final previousFlux = [for (final sample in _history) sample.$2]..sort();
    final median = _median(previousFlux);
    final deviations = [
      for (final value in previousFlux) (value - median).abs(),
    ]..sort();
    // Absolute slope/contrast floors also reject the .6 dB wire quantization
    // and gradual swells when the robust noise estimate is close to zero.
    final threshold = math.max(2.0, median + 4.45 * _median(deviations));
    _history.add((at, flux));
    if (_history.length > 128) _history.removeAt(0);

    if (flux < threshold * .4) {
      _quietSince ??= at;
      if (at.difference(_quietSince!).inMilliseconds >= 30) _armed = true;
    } else {
      _quietSince = null;
    }
    final beat =
        _armed &&
        flux > threshold &&
        contrast >= .025 &&
        linear.any((value) => value >= .008) &&
        (_lastBeat == null || at.difference(_lastBeat!).inMilliseconds > 90);
    if (beat) {
      _lastBeat = at;
      _armed = false;
      _quietSince = null;
    }
    return beat;
  }

  double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0;
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
