import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import '../tools/preview_frame_stats.dart';

FrameTiming frame(int start, int build, int raster, int id) => FrameTiming(
  vsyncStart: start - 200,
  buildStart: start,
  buildFinish: start + build,
  rasterStart: start + build + 100,
  rasterFinish: start + build + 100 + raster,
  rasterFinishWallTime: 0,
  frameNumber: id,
);

void main() {
  test(
    'timing watermark waits for a frame beyond the final measured boundary',
    () {
      final stats = PreviewFrameStats();
      stats.add(frame(1000, 1000, 1000, 1));
      expect(stats.hasTimingAtOrAfter(2000), false);
      stats.add(frame(3000, 1000, 1000, 2));
      expect(stats.hasTimingAtOrAfter(2000), true);
    },
  );
  test(
    'late batched timings belong to their timestamp window, not arrival time',
    () {
      final stats = PreviewFrameStats();
      stats.add(frame(900, 99000, 99000, 1)); // warmup, excluded
      stats.add(frame(1900, 4000, 8000, 3)); // next window arrives first
      stats.add(frame(1100, 1000, 2000, 2)); // delayed previous window
      stats.add(frame(1900, 4000, 8000, 3)); // duplicate callback, excluded
      final first = stats.summarize(start: 1000, end: 1800, refreshHz: 144);
      final next = stats.summarize(start: 1800, end: 2500, refreshHz: 144);
      expect(first['frames'], 1);
      expect((first['buildMs'] as Map)['p95'], 1.0);
      expect((first['rasterMs'] as Map)['p95'], 2.0);
      expect(next['frames'], 1);
      expect(next['uiOrRasterOverDisplayBudget'], 1);
      expect(next['uiOrRasterOverPreviewBudget'], 0);
    },
  );
  test(
    'nearest-rank percentiles retain worst frames and empty windows are inconclusive',
    () {
      final stats = PreviewFrameStats();
      for (var i = 0; i < 100; i++) {
        stats.add(frame(i * 100000, (i + 1) * 1000, 1000, i));
      }
      final all = stats.summarize(start: 0, end: 10000000, refreshHz: 60);
      expect(all['conclusive'], true);
      expect((all['buildMs'] as Map), {
        'p50': 50.0,
        'p95': 95.0,
        'p99': 99.0,
        'max': 100.0,
      });
      final empty = stats.summarize(
        start: 20000000,
        end: 21000000,
        refreshHz: 60,
      );
      expect(empty['conclusive'], false);
      expect(empty['buildMs'], isNull);
    },
  );
  test(
    'capacity overflow and invalid windows cannot masquerade as successful measurements',
    () {
      final stats = PreviewFrameStats(capacity: 2);
      for (var i = 0; i < 3; i++) {
        stats.add(frame(i * 100000, 1000, 1000, i));
      }
      final result = stats.summarize(start: 0, end: 1000000, refreshHz: 60);
      expect(result['truncated'], true);
      expect(result['conclusive'], false);
      expect(
        () => stats.summarize(start: 100, end: 100, refreshHz: 60),
        throwsArgumentError,
      );
      expect(
        () => stats.summarize(start: 0, end: 100, refreshHz: double.nan),
        throwsArgumentError,
      );
    },
  );
}
