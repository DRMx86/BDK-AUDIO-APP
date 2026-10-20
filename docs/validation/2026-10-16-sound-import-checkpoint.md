# Sound import development checkpoint

App and phone work only. The supplied ESP32 project remains untouched. This
checkpoint is not a production release or a physical speaker-transfer result.

## Implemented behavior

Speaker sounds has four focused editors: Startup, Pairing, Connected and Volume
limit. Device presence comes from existing sound flags; local drafts are separate.
Imported files stay unchanged. The app streams a private copy up to64MiB, decodes
off the UI thread, and prepares mono PCM16 at22050/16000/11025/8000Hz within200KiB.
Long files require explicit clip selection; exact start/length inputs supplement
the overview slider. No silent truncation or padded successful output.

Up to four prepared drafts persist locally, including their source/selection
metadata. Atomic file replacement preserves the previous store after a failed
save, and unknown store versions are preserved. Originals must be selected again
to edit a restored draft. Local playback follows real player events and stops
on background/route exit.

App-side upload/delete/mute use the existing exclusive BLE writer. Upload waits
for both ATT completion and READY for each packet, then actual COMPLETE after END.
Mute/delete require command ACK and matching flags. Uncertain, failed or cancelled
operations disconnect before retry. Existing untagged responses cannot prove
arbitrary delayed-duplicate identity. Interrupted replacement may lose the old
speaker sound because the existing source removes it first; the UI discloses that.

The preview build disables all remote sound mutations, including status-query
side effects from the transfer controller. Local import and playback stay usable.

## Evidence so far

- Flutter suite289 passed, one optional screenshot test skipped; analyzer clean.
- Fresh independent review found two Important issues, both reproduced failing
  then passing: old import completion deleting the newer source, and a long-file
  range slider unable to select a short arbitrary excerpt. Ownership/ticket checks
  and exact-time inputs repair these cases. No Critical or deferred Minor findings.
- Windows offline decoder:16 real C ABI tests,1 PCM-window test and5 Dart FFI/
  isolate tests passed. Both pinned upstream source hashes match provenance.
- Android arm64 and Windows x64 app builds passed. Actual Windows GUI inspected
  setup, Sound, Speaker, sound list/editor; M4A imported through the native file
  dialog into a2s/22050Hz/88244-byte canonical draft. Windows Bluetooth not tested.
- Actual Redmagic imported a non44-byte-header WAV into the same canonical size;
  its draft survived force-stop/cold launch. Local playback transitioned to Stop
  preview and returned to Preview locally on completion, without an app error.
  Audibility/output waveform was not measured.
- Actual Redmagic imported a600s FLAC and prepared the explicitly chosen
  125.25–128.25s excerpt:3s/22050Hz/132344bytes. No automatic truncation or upload.
- Actual Redmagic M4A initially failed exact segment decoding. The offline Android
  harness reproduced codec priming, extractor EOF and inaccurate seek behavior.
  Preserving decoder history repairs these failures; 174 offline Android cases
  pass, with excerpts within two PCM units of origin conversion. The installed
  0.3.2 app also imported the exact failing M4A through the real file picker into
  a two-second / 22050 Hz / 88244-byte draft. No speaker mutation was performed.

Current installed package: 0.3.2(2006), ARM64 preview, 89,268,826 bytes. Local,
transferred and installed APK SHA256 matched:
`e5a9e9232f9e95403aaf11bedd24ef8c7c08df3b58b0d338429a4340fbe7490b`.
Phone screenshots stay local under ignored docs/validation/redmagic-*.png.

## Platform boundaries

| Target | Decoder support | Current validation |
|---|---|---|
| Android | WAV/MP3/FLAC plus OS AAC/M4A/Ogg | 174 native cases; installed app WAV/FLAC/M4A import and local playback events checked |
| Windows | WAV/MP3/FLAC plus Media Foundation AAC/M4A/Ogg | C ABI/Dart tests and native app M4A import passed |
| iPhone/iPad | Portable formats plus prepared AVFoundation fallback | Source prepared; needs Apple SDK build and device runtime |
| macOS | Portable formats plus prepared AVFoundation fallback | Source/entitlements prepared; needs native runner |
| Linux | WAV/MP3/FLAC | Source prepared; native app build/runtime pending |

Desktop/Apple file filters list decoder formats explicitly; the generic Windows
audio filter omitted FLAC. Android retains its native audio/* filter because the
custom extension-to-MIME mapping hid valid M4A files in the actual picker. Every
chosen file still passes bounded native validation. The corrected Android picker
was verified in the installed 0.3.2 build.

Physical sound upload/delete/mute, audible speaker playback, live BLE meter
reaction and codec negotiation remain unverified. User reports audio is not yet
connected/playing. No ESP32 operation was performed to compensate for that gate.
