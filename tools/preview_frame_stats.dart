import 'dart:ui';

/// Benchmark-only storage. Engine timestamps classify delayed/batched callbacks;
/// arrival time is deliberately not used to assign a frame to a scenario.
class PreviewFrameStats {
  PreviewFrameStats({this.capacity = 20000}) : assert(capacity > 0);
  final int capacity;
  final _frames = <int, FrameTiming>{};
  bool truncated = false;
  bool hasTimingAtOrAfter(int boundary) => _frames.values.any(
    (frame) => frame.timestampInMicroseconds(FramePhase.buildStart) >= boundary,
  );

  void add(FrameTiming frame) {
    final timestamp = frame.timestampInMicroseconds(FramePhase.buildStart);
    final key = frame.frameNumber >= 0 ? frame.frameNumber : timestamp;
    if (_frames.containsKey(key)) return;
    if (_frames.length == capacity) {
      truncated = true;
      return;
    }
    _frames[key] = frame;
  }

  Map<String, Object?> summarize({
    required int start,
    required int end,
    required double refreshHz,
  }) {
    if (end <= start || !refreshHz.isFinite || refreshHz <= 0) {
      throw ArgumentError(
        'A finite refresh rate and ordered window are required.',
      );
    }
    final frames = _frames.values.where((frame) {
      final timestamp = frame.timestampInMicroseconds(FramePhase.buildStart);
      return timestamp >= start && timestamp < end;
    }).toList();
    final displayBudget = 1000000 / refreshHz;
    const previewBudget = 1000000 / 30;
    bool over(FrameTiming frame, double budget) =>
        frame.buildDuration.inMicroseconds > budget ||
        frame.rasterDuration.inMicroseconds > budget;
    Map<String, double>? percentiles(Iterable<Duration> values) {
      final sorted = values.map((value) => value.inMicroseconds).toList()
        ..sort();
      if (sorted.isEmpty) return null;
      double at(double rank) =>
          sorted[(sorted.length * rank).ceil() - 1] / 1000;
      return {'p50': at(.5), 'p95': at(.95), 'p99': at(.99), 'max': at(1)};
    }

    return {
      'frames': frames.length,
      'conclusive': frames.length >= 30 && !truncated,
      'truncated': truncated,
      'windowSeconds': (end - start) / 1000000,
      'refreshHz': refreshHz,
      'buildMs': percentiles(frames.map((frame) => frame.buildDuration)),
      'rasterMs': percentiles(frames.map((frame) => frame.rasterDuration)),
      'totalSpanMs': percentiles(frames.map((frame) => frame.totalSpan)),
      'uiOrRasterOverDisplayBudget': frames
          .where((f) => over(f, displayBudget))
          .length,
      'uiOrRasterOverPreviewBudget': frames
          .where((f) => over(f, previewBudget))
          .length,
    };
  }
}
