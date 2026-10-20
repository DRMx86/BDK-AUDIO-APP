# Android 0.7.2 internal delivery

The normal ARM64 application is installed on the authorized Redmagic
9125299103B7 (nubia NX809J, Android API 36). The original Android app remains
installed. This is an internal Android checkpoint, not a universal/store release.

## Installed artifact

- Package com.bdkaudio.controller; version 0.7.2; ABI version code 2030.
- Normal lib/main.dart; BDK_PREVIEW_ONLY=false. Demo still guards physical writes.
- APK: artifacts/android-ship-20261020/bdk-audio-0.7.2-2030-arm64.apk.
- Size 20,916,586 bytes; SHA256
  db45616e0322319c56cbbfc43664b41300866d18013aee53c2a6092e80285d12.
- Installed base.apk SHA256 matches that artifact; min API 24, target API 36.
- Existing Android Debug development certificate retained for data-preserving
  upgrade; certificate SHA256
  4803b9a2bef3e61dc4e981ddffe346169bc4272b8c1af3b23c64b7661c39ca93.
- ZIP CRC, ARM64 ELF headers and signature verified. Native LED/decoder libraries
  are byte-identical to the earlier 0.7.0 internal artifact; unrelated Linux WIP
  was not staged or changed by this completion.
- Final installation used standard adb --no-streaming push/install successfully.
  Earlier streamed installs were slow; no OS or security policy was changed.

Package, signature, install and readback receipts are package-receipt-072.json,
signature-072.log, install-072.log and installed-072-sha256.txt in that directory.

## Delivered behavior

Audio quality separates observed config from a draft, shows source/freshness,
supports known LDAC targets and positively identified LHDC V5 requests, and
requires fresh same-device capability checks plus exact requested readback.
Unknown vendor fields are preserved. Rate changes align incompatible LHDC
draft targets visibly; lossless mode restricts requests to Adaptive. Local editing
does not expire mid-choice, while Apply retains the fresh-write boundary.

The shared compact strip displays codec/rate/depth and a recognized configured
bitrate or Adaptive across Sound, Light and Speaker. Menu/header bitrate values
use the user's short labels. Detail text explains nominal targets and the absence
of an actual transmitted-bitrate getter.

Verified exact speaker candidates skip the five-second successful-discovery
dwell. Android foreground scanning explicitly requests low latency with report
delay zero; lifecycle gates still stop scanning. Saving a speaker preference no
longer delays usable controls. Connected controls reveal over 280 ms without an
extra readiness wait; reduced-motion changes preserve child state.

Brightness-only writes use 0x07 at queue dispatch, avoiding full effect resets.
The revised timestamp-aware meter onset detector rejects sustained-note
retriggers, gradual swells and quantization noise. Sound COMPLETE is separated
from confirmed slot presence; uncertain receipts remain explicit and expire
across connection epochs. Pairing retains actionable transport errors.

## Fresh verification

- 699 Flutter tests passed; two intentional skips. Full log full-tests-072.log.
- Whole-app analyzer clean: analyze-072.log.
- 25 native renderer tests passed: native-renderer.log.
- 13 freshly compiled JVM codec parsing/policy/cache checks passed:
  lhdc-native-shipping.log.
- ARM64 AOT/release-mode build passed: android-build-072.log.
- Independent reviews led to regression-backed fixes for queued read deadlines,
  default LDAC identity checks, LHDC rate-only validation, duplicate codec routes,
  reduced-motion subtree lifetime and pending sound-receipt epochs.

The [meter benchmark](2026-10-20-meter-onsets.md) records synthetic held-out
F1 0.9822 versus 0.3934 and eleven weak-dynamics misses. Host processing averaged
8.90 microseconds/update on its finite warmed test; that is not phone render
timing or real-music/acoustic accuracy. The [connection receipt](2026-10-20-connection-latency.md)
distinguishes removed controller waits from unmeasured physical discovery time.

## Physical codec evidence

The [Android API research receipt](2026-10-20-android-codec-api.md) records a
normal-target-app LHDC V5 API experiment: configured target 1000 to 900 kbps,
then exact captured raw-configuration restoration. Rate 192 kHz, depth 24-bit,
stereo, priority and opaque fields remained unchanged. Actual encoded/RF bitrate
was not measured. Exploratory LHDC 500-kbps UI automation was inconclusive due
to helper layout/semantic assumptions and is not counted as a successful test.
Its failed captures are retained.

For the user's separate LDAC request, the phone was already using LDAC
96 kHz / 32-bit stereo / Adaptive when the final test began. All four modes were
then selected and applied through the installed 0.7.2 app UI:

| Mode | Fresh current-config result | App confirmation |
|---|---|---|
| 330 kbps | LDAC, 96 kHz, 32-bit, stereo; nominal 330 | Current connection confirmed |
| 660 kbps | Same format; nominal 660 | Current connection confirmed |
| 990 kbps | Same format; nominal 990 | Current connection confirmed |
| Adaptive | Same format; Adaptive; no invented fixed nominal rate | Current connection confirmed |

Receipts: ldac-readback-330.ui.json, ldac-readback-660.ui.json,
ldac-readback-990.ui.json and ldac-readback-adaptive2.ui.json. Draft values and
owned semantic click results are recorded separately. The initial Adaptive mode
and visible format were restored. The complete opaque pre-test LDAC tuple was
not captured, so no separate exact-raw-tuple restoration claim is made for LDAC.

The independent UI helper checks package/focus, fresh node identity and action
uniqueness and refuses ambiguous/stale targets. A refusal during freshness
layout change was retried from a new snapshot; guards were not bypassed. The
optional separate LDAC API backup helper was compiled, not executed after the
successful UI tests. No duplicate physical experiment is counted.

The current string LDAC · 96 kHz · 32-bit · Adaptive was physically observed on
all three main tabs (final-sound-verified.ui.json, final-light-verified.ui.json,
final-speaker-verified.ui.json). The app was left on Sound.

After verification, the temporary com.bdkaudio.codecprobe test helper was
uninstalled successfully. The main com.bdkaudio.controller application remains
installed.

## Scope and remaining release gates

No ESP32 firmware source edits/builds, serial operations, flashing or physical
sound/OTA transfer was performed. Sound/OTA clients remain fake-transport tested
for this checkpoint. Speaker ACK/COMPLETE/status and durable persistence are
separate boundaries. Codec target readback does not establish RF throughput,
decoder delivery, acoustic quality or synchronization.

The earlier native phone diffusion/splash/discovery checkpoints remain valid
historical evidence; no new GPU/performance or controlled connection-latency
benchmark is claimed here. Broader Android/OEM/permission coverage, physical
transfer QA and public signing remain. Apple native builds/signing and the
Windows/Linux release matrix remain separate work; the universal goal is not
marked complete. See the [platform matrix](../platform-release-matrix.md).
