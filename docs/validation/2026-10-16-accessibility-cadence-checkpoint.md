# Accessibility and preview cadence checkpoint

Development preview 0.5.2; the full production goal remains active.

## Changes and verification

Four demonstrated accessibility gaps are fixed: RGB slider names, gallery
selected state, custom tone-slider role/focus state, and assistive input-focus
forwarding. The approved visual design is preserved.
[Scoped audit and native follow-up](accessibility-checkpoint.md).

Native profiling exposed a functional preview defect: faster input advanced
stateful effects more frequently than the 30 FPS preview clock. New input now
keeps the latest levels, with one queued short beat consumed at a frame tick.
Meter clearing discards that pending beat. Data updates no longer invalidate
every in-flight decode. Actual Redmagic and Windows after-runs hold about 30
effect updates/s at all three synthetic input cadences.
[Raw reports, measurements and limits](native-preview-performance.md).

Fresh full Flutter suite: **420 passed**, one optional screenshot capture skipped.
Analyzer clean. New checks include 11 accessibility cases, four timing/statistics
cases, three run-lifecycle/workload cases and two input-cadence cases. Meaningful
failures were observed before fixes. Async image tests synchronize the real
decode queue separately from the fake widget clock.

The diagnostic build policy has 22 standalone Java cases. An actual Flutter
diagnostic build without its QA define was rejected before packaging. Both the
isolated profile APK and the normal APK were checked for their exact package IDs.
The temporary QA app was removed after retaining its numeric reports; the
original installed app and normal Flutter app data were preserved.

Independent review found three Important diagnostic-tooling risks: accidental
normal-app replacement, stale successful reports and partially stopped workloads.
They were fixed with regressions. The timing-drain finding was raised to Important
and fixed with a finite watermark check. The cadence bug was found in native
measurements and verified with focused tests plus native after-runs. No second
review or full release approval is implied.

## Native packages and UI

Android ARM64 and Windows x64 Debug builds pass. Redmagic 0.5.2 / versionCode 2010
was installed and cold launched. Local, transferred and installed base.apk
SHA256 matched:

`6ff52778b6d97d2fcc318f106cfc4589f803a8dba2326c6daf37517254b3b94c`

Artifact: `artifacts/bdk-audio-design-preview-0.5.2.apk`,90,305,642 bytes,
`BDK_PREVIEW_ONLY=true`.

Native Android nodes confirm labeled/focusable EQ and RGB SeekBars. Gallery
selected state moved from Spectrum Bars to Ripple. Ambient quick selection
reached its brightness and color controls. The native phone preview was visually
inspected and left on explicit animated Spectrum Demo.

Windows UI Automation reports the three tone controls as sliders. Pointer focus
plus native Up/Down changed Bass 0→+1→0 while other bands stayed neutral. The
complete development bundle archive's required executable/plugin/engine/Dart
asset hashes match the current build.

Windows artifact: `artifacts/bdk-windows-design-preview-0.5.2.zip`,45,879,769 bytes,
SHA256:

`276f9b9630e06c06e8332f3c89b1d02bb6ebafa77e4057d316ed1813f22f5538`

These are development packages, not signed production releases. Native captures
remain local/ignored. Only exact self-created temporary files/apps were removed.
No original Android/ESP32 sources, serial ports, firmware builds, flashing,
speaker controls, codec setters, sound transfers or physical updates were used.

## Remaining gates

Live connected music/BLE response and actual codec negotiation are pending the
user's audio readiness. Spoken TalkBack/VoiceOver/Narrator behavior, contrast,
low-end/long-running/full-app audio performance, physical Windows identity,
Apple/Linux native runtime, icons, publisher/signing/distribution and trusted
updates remain open. [Platform matrix](../platform-release-matrix.md) and
[preview user guide](../user-guide.md).
