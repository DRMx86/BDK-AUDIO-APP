# Brand Reveal and Discovery Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task by task. Root owns the Flutter SDK, emulator and final integration.

**Goal:** Deliver the requested B zoom reveal into a full-screen, genuinely searching speaker-discovery flow, with a musical brand cue and coherent card depth.

**Architecture:** Keep existing source identity/session gates. Separate read-only automatic discovery from automatic connection, use the existing native transport, and present state in a full-size finding screen. Independent brand and discovery UI work share the surface decoration contract; root integrates source timing, theme and native verification.

**Tech Stack:** Flutter 3.44.4/Dart 3.12.2, code-native vector painting, SVG/Sharp exports, existing Universal BLE adapter.

**Spec:** `docs/superpowers/specs/2026-10-16-brand-discovery-design.md`

## Global Constraints

- No ESP32 source/build/serial/flash or speaker-setting/OTA/sound writes.
- User's latest testing instruction is emulator instead of phone. Use owned AVD
  serial `emulator-5580` only; no further phone inputs or installation.
- PreviewOnly Android; no global permission/driver changes. Grants to this app
  inside its isolated AVD are test setup, never host/phone permission changes.
- Preserve exact audio identity, service and complete-status gates; no timer-based Ready.
- Preserve unrelated Linux WIP; explicit staging only.
- No copied JBL art/code; native reference captures stay ignored.

## Review Focus

- Early discovery candidates must not erase the visible searching phase.
- Cancel/background/new searches must cancel old timers and native work.
- Empty/error/permission states must fill the page and retain useful recovery.
- Slow startup and reduced motion must not hide real failures or trap navigation.
- Narrow/large text layouts and decoration shadows must not obscure actions.

### Task 1: Source discovery and surfaces — root

**Files:** `lib/connection/speaker_setup_controller.dart`, `lib/main.dart`, `lib/app.dart`, `lib/theme.dart`, `lib/widgets/surface_decoration.dart`, relevant Sound/Light panel wrappers; `test/discovery_flow_test.dart` and app integration tests.

- [x] Write failing read-only discovery, early-candidate dwell, repeated audio check, cancellation/background and stale-timer tests.
- [x] Observe RED; implement independent autoDiscoverEnabled with bounded real scan exposure and unchanged auto-connect defaults.
- [x] Bind full searching/checking flags into the pairing screen and main startup path. Add shared surface decoration and consistent card shadows.
- [x] Run focused tests, integrate the two UI owners, then full suite/analyzer.

### Task 2: Musical B and animated native intro — brand owner

**Files:** startup widgets/vector mark and tests, `assets/branding/*`, `tools/export_icons.cjs` and generated platform icons.

- [x] Write failing zoom/reveal/mount-order/error/dispose/reduced-motion tests; send root the exact test command for RED before implementation.
- [x] Implement music-related B identity and vector zoom reveal into the ready app; retain real async initialization/error/retry semantics.
- [x] Export/check all native icon scales. Root runs SDK tests and inspects actual rendered/native frames.

### Task 3: Full-size finding and recovery — discovery UI owner

**Files:** `lib/features/pairing/speaker_pairing_screen.dart`, new radar/speaker illustration widget, `test/ui/speaker_pairing_screen_test.dart`.

- [x] Add failing full finding/early candidates/empty recovery/no dialog and responsive accessibility tests; root runs RED first.
- [x] Implement airy radar/illustration plus one shadowed status surface, matching spec and existing callbacks. No source-controller or native protocol changes.
- [x] Render/inspect native Flutter fixtures in both themes; root owns builds and device inputs.

### Task 4: Native review and installed checkpoint — root

- [x] Review visual frames with actual fonts before building; address material review findings.
- [x] Run full suite/analyzer, deterministic exports, Android package/ABI/notice/CRC checks.
- [x] Install verified x64 package in the owned emulator; capture actual zoom,
  discovery timing, full no-audio-speaker recovery, retry and Demo return. Keep
  emulator-rendered motion distinct from actual physical BLE discovery evidence.
- [x] Document exact native evidence and limitations, commit verified scope, leave the broader release goal unchanged.
