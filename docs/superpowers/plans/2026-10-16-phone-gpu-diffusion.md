# Phone GPU Diffusion Implementation Plan

> **For agentic workers:** Use the existing scoped agent for the new shader module;
> root owns app integration, SDK commands, build and emulator verification.

**Goal:** Compute the app's diffused LED light on supported phone GPUs while
retaining smooth gradients, source effect geometry and compatibility fallbacks.

**Architecture:** Two separable16-tap Gaussian passes produce GPU-resident
Float32 core/halo images via Picture.toImageSync. Impeller and a completed
fractional-value probe must pass before this route is selected: the installed
Skia implementation ignores the float target. The existing final shader retains
title shading and final dither; the validated native Float32 CPU preparation
remains the fallback. Only the original1KiB source image is uploaded per frame.

**Tech stack:** Flutter3.44.4, dart:ui FragmentProgram/Picture, Impeller, existing
portable16×16 source renderer. No original ESP32 or physical phone operations.

- [x] Write/run failing tests for backend selection and field renderer; retain
  the failed Skia32F probe as evidence, never claim its8-bit output is float.
- [x] Add gpu_light_fields.dart and led_gaussian_pass.frag. Validate fractional
  core/halo samples against independent Gaussian math once, with bounded
  readback before enabling. No per-frame CPU field build or readback on GPU route.
- [x] Integrate owned per-preview renderers in main/gallery; preserve generation,
  source clock, reduced motion, disposal and coalescing. Prewarm behind the B intro.
- [x] Run full tests/analyzer/review. Build normal main PreviewOnly Android ABIs;
  install emulator-5580 using hardware renderer and the subsequently authorized
  graphics-only Redmagic build. Verify actual capability,
  gradient/shape/autoplay and shader/resource behavior. Record physical-phone
  validation limits and restore the user's observed local effect where practical.

App hardware acceleration was already enabled. This changes the optical field
computation, not the Android permission or device-connection gates. The earlier
emulator presentation experiment is separate: software was abandoned on user
instruction, VulkanNativeSwapchain crashed this host before boot, and original
hardware -gpu host was restored. No global driver/HDR setting changed.

The user subsequently approved Redmagic graphics-only installation/testing.
Native phone Spectrum is smooth; foreground guards preserve the later Settings
session. Native hardware OpenGL/Impeller emulator probe and production GPU route
pass. Windows resized-window presentation remains a recorded QA limitation.
See [native GPU and phone receipt](../../validation/2026-10-16-phone-gpu-diffusion.md).
