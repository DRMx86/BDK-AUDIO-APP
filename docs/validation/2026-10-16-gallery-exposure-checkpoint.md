# Native gallery exposure checkpoint — 0.5.8+16

Meteor Shower's gallery tile now shows its sparse native glow clearly on the
Redmagic. The fixed gallery opacity had suppressed low-energy representatives;
the native frame was present, rather than missing or frozen.

The app now stores bounded exposure with each cached representative image:
`(.2 * 16384 / max(1, rgbEnergy)).clamp(.2, .6)`. Dense frames retain opacity .2;
sparse frames can reach .6. Source RGB, geometry, diffusion, main-preview opacity,
physical brightness settings and copied effect classes are unchanged. This is an
app gallery presentation adjustment. App code checkpoint: `e2fd28d`.

## Regression and source checks

Four recorded native 16×16 RGBA fixtures include Meteor, Particle Burst, Fire and
Beat Pulse. Their provenance records the actual packaged Windows 0.5.7 library,
settings, bounded 72-frame sampling sequence, selected frame and hashes. Meteor's
representative RGB energy is 3,278, compared with Beat Pulse's 82,432.

The new actual-widget raster test failed before the change in both themes:
Meteor's blank-band mean RGB chroma was **3.992/255**, below the independently set
minimum of 6. After the change, the test passes. It also checks title contrast
**≥4.5:1** over native fixtures and an opaque-white worst-case dense frame, using
the actual fonts and a raster with the label removed. This does not establish
contrast for every possible sparse frame or native device renderer.

Fresh verification:

- Relevant Light tests: **30 passed, 1 optional skipped**.
- Complete Flutter suite: **523 passed, 1 optional skipped**.
- Analyzer: **no issues**.
- Focused code review: no material findings; broader sparse-frame contrast remains
  a coverage limit rather than a universal guarantee.
- All three copied source files match the app's existing provenance manifest.
- All fifteen non-Dart native libraries across the three Android APKs are
  byte-identical to their verified 0.5.7 counterparts.
- The Windows LED DLL is byte-identical to the previously tested 0.5.7 binary;
  its existing 12 native C ABI passes apply to that exact binary. No fresh native
  test execution is claimed for this unchanged DLL.

Logs and raster exports remain in ignored `artifacts/gallery-*` paths. Fixture
data is committed under `test/fixtures/led/` and is never shipped as runtime art.

## Actual Redmagic check

Only serial **9125299103B7**, package `com.bdkaudio.controller`, normal
`lib/main.dart`, ARM64 optimized AOT **0.5.8 / code 2016**, PreviewOnly build was
used. The upgrade preserved app data. Local, staged and installed APK hashes
matched. Own foreground and unlocked-screen checks guarded inputs; selection
used fresh native semantics. Native PNGs were streamed directly; uniquely owned
temporary XML and the exact staged APK were removed.

Before/after native gallery captures have identical Meteor bounds
`[631,1212]–[1151,1777]`. The same blank band below its icon and above its label,
`(696,1563)–(1086,1634)`, excludes foreground controls and contains 27,690 pixels:

| Measured gallery band | 0.5.7 | 0.5.8 |
|---|---:|---:|
| Mean max(R,G,B) − min(R,G,B) | 4.588 | 13.802 |
| Pixels with RGB chroma >8 | 20.24% | 50.08% |

The neighboring dense Kaleidoscope band `(130,920)–(520,1000)` is byte-identical
between those captures. Inspected first gallery rows retain readable Spectrum,
Beat Pulse, Ripple and Fire labels over diffused native frames.

Selecting Meteor returns to its main preview. Paused samples show **0 changed
pixels**; playing samples show **35,098 / 194,839 changed pixels** relative to the
first, within artwork ROI `(200,850)–(1000,1500)` of 520,000 pixels. The native
effect naturally has dark intervals; these counts establish change, not uniform
brightness, frame rate or physical speaker synchronization.

After restoring Spectrum Bars, actual Home navigation, five seconds in the
background and a normal HOT Activity return retain the preview. Two resumed
artwork captures differ in **138,195 pixels**. This proves visible foreground
continuation, rather than measuring background CPU use. The install launch was
COLD; the single observed Activity times are not performance benchmarks.

The phone was left on **Spectrum Bars, 70%, playing, explicit firmware Demo,
Not connected**, PID 28698. There are **42 hashed native PNG/XML entries** in
`artifacts/gallery-058/capture-manifest.json`; events, installed/final identities,
comparison receipts and raw images remain alongside it. This run did not repeat
the earlier 22-effect sweep or establish live BLE/music/codec behavior.

## Local preview packages and remaining scope

Android ARMv7, ARM64 and x64 APKs compile and pass manifest/API24→36, expected ELF
architecture, CRC, development-certificate and eight bundled-notice checks.
ARMv7/x64 are package-verified only. Installed ARM64 artifact:

`artifacts/bdk-audio-preview-0.5.8-release.apk`, **20,729,274 bytes**, SHA256
`1dfacfdc4f94e3b76786b7408b88425e83b0aecf613683d50864e5514eb4b4e8`.

Windows AOT x64 Release compiles. Complete 27-file bundle, seven PE x64 files,
ELF64 x64 Dart payload, native version 0.5.8+16, CRC, extraction hashes and eight
notices pass. Its executable is **NotSigned**. Archive:

`artifacts/windows-0.5.8-release/bdk-windows-preview-0.5.8-x64-release.zip`,
**13,943,472 bytes**, SHA256
`21682aa5a9d7dcd72073719daf0b17dfb34474f405bf48d25243c724ca2e304b`.

No Windows Release GUI retry was made while the earlier activation failure's
conditions remained unchanged. Linux retains its separately documented 0.5.6
bundle and partial Jammy runtime verdict. Apple builds/devices, broad release
validation and production signing/distribution remain open. The user reports no
audio connection or playback yet, so actual read-only BLE/meter/codec checks
remain pending. No Bluetooth setting, BLE connection, sound/OTA transfer,
ESP32 source, serial, firmware or hardware operation occurred.
