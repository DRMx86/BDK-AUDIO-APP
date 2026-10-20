# Phone-side meter onset validation — 2026-10-20

The app estimates attacks from the existing three positive BLE meter values
(30, 60 and 100 Hz bands). It receives neither PCM nor a full spectrum. No
microphone permission, audio capture, firmware change, or tempo-generated pulse
was added. The source-derived preview audio mapping and AGC remain unchanged.

`MeterPreviewProcessor` now uses timestamp-aware 22/180 ms fast/slow envelopes
of compressed amplitude, positive flux, a prior-sample median/MAD threshold,
absolute noise/attack floors, a 30 ms quiet rearm, and the existing >90 ms
refractory interval. History is capped at 128 samples and 1.5 seconds. The first
packet and a gap of at least 500 ms prime envelopes without inventing an onset.
Missing, stale/future, duplicate and out-of-order packet behavior and reset are
covered by processor tests; its public API and seven audio values are preserved.

## Independent synthetic comparison

`test/support/meter_onset_fixtures.dart` authors continuous amplitude envelopes
before sampling or detection, then adds deterministic jitter/noise and the
existing .6 dB wire quantization. Families cover sustained notes, slow
crescendos, alternating weak/strong attacks, irregular rhythm, individual meter
bands, noise, short packet loss and a long dropout. This is generated telemetry,
not recorded music. Labels do not come from either detector.

Development uses seed 41 at 30 notifications/second. The frozen holdout uses
seeds 271/941/1723, changed attack times/dynamics, and 30/60/100 notifications per
second. These notification rates are distinct from the three frequency bands.
The detector passed development before the holdout run; no holdout tuning was
performed. The previous detector is frozen in the test support file.

One-to-one matching uses a fixed [-20, +100] ms window around authored onsets.
Unmatched pulses, including sustained retriggers, count as false positives.
Attacks completely hidden inside the long dropout are explicitly labeled and
excluded from observable recall (nine hidden holdout attacks). Timing reports
absolute onset error and delay from the first observed packet after each onset.

| Split / algorithm | TP | FP | FN | Precision | Recall | F1 | p95 onset error |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Development / previous | 28 | 79 | 7 | 0.2617 | 0.8000 | 0.3944 | 40.97 ms |
| Development / replacement | 35 | 0 | 0 | 1.0000 | 1.0000 | 1.0000 | 33.49 ms |
| Holdout / previous | 251 | 710 | 64 | 0.2612 | 0.7968 | 0.3934 | 37.56 ms |
| Holdout / replacement | 304 | 0 | 11 | 1.0000 | 0.9651 | 0.9822 | 33.78 ms |

Holdout replacement median absolute onset error is 10.84 ms; p95 delay after
the first observable packet is 19.08 ms. Sustained, crescendo, noise and dropout
families have zero false positives. All eleven misses are in the weak/strong
dynamics family (52/63 attacks detected; recall 0.8254). That family remains a
known sensitivity limit despite the aggregate improvement.

## Receipts and reproduction

Root-agent SDK runs, independently read back from their saved logs:

- `artifacts/android-ship-20261020/features-red.log`: original detector fails
  sustained/crescendo/30 Hz/dropout regressions; candidate and baseline metrics
  are identical before implementation.
- `artifacts/android-ship-20261020/beat-development.log`: development comparison
  passed (one test).
- `artifacts/android-ship-20261020/beat-green.log`: all 12 targeted processor and
  synthetic benchmark tests passed, including the frozen holdout.

From the Flutter app directory:

```powershell
flutter test test/meter_preview_test.dart test/meter_onset_benchmark_test.dart --reporter expanded
```

`SYNTHETIC_METER_ONSETS` lines contain the exact counts, unrounded metrics and
per-family results. A separate optional host-only cost probe is available:

```powershell
dart run tools/benchmark_meter_preview.dart
```

The cost probe reports warmed host processing time for preconstructed 100 Hz
synthetic packets, excluding fixture creation and scoring. It is not phone
render timing or a per-packet tail-latency measurement; no cost result is claimed
until that tool is run and its receipt inspected.

These tests establish the stated generated-telemetry behavior only. They do not
prove beat accuracy for real music, acoustic synchronization, physical LED
behavior, Android deployment, or recovery of attacks absent from the transmitted
meter envelopes. First-packet/gap priming intentionally sacrifices an unobserved
attack rather than manufacturing one from unknown history.
