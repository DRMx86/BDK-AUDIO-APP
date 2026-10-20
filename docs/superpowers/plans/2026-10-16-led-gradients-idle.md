# LED gradient quality and Spectrum idle

**Goal:** Remove visible contour bands across main/gallery light previews and
randomize Spectrum in Demo and fresh confirmed silence, as selected by the user.

**Design:** Floating-point Gaussian core/cover reconstruction, title shade and
dithering before final display quantization. Uniform frames use analytic Gaussian
rectangle integrals. Other frames use cached separable native Float32 fields,
decoded explicitly to Float32 textures and sampled linearly at endpoint-aligned
nodes. The final shader needs two field samples; the exact16×16 gather remains
the fallback. Source-black and zero opacity bypass the pass. No effect geometry
stretching or source firmware change. Cache programs, own/dispose shader and image
instances, prewarm after the first raster, and preserve the30FPS source clock.
Coalesce pending texture work without discarding every incoming source frame.
Effect selection resumes paused playback unless reduced motion is enabled.

The app-owned native wrapper feeds Spectrum smooth per-context pseudo-random
band inputs only for an explicit demo/idle call. Live inputs and all copied effect
algorithms remain unchanged. Dart authorizes connected idle only for a fresh
zero-valued meter with no active audio; stale/missing/positive BLE is never idle.
Show an idle label, and return to waiting when the meter expires.

**Constraints:** No original ESP32 source/build/serial/hardware or phone action.
Use owned emulator-5580/PreviewOnly; preserve Linux WIP and the active Windows app
with its locked native DLL. Build native tests in separate native_renderer_quality.

- [x] Reproduce gradient banding and old repeating Spectrum in failing tests.
- [x] Implement shared diffusion and idle gating; check blackout, live-byte
  preservation, freshness/active/other-effect boundaries and shader lifetimes.
- [x] Run full suite/analyzer/nativeCABI/provenance checks and review. Compile
  all Android ABIs; install only owned emulator. Inspect dark Beat Pulse, saturated
  and sparse effects, gallery and randomized Spectrum; measure native motion
  cadence/performance before accepting the shader. Document finite evidence.

Native0.6.7 receipt: [gradients and playback validation](../../validation/2026-10-16-led-gradients-playback.md).
600Flutter tests,25CABI tests and analyzer pass. Native autoplay and dark
gradients were inspected; finite presentation/capture measurements and their
limits are recorded. The broader platform release remains separate work.

The0.6.5 post-quantization grain pass was insufficient in the user's emulator
check. An independent row-mean reference catches the remaining stepped mean;
the float renderer reduces worst error from0.50 to0.05 RGB levels. Nonuniform-edge
and isolated-cell tests also reject stepped sampling and split glow lobes.
The0.6.6 direct gather was visually accurate but slow on the native emulator;
0.6.7 adds the separable field cache. Tests compare native fields with an
independent double Gaussian, cached/direct final pixels, fractional texture
decoding, ownership after disposal, async coalescing and synchronous fallback.
