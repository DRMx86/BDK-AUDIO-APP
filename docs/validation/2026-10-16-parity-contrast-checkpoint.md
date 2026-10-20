# Original-app parity and light readability checkpoint

Development preview 0.5.3. The production goal remains active.

## Changes and evidence

The [original-app audit](original-feature-parity-audit.md) follows the actual
ConnectionActivity → MainActivityRedesign route. All nine active presets retain
their exact wire gains; Flutter also keeps three legacy choices.

The original dropdown's Off 255 sentinel conflicts with the previously recorded
[project protocol](../migration/protocol-contract.md). Flutter tolerates that
state on input and renders it black, but never sends 255 in SET_LED. Gallery Off
uses zero brightness with a valid remembered effect. Original/ESP32 sources were
not changed; no physical255 state or compatibility is claimed.

Light restoration now survives tab changes and same-speaker reconnects during
the app session. A different ready speaker resets the memory. Transient
connecting/default settings cannot replace the last real settings. Regression
checks cover incoming Ambient 37 → Off 0 while Light is unmounted, both Off paths,
same-ID reconnect and different-ID reset, without a setter in simulated links.

The existing top gradient now keeps the upper-left effect name readable over
bright light, including wrapped enlarged text. No title pill was added. Real
bundled-font tests verify an opaque-white decoded LED image and independently
sample aligned glyph interiors, including the existing shadow:

| Scenario | Before minimum contrast | After minimum contrast |
|---|---:|---:|
| Ambient, 400px, DPR 1 | 2.244:1 | 7.114:1 |
| Frequency Spiral, 320px, DPR 2 | 2.270:1 | 7.226:1 |
| Wrapped Frequency Spiral, 320px, DPR 2, 2× text | 1.371:1 | 6.193:1 |

All three checks require at least 4.5:1. These are bounded rendered-widget
measurements, not a whole-app accessibility certification. The first fallback
font/histogram check falsely passed; actual fonts and glyph alignment exposed
the failure before the gradient correction.

Speaker → App info restores installed version/build and the original creator's
WillyBilly credit. Metadata errors and missing fields show unavailable states.
`package_info_plus 10.2.2` is pinned. Project-local plugin junctions resolved the
Windows symlink prerequisite without changing global Developer Mode.

Final analyzer clean; full Flutter suite **438 passed**, one optional screenshot
test skipped. Failures were observed before the fixes. Independent review's
tab-local restore limitation was raised to Important and repaired; its contrast
threshold finding was corrected. A focused follow-up found no new material
memory/App info issues. Root reconciled the outgoing Off contract before any
new installation; the initial compiled artifact was not deployed.

## Native builds and packages

Android ARM64 Debug and Windows x64 Debug builds pass using `lib/main.dart` and
`BDK_PREVIEW_ONLY=true`.

Redmagic NX809J, serial 9125299103B7: installed 0.5.3 / versionCode 2011. Local,
transferred and installed base.apk hashes match. Transfer completed in 130s.
The first launch encountered a stale in-task file picker; reopening the exact
own activity with CLEAR_TOP produced a confirmed cold launch of 1005ms.

- APK: `artifacts/bdk-audio-design-preview-0.5.3.apk`, 90,333,186 bytes.
- SHA256: `b8bf70ba620e35b21ee2c363bc65a2e9345cf5f8ea949f4268f4cde03eaf74b2`.

Native Android App info displays Version 0.5.3 / Build 2011. The actual screenshot
was inspected. Ambient quick select opens its controls. A native sequence of
Ambient 38% → Off → Sound → Light → On restores Ambient 38%; SeekBar and switch
states confirm it. The native diffused Spectrum preview was visually inspected.

Native Windows App info displays Version 0.5.3 / Build 11. The same restoration
sequence retains Ambient 37%, confirmed through UI Automation. The tested app
was closed after checks.

- Complete bundle: `artifacts/bdk-windows-design-preview-0.5.3.zip`, 45,928,136 bytes.
- SHA256: `8ba8587e8a60bcf156d89c20b4471fb41f1aeab891bb5eed2ab8ff5c12917fda`.
- All 20 archived bundle files match their built sizes and SHA256 hashes.

These are local development packages. No BLE connection, speaker write, codec
setter, sound transfer, OTA operation, serial access, ESP32 build or flash was
performed. Original app installation/data and older ADB/VM processes are
preserved. Only exact self-created remote QA files were removed.

## Remaining work

Saved/single-speaker automatic control connection remains an original-app
convenience gap; manual connection exists. Live music/BLE/codec evidence is
pending user audio readiness. Native spoken accessibility, full-app/long-running
audio tests, physical Windows identity, Apple/Linux native execution, icons,
signing/distribution and trusted updates remain open in the
[platform matrix](../platform-release-matrix.md). This checkpoint does not
complete Task 10 or the full goal.
