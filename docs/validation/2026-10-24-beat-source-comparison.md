# ESP32 and phone beat paths

Read-only firmware inspection and app-only handoff correction, 2026-10-24.

## Source and scope

The inspected local speaker tree is
`ESP32-A2DP-SINK-WITH-CODECS-UPDATED-main`. Its BTstack target's
`btstack_speaker/main/CMakeLists.txt` includes the shared
`bt_audio_sink/main/main.cpp`, DSP and LED code. This is a source comparison,
not verification of the image currently running on any board.

No firmware files were changed, built or flashed. No serial port, speaker upload,
OTA, phone settings or physical phone interaction was used for this comparison.
The app's copied effect/config/fast-math source hashes still match the inspected
speaker files. The differences below are in the inputs and beat delivery path.

## The ESP32 path

`bt_audio_sink/main/dsp/dsp_processor.h` analyzes the mono mix of decoded PCM
before EQ/output processing. It box-averages to an effective analysis rate near
11 kHz and feeds the Goertzel bank and peak envelopes. `dsp/goertzel.h` scales
the configured reference window of 512 samples at 44.1 kHz with the effective
sample rate: approximately 11.6 ms per magnitude update, not a runtime benchmark.

The beat task in `main.cpp` uses **60 Hz + 100 Hz linear Goertzel levels**.
In the inspected `bt_audio_sink/sdkconfig` and `btstack_speaker/sdkconfig`:

| Setting | Configured value |
|---|---:|
| Fast bass smoothing coefficient | 0.35 |
| Running-average coefficient | 0.01 |
| Minimum summed bass level | 0.012 |
| Fast/average ratio threshold | greater than 1.6 |
| Minimum beat interval | greater than 90 ms |
| Beat flag/LED flash duration | 60 ms |
| Beat-task timed wait | up to 10 ms, with task notifications also able to wake it |
| LED rendering target | 30 frames/s |

The task sets the internal beat flag directly. `led/led_controller.h` consumes
its rising edge and passes it to the effect. Beat intensity is a separate input:
the LED renderer derives bass intensity from **30 Hz + 60 Hz**, with volume
boost and AGC. The detector's bass sum and the renderer's bass intensity should
not be conflated.

## What reaches the phone

The meter branch in `main.cpp` is different from the beat branch:

1. For each 30/60/100 Hz band, take the higher of its Goertzel dB and peak-envelope
   dB values.
2. Smooth that display value with coefficient **0.45**.
3. Clamp it to -60..0 dB and round it into **0..100**. Each wire step represents
   approximately 0.6 dB.
4. Request a three-byte meter notification at the configured **30 ms** period.
   `ble/ble_unified.h` can skip best-effort meters when unsubscribed, unavailable
   or below its internal-heap threshold.

The current meter packet carries **no beat flag, event sequence, source sample
timestamp or PCM**. The three numbers are frequency bands, not three selectable
notification rates. Local phone arrival timestamps also include transport and
scheduling jitter.

`lib/features/light/meter_preview.dart` therefore reconstructs an onset from
the altered envelopes. It uses per-band positive flux after log compression,
22/180 ms fast/slow envelopes, a median/MAD threshold, contrast and amplitude
floors, a quiet rearm and a refractory interval. That is not the source's
60+100 Hz fast/average ratio detector. Its conservative gates can reject quieter
or smoothed attacks the ESP32's internal detector accepts.

This explains why a more powerful phone does not automatically recover the
speaker's trigger. Information was transformed before it arrived. It does not
by itself quantify musical accuracy or prove that either detector is better
on every track.

## Confirmed app handoff bug and correction

The real onset processor could return `beat=true`, followed by `beat=false` for
the next level packet. `BdkApp._updateSpeaker` replaced the whole preview sample
on each notification. If both arrived before Flutter built a frame, LightScreen
only received the last false value. Its existing queue could not retain an event
it had never received.

`test/ui/beat_handoff_app_test.dart` reproduces that exact boundary with the real
processor: the reference detects the onset, the later packet has no new onset,
and the original app loses it. The saved RED log fails on the lost-event
assertion, not on a missing API or fixture error.

The correction retains the latest onset timestamp separately from the latest
level sample and passes that identity to LightScreen. Its render clock consumes
that identity once, while level updates continue normally. Explicit identity
withdrawal also clears a queued event, including when effects change in the same
update: the forced settings frame now runs after input bookkeeping. Absent or
invalid meter data, source changes and disconnects invalidate the handoff; the
renderer rejects expired or future events. This is a latest-event latch, not an
arbitrarily deep beat queue: multiple onsets during a long UI stall can still
coalesce, and events at least 500 ms old are discarded. No detector thresholds,
random audio input, firmware protocol or effect algorithms were changed.

The renderer tests additionally cover exactly-once consumption across later
packets, explicit withdrawal with/without an effect change, and rejection of
old/future event timestamps with otherwise fresh audio. Initial test-fixture
attempts omitted a Material ancestor or had a syntax error; their failed logs
are retained and are not counted as behavioral regression evidence. Both
withdrawal cases failed on their actual queued-event assertions before their
corrections.

Receipts are local ignored files in `artifacts/beat-source-audit-20261024/`:
`handoff-red.log`, `handoff-green.log`, `identity-green.log`,
`withdrawal-red-2.log`, `effect-withdrawal-red.log`, `full-tests-reviewed.log`
and `analyze-reviewed.log`. The correction is source-level until a new Android package is
explicitly built, installed and checked; the earlier 0.7.2 phone receipt is not a
deployment receipt for this change.

Final verification: **705 Flutter tests passed, two skipped; analyzer clean**.
Independent review checked the firmware comparison, branch preservation and
event handoff, and the effect-change withdrawal regression was added before
the final passing run. These host checks do not establish real-music accuracy
or physical phone-to-speaker timing.

## Next validation and architectural choices

The previous [synthetic onset benchmark](2026-10-20-meter-onsets.md) remains a
generated-telemetry result. Its fixture generator does not reproduce the full
firmware's peak fallback and 0.45 dB smoothing path. Its aggregate F1 therefore
does not resolve the user's real-music observation.

For an app-only detector revision, capture real BLE meter traces and compare
bass-weighted/ratio and onset candidates using the actual firmware preprocessing,
with quiet tracks, sustained bass, transients, packet jitter/loss and latency
scored separately. Do not tune thresholds from the existing synthetic score
alone or claim exact synchronization from three level values.

If firmware work is separately authorized later, the most direct route to
matching the speaker's beat timing is a compatible, capability-negotiated beat
event with sequence/timing data from the existing ESP32 detector. Preserve legacy
meter compatibility rather than silently changing its packet meaning. This is a
future design option, not an implemented protocol.

## Inspected source hashes

These pin the local comparison, without asserting any board's deployed version.

| File under `bt_audio_sink/main/` | SHA256 |
|---|---|
| `main.cpp` | `757aa5d97f96fd36677fd72d686ad7ae0a6397b48904493f9a963f7f9fd03442` |
| `dsp/goertzel.h` | `747903e4066a597ab49003f253284a3c7a7fd8842f40d695bd702aed78887362` |
| `dsp/dsp_processor.h` | `05037cfb8d4e0556af1a2a9dd558ca4fc7c4647df9bd056543fb2e78b79657b0` |
| `config/app_config.h` | `07dc8677ea67d95a05ad591f2598535add5ee6784d626f1cd6efc1ed4e9c289a` |
| `ble/ble_unified.h` | `d6e4c22599d5cd8bee4e99526ad152184b591eb9a4921b1d24c13a9fdf02e858` |
| `led/led_controller.h` | `db43cc3a3ed519da1c16bb894bdb36fe1ed9d2ba9122d18d949d37afa91f9ba5` |
