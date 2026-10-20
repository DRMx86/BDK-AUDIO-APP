# Light-theme LED preview checkpoint

Development preview 0.5.6. The full production migration goal remains active.

Native Linux testing found a shared UI defect: additive LED light was composited
over the app's pale Material surfaces. In Light theme, RGB channels clipped and
the preview became gray/white. The unchanged 0.5.5 native app produced zero changed
pixels in a 140,800-pixel preview region over 3.191 s. Switching only its app theme
to Dark restored colors and 43,475 changed pixels over 3.249 s. The native library
was mapped in that same process; direct LED/WAV ABI checks also passed.

The repair gives the main preview and effect tiles a neutral dark optical base
in either app theme. Gallery names, selection marks, symbols and preview-error
text retain readable foregrounds. Surrounding navigation/settings still follow
the chosen theme. Effect algorithms, geometry, blur, timing and BLE behavior are
unchanged.

Two actual-widget raster regressions failed before the repair: the pure-red
main preview's mean R-B was 5.708 rather than >25, and the effect tile was -4.113
rather than >5. Red/blue color separation now passes in both locations. Existing
diffusion/title checks remain green; minimum title contrast is 7.114/7.226/6.193:1.
Analyzer is clean; full suite **521 passed**, one optional capture skipped.
One fresh independent focused review found no material issues.

## Native evidence

- Redmagic installed 0.5.6 / code 2014 AOT, `lib/main.dart`, `BDK_PREVIEW_ONLY=true`.
  Local, transferred and installed base.apk SHA256 all match. In app-selected
  Light theme, two captures changed 129,760/520,000 interior artwork pixels
  (24.95%); 518,963 pixels were visibly chromatic. Native gallery artwork, names
  and selection were inspected. Phone restored to Follow device and left on
  Spectrum Bars 70% in explicit Demo, preview playing.
- Windows Debug build succeeded. The Light-theme native panel displayed colored
  Spectrum; the app was also resized. A separate driver window intermittently
  occluded captures, so it was never used as an app or codec verification result.
  No driver input/settings action was performed. The tested BDK window was closed
  and its absence confirmed while the driver and other apps remained open.
- Linux 0.5.6 compiled from a fresh 308-file manifest-verified snapshot. Native
  decoder probe/512-frame PCM decode is bit-exact; native Rainbow Wave yields 32
  unique RGBA frames. All five ELF dependencies resolve in the Ubuntu 24 guest.
  The actual app's Light preview has four distinct ROI hashes across a bounded
  extended sample, changing 16,866/16,986/38,878 of 140,800 pixels relative to first.
  A shorter identical pair is preserved, so no frame-rate guarantee is claimed.
  Native gallery colors/labels/selection are inspected separately in the runner
  receipt. Emulated guest software rendering is not bare-metal/GPU/BLE evidence.

| Artifact | Bytes | SHA256 |
|---|---:|---|
| `artifacts/bdk-audio-preview-0.5.6-release.apk` | 20,712,890 | `6d625fa98be1a3e7f68d51a0e8b670eab215bef617dc2617507b14ecee9c2a07` |
| `artifacts/bdk-windows-design-preview-0.5.6.zip` | 46,102,963 | `6da24ec151031342a56ad2fcf3bc8a9cab952b9966d12cb1f17b5495c452a150` |
| `artifacts/linux-runner/bdk-audio-0.5.6-linux-x64-debug-preview.tar.gz` | 39,192,054 | `73a8f337fbc3f6bca87af97046b06c97fb8e51e20e05ab3d73cb1048fe5854a2` |

All 29 Windows archive files match the complete built bundle. Android continues to
use a development signature despite AOT optimization. Exact self-created remote
APKs/captures were removed; local receipts and failed observations are preserved.
The Linux TAR's42 manifest entries independently match sizes, hashes, types and
modes; executable/launcher permissions remain0755 and its eight notice assets
match source bytes. App-level Linux Sound file selection/isolate decoding remains
untested; direct ABI decoding is a distinct verified gate.

## Remaining limits

The current Linux bundle imports GLIBC 2.38 and GLIBCXX 3.4.29, so Ubuntu 24 native
success is not older-distro compatibility. An older build root and architecture
coverage remain necessary. General Linux audio confirmation stays explicit:
the source-backed [identity boundary](../migration/linux-audio-identity-boundary.md)
shows that a newly configured BlueZ/PipeWire transport can precede completed
A2DP connection; it must not be labeled automatically verified.

Live music/meter/codec checks await user audio readiness. Apple native build and
hardware validation, publisher/source-rights inputs, signing/distribution and
other release gates remain open. No ESP32 source access/build/serial/flash,
speaker control/sound/OTA write, Bluetooth setting change or cloud job occurred.
