# Linux audio import parity gap

Read-only review, 2026-10-16. This is a proposed next implementation task, not an
implemented decoder or successful format-validation receipt. The current native
WAV import gate passes; Linux's additional-format limitation remains.

## Current behavior

`packages/bdk_audio_decoder/src/CMakeLists.txt` builds the unsupported fallback on
Linux. The portable miniaudio path handles WAV/MP3/FLAC. MP4/M4A, ADTS AAC and Ogg
can pass the shared container check but return unsupported from that fallback.
`lib/features/sounds/sound_import_io.dart` therefore advertises only
`wav`, `mp3`, `flac` in the Linux picker. Other target adapters have conditional
native support for additional containers. App imports are privately copied to
`source_N.audio`, so a backend must recognize content independently of extensions.

## Builder recommendation

Use a Linux-only offline GStreamer fallback, explicitly linked by that decoder
target. The locked audioplayers Linux dependency already uses core/app/audio
GStreamer libraries; this does not automatically give the decoder those links
or every codec plugin. Preserve the existing C ABI, portable decoder, downmix,
resampler, output-frame coordinates and typed errors.

Feed the already-open, size-checked descriptor into a bounded random-access
`appsrc`. Do not reopen the pathname, accept URI redirects or use playback sinks.
Select only the intended audio demuxer/parser/software decoder route, ending in
native-rate/channel interleaved float PCM and the existing `BdkPcmWindow`.
AAC-in-MP4 uses qtdemux/aacparse/avdec_aac; ADTS uses aacparse/avdec_aac;
Ogg/Vorbis uses oggdemux/vorbisdec. Planar AAC output needs layout conversion.
[AAC decoder](https://gstreamer.freedesktop.org/documentation/libav/avdec_aac.html),
[AAC parser](https://gstreamer.freedesktop.org/documentation/audioparsers/aacparse.html),
[Vorbis decoder](https://gstreamer.freedesktop.org/documentation/vorbis/vorbisdec.html).

Random access is material to MP4 presentation semantics: the pinned 1.20.3
qtdemux implementation discards complex edit lists in push mode. File callbacks
must honor the checked size and any bounded ADTS view, and distinguish early
physical EOF from the expected boundary.
[1.20.3 appsrc contract](https://raw.githubusercontent.com/GStreamer/gstreamer/1.20.3/subprojects/gst-plugins-base/gst-libs/gst/app/gstappsrc.h),
[1.20.3 qtdemux](https://raw.githubusercontent.com/GStreamer/gstreamer/1.20.3/subprojects/gst-plugins-good/gst/isomp4/qtdemux.c).

Decode from the presentation origin and discard earlier PCM without retaining
it. Convert sample timestamps through their GstSegment; raw PTS need not begin
at zero. Respect existing decoder/demuxer clipping rather than applying encoder
delay twice. A conservative implementation can first count contiguous decoded
PCM, then recreate the pipeline on the same descriptor for the selected window.
Declared MP4 presentation coverage must agree with decoded coverage; reject
gaps, missing samples and unexpected format/segment changes.
[Segment conversion](https://gstreamer.freedesktop.org/documentation/gstreamer/gstsegment.html),
[clipping metadata](https://raw.githubusercontent.com/GStreamer/gstreamer/1.20.3/subprojects/gst-plugins-base/gst-libs/gst/audio/gstaudiometa.h).

## Dependencies and practical limits

The Noble runner includes base/good/bad/ugly/libav runtime plugins. The current
Jammy validation root deliberately installs base/good only; AAC would need
`gstreamer1.0-libav` there. Missing plugins remain unsupported, with no runtime
download. Actual element creation and negotiated decoding establish capability;
linked libraries alone do not. System packages fit the current Linux bundle's
dependency model, but a bundled distribution would need its own packaging and
license review.

Use bounded non-dropping appsink queues, timed pulls and one monotonic deadline
across both passes. Report bus errors, timeout and missing declared coverage;
never manufacture silence or return partial success. Plugin-internal allocation,
blocking and teardown cannot be strictly contained by an in-process deadline.
A supervised helper with inherited descriptor and OS limits would be a larger
design if that stronger guarantee is required. GStreamer has process-global
registry/runtime state: initialize safely and never deinitialize it per call
while audioplayers shares the process.
[1.20.3 appsink](https://raw.githubusercontent.com/GStreamer/gstreamer/1.20.3/subprojects/gst-plugins-base/gst-libs/gst/app/gstappsink.c),
[runtime lifecycle](https://gstreamer.freedesktop.org/documentation/gstreamer/gst.html).

## Required implementation evidence

- Real AAC-LC mono/stereo at 16/44.1/48 kHz, faststart/end-moov M4A, raw/tagged
  ADTS and Ogg/Vorbis. Include independent priming/padding and nonzero edit-origin
  fixtures.
- All four existing output rates and origin/nonaligned-middle/late/exact-tail
  windows. Compare slices with full conversion within the existing two-PCM-unit
  tolerance, plus an independent presentation-length/alignment reference.
- Truncated/damaged headers, selected packets and tails; malformed edit lists,
  gaps, format changes, chained Ogg, encryption and external references. Missing
  declared coverage must fail with zero written samples.
- Extension-independent private `.audio` imports, Unicode names, pathname
  replacement, growth/shrink and ordinary in-place changes. Same-handle identity
  is distinct from immutable file bytes.
- Missing plugins/runtime, concurrent calls, repeated failures, bounded resource
  observations and cleanup. Finally exercise the shipped Linux app through its
  real picker, Dart isolate, native library and persisted draft without playback.

Do not expand the Linux picker or advertise new formats before these gates pass.
The existing unchanged 0.5.6 Jammy ABI/runtime job proceeds independently.
