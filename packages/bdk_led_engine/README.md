# BDK firmware LED engine

Portable C++17 library and Dart FFI owner. The original firmware's22 effect
classes, configuration and fast-math headers are copied unchanged; see
SOURCE_PROVENANCE.json for hashes and original paths. A memory driver replaces
SPI output and retains HSV, brightness, saturation and serpentine indexing.

NativeLedEngine owns one context and buffers. configure takes the unified10byte
LED payload (effect, brightness/speed0..100, RGB colors, gradient). render returns
a copied16×16 RGBA frame. Dispose explicitly; further access throws StateError.
The original app's Off sentinel (effect255) is accepted by the Dart adapter and
renders black through a zero-brightness source effect; the22 source algorithms
are unchanged. Resuming a normal effect re-applies its configured brightness.
Audio inputs have seven floats (three normalized bands, three dB values, beat
intensity) and beat/audio-active flags. Live rendering always passes these inputs
to the unchanged source effect.

Spectrum's explicit demo/idle mode supplies smoothly changing pseudo-random
bass/mid/high inputs to the original Spectrum renderer. Each context owns its
generator and progression; only rendering advances it at the app's 30 FPS clock.
Brightness and repeated same-effect configuration do not restart the sequence.
This mode does not infer silence from zero, missing or stale audio values: the
caller must explicitly request it. The app can authorize idle animation for Demo
or fresh, confirmed silence while keeping stale meter data in its waiting state.
The existing Particle Burst and Meteor Shower demo clock workarounds remain;
other demo modes continue to use the original source updateDemo methods.

`NativeLedEngine.lightFields(source, haloSigma)` reconstructs an existing 16x16
RGBA frame without rendering/configuring the source effect. It returns owned
float32 RGBA lists: a 256x256 core at sigma 0.8 source cells and a 128x128 halo at
the requested finite sigma in [0.25,32]. RGB is normalized and premultiplied by
source alpha; output alpha is 1. No gain, clamp or 8-bit intermediate is applied.

Output nodes include both domain endpoints. Core coordinates are
`-4 + i*24/255`; halo coordinates are `i*16/127`. Source LED samples stay at
`x+0.5, y+0.5`. For bilinear texture sampling, map a domain fraction `t` to
`(t*(N-1)+0.5)/N`. The native helper caches Gaussian coefficients and scratch
storage per context and performs horizontal then vertical passes. Dart input
and output buffers allocate lazily, are released on dispose, and each returned
list remains independent of later calls and disposal.

Tests exercise the real C ABI and Dart boundary. Source algorithm reuse does not
establish physical pixel/clock/random-state parity with a running ESP32.
