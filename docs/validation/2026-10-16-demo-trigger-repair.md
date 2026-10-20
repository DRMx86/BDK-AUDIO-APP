# Native demo trigger repair

Version 0.5.7+15 repairs app-preview input for Particle Burst and Meteor Shower.
The supplied ESP32 project and all three provenance-tracked copied source files
remain untouched. The effect classes, live-input path, geometry, diffusion and
30 Hz widget clock are unchanged.

## Reproduced cause

The actual 0.5.6 Redmagic sweep selected all 22 named effects. Twenty changed in
native artwork captures; Particle Burst retained a red center and Meteor Shower
stayed black. Longer observations confirmed each was static for roughly eleven
seconds. This was specific to these demo paths, not a global renderer freeze.

Each affected copied `updateDemo()` increments its frame counter, checks an
even-period trigger, then calls `update()`, which increments that same counter.
Starting at zero, only odd values are checked: neither the 20-frame bass hit nor
30-frame beat can occur. Root independently reproduced Particle Burst through
the actual packaged Windows native library: 240 Demo frames, the final 180 all
identical, at most nine lit center pixels. Explicit 30-frame beat input into the
same unchanged effect produced 180 distinct late frames and up to 255 lit pixels.

## App-owned correction and tests

Only the adapter in `packages/bdk_led_engine/src/bdk_led_engine.cpp` changes.
These two Demo effects receive their original bass/beat-intensity inputs from a
per-context 60-frame cycle, then call the unchanged audio-reactive update. This
produces beats at 30/60 and Meteor bass hits at 20/40/60. Actual effect changes
reset that cycle; repeated settings or same-effect selection do not. Other Demo
effects and live input keep their existing path.

Three real native regressions failed against the old packaged DLL: sustained
Particle animation, visible Meteor spawning and Particle cadence under repeated
settings. After the correction the complete **12 native C ABI checks pass**.
One focused independent review found no material issues. All copied-source
SHA256 values still match `SOURCE_PROVENANCE.json`; no original source access
was needed for that comparison.

The first test invocation contained a syntax error; its separate log is retained
and is not counted as the behavioral RED. The corrected RED log shows three
assertion failures before any implementation change.

Receipts are under `artifacts/particle-burst-056/`, including native baseline
reproduction, RED/GREEN tests and native/Android build output. Android optimized
preview builds pass for ARMv7/ARM64/x64. Windows AOT rebuild and actual new-version
phone verification are separate pending gates at this source checkpoint. No
new-version Linux, Apple, physical BLE or speaker behavior is claimed.

## Installed/package verification after the source checkpoint

Android 0.5.7 ARMv7/ARM64/x64 APKs pass manifest, signature, ZIP CRC, expected
ELF architecture and eight bundled-notice checks. The ARM64 APK was upgraded with
`pm install -r`; local, transferred and installed SHA256 match. Version code is
2015 and app data was preserved. Its 20,729,274 bytes have SHA256
`b35c2040abaece68da9abbcfb4843f48773b30199fc5c44787716a15efc5c2da`.

The Android upgrade resurfaced an old system picker in BDK's own task493. The
task's own BDK component intent was checked before launching that component with
CLEAR_TOP. The actual new MainActivity then cold-launched in 198 ms (one
observation, not a performance distribution). No system picker/Bluetooth setting
control was activated. Only the identity-checked temporary APK was removed after
verification; the installed app remains.

The [separate 0.5.7 phone check](2026-10-16-redmagic-demo-repair-checkpoint.md)
passes Particle Burst and Meteor Shower main preview animation, pause and resume.
Root independently verified all 78 evidence hashes/sizes and recomputed all nine
native screenshot series. Both main previews now change; paused series remain
identical. Phone restored Spectrum Bars70%, Follow device/Dark, explicit Demo
playing, Not connected. The static Meteor gallery thumbnail remains dark and
requires separate investigation; this repair does not close that visual gate.

The complete Windows AOT export is
`artifacts/windows-0.5.7-release/bdk-windows-preview-0.5.7-x64-release.zip`,
**13,943,405 bytes**, SHA256
`fa4d6e687360ed0fe19f023e445421b6de356a4711a147ddc1ed1e0b179b6068`.
All27 archive/extracted files and eight notices match the built bundle. The
actual packaged native DLL passes all12 C ABI checks. Windows Release UI was not
retried after the prior unrelated activation failure; no new GUI verdict follows
from packaging/native-library checks. These packages remain development previews.
