# LED diffusion, idle Spectrum and automatic preview playback

App source checkpoints: `622129c` (0.6.5), `543eff5` / `3738b42` (0.6.6),
and `3cd4367e4d29372df0cee1571402793d3bc77d03` (0.6.7+25).
This receipt covers the user's LED-preview requests. The broader release goal
remains paused. No original ESP32 repository, serial port, firmware build, board
or speaker setting was accessed. Phone QA remains at0.6.0; all new installations
and inputs targeted only owned `emulator-5580`, AVD
`BDK_Animations_API36_20261016`.

## Changes and rejected approaches

The0.6.5 noise overlay still rounded the Gaussian blur and title gradient before
adding grain. The user correctly reported remaining steps. An independent
double-precision reference catches the stepped local mean: worst error was
0.499986 RGB levels. Direct float reconstruction, including the title/matte
shade and physical-pixel dither before final display quantization, reduces that
error to0.050472. Dither also covers dark margins of an emitting frame; all-black
source and zero opacity add no synthetic light.

The direct0.6.6 shader reconstructs all256 source cells. It preserved quality but
was expensive in emulator captures. An18-tap experiment was rejected before
deployment because edge and isolated-cell tests exposed sampling/lobe defects.
The final0.6.7 path prepares separable Gaussian fields in the app-owned native
wrapper, retains Float32 through explicit Float32 texture decoding, and linearly
samples two fields in the final shader. Core256² nodes cover[-4,20], sigma0.8;
halo128² nodes cover[0,16], with sigma derived from the actual preview's cover
size. Uniform frames such as Beat Pulse use the analytic Gaussian rectangle path.
The exact source-cell shader and native Canvas blur remain fallbacks.

Main previews and gallery cards share this optical path. Texture work coalesces
new frames without continually discarding completed work; images/shaders have
explicit owners and late completions are disposed. Review found a synchronous
unsupported-library error could call setState during LayoutBuilder. A failing
regression reproduced it; construction now starts after layout and checks
generation, size and disposal before work/publication. Scoped re-review found no
remaining material issue.

Effect selection resumes a paused preview unless the user has enabled reduced
motion. Explicit Play still opts in under reduced motion. Brightness edits retain
the existing source clock and direct thumb tracking.

Spectrum's Demo inputs now use smooth independent per-context random targets.
Per the user's choice, connected idle is allowed only for fresh confirmed zero
BLE levels and no active audio. Missing/stale/positive data stays waiting/live;
freshness expiry ends idle. No source effect header changed. The fixed360-frame
live Spectrum sequence retained SHA256
`6434ba9a587ac155f97f416d4e7164bb490807c08c790b963c8cda2be13e6ef5`.
All three app-owned copied source hashes match `SOURCE_PROVENANCE.json`.

## Verification

- Full Flutter suite:600PASS,1optionalSKIP in27s; analyzer clean8.8s.
- Native CABI:25PASS, including independent double Gaussian/premultiplied alpha,
  grid endpoints, symmetry, invalid-output sentinels and effect-clock isolation.
  Existing18 tests passed and seven new tests failed on the missing export before
  implementation. A fresh separate DLL avoided the active Windows app's locked DLL.
- Cached/direct final image comparison stays within1RGB level per pixel and
  mean absolute error below0.08. Fractional Float32 values survive decoding;
  edge continuity, single halo, dark mean, blackout, disposal, async coalescing,
  autoplay and brightness/input-cadence regressions pass.
- A synchronous raw-image decoder experiment failed on Skia and was discarded;
  its failed log is retained. The supported asynchronous Float32 path remains.
- All three Android ABI packages passed manifest/API24→36, ELF, CRC, development
  certificate, compiled shader and eight bundled-notice checks. These optimized
  development previews are not signed distribution releases.

Logs and native media are under `artifacts/led-quality-065`,
`artifacts/led-quality-066` and `artifacts/led-quality-067`. Earlier failed/stale
DLL checks and insufficient approaches remain preserved. The accidental focused
test filename error is excluded; the later full suite includes the real cadence
tests and passed.

## Installed native emulator evidence

0.6.7+25, x64 versionCode4025, normal `lib/main.dart`,
`BDK_PREVIEW_ONLY=true`, timing diagnostics off. APK22,273,030bytes,
SHA256`43b0dbeea8f7aa1a9f81a7a54703fff7e3b18cfae0f86c57b5fb19d209003c6c`;
local, staged and installed hashes match. Initial verified PID18860; app data
and isolated emulator permissions were preserved.

Native PNGs and recordings show Spectrum, Beat Pulse and Fire selected from a
paused preview. Each selection immediately restores the Pause control and the
effect continues moving without a brightness gesture. Brightness stays70%.
`beat-autoplay-later.png` contains the dark pulse that exposed the original
banding; broad contours are absent. `beat-autoplay-gallery.png` shows full-card
diffused Spectrum, Beat Pulse, Ripple, Fire, Plasma and Matrix Rain artwork.
Native contact sheets were inspected for flash/decay, bottom-up fire and changing
Spectrum bands. Full PNGs are the gradient evidence; compressed video and reduced
contact sheets can introduce their own quantization artifacts.

Recordings contain284frames/11.488578s (Beat),352/11.465989s (Fire), and
187/11.186389s (warm Spectrum). The earlier Spectrum capture varied to
123/10.976578s. These are recording rates, not source-effect or GPU FPS.
Read-only SurfaceFlinger observations of the actual app SurfaceView show127
presented buffers over3.037234s (Beat,41.49/s) and4.086894s (Spectrum,30.83/s).
Spectrum's median presentation interval was29.61ms, p9571.59ms. This finite
emulator evidence demonstrates continuing presentation, not guaranteed smooth
30FPS across hardware or a count of distinct native effect advances. The existing
source-clock regression tests remain the cadence check; physical phone timing
and live BLE-driven rendering are outside this receipt.

Native helper profiling on Windows measured Spectrum median3.885ms, Fire2.755ms
and black0.485ms. It does not measure Android decode/upload/GPU cost. Android
compile commands confirm-O2/-fno-fast-math. A3,600-frame source probe found zero
identical consecutive Spectrum frames, so deduplication was not applied. Subnormal
counts did not establish the cause of variable capture rates; no global FP mode
changed. A smaller grid was rejected for desktop error bounds. Current quality
and geometry were retained.

Final state: owned emulator remains in local Demo with Spectrum playing. No
physical peer, music or meter input was injected. Actual BLE/hardware parity,
Apple/desktop runtime coverage, release signing and distribution remain separate
release work.
