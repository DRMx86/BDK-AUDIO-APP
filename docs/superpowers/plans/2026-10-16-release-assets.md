# Release assets implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace scaffold launcher art with the original BDK speaker mark and expose bundled component notices in the native app.

**Architecture:** Retain the original Android speaker vector geometry, rendered from a checked-in SVG master onto the approved dark/cyan palette. Flutter's license registry and license page expose existing package notices plus explicitly bundled font/native notices.

**Tech Stack:** Flutter 3.44.4, Dart 3.12.2, SVG, local Node/sharp export tool.

**Spec:** `docs/superpowers/specs/2026-10-16-flutter-audio-design.md`; original creator/branding evidence in `docs/validation/branding-license-audit.md`.

## Global constraints

- No access to supplied ESP32 sources, serial operations, hardware writes, or changes to Bluetooth/audio settings.
- Native QA builds use `BDK_PREVIEW_ONLY=true`; preserve app data and target only Redmagic serial `9125299103B7`.
- Existing approved BDK typography, cyan accent, focused navigation and original creator credit remain.
- Neither source provenance nor generated notices establish redistribution rights. Do not invent a license grant or publisher identity.
- Linux runner preparation is independent, local and isolated; its evidence belongs in `docs/validation/2026-10-16-linux-runner.md`.

## Review focus

- License access after package metadata failure; notice reading must remain available.
- Large text/narrow screens; the notices row must be reachable without clipping.
- Font and native notices must be present in packaged assets, not just the repository.
- Adaptive icon masks must retain the speaker/waves within Android's safe zone.
- Apple assets must have the declared dimensions and no unwanted transparent marketing icon background; Linux icons and desktop entries must travel with the relocatable bundle.

## Task 1: Readable notices

**Files:** `lib/features/app_info/app_info_screen.dart`, `lib/licenses.dart`, `lib/main.dart`, `pubspec.yaml`, `assets/licenses/*`, `assets/fonts/Manrope-NOTICE.txt`, `packages/bdk_led_engine/LICENSE`, `test/ui/app_info_test.dart`, `test/licenses_test.dart`.

- [ ] Write/run failing tests for App info notice navigation with failed metadata and for complete real bundled font/native notice loading.
- [ ] Add the license registry loader and assets; register once at main startup. Add a reachable `Licenses and notices` row that opens Flutter's native license page independently of metadata.
- [ ] Preserve font OFL texts; additionally expose the exact binary's Manrope copyright metadata. Bundle unchanged native and nested third-party notice texts from audited local inputs.
- [ ] Replace the LED package's literal TODO with a provenance/rights-unresolved notice, explicitly granting no new rights.
- [ ] Run targeted tests, analyzer and full suite; inspect generated native assets/NOTICES after packaging.

## Task 2: BDK launcher exports

**Files:** `assets/branding/*`, `tools/export_icons.cjs`, Android icon resources/manifest, Apple AppIcon PNGs, Windows ICO, Linux desktop/icon resources and CMake.

- [ ] Generate code-native SVG masters from the original speaker/ring/waves geometry with source hash recorded; adapt only canvas/background/safe-zone scale.
- [ ] Use deterministic sharp rasterization at each declared native size. Reuse the square export in App info. No dependency added to the runtime app.
- [ ] Install Android adaptive/round resources, iOS/macOS declared PNG exports, multi-frame Windows ICO and Linux icon/desktop files within the bundle.
- [ ] Run export tool and inspect representative small/large/adaptive artwork plus dimensions/opacity. No implementation-mirroring tests for static art/configuration.

## Task 3: Native validation and checkpoint

- [ ] Increment development version, build Android ARM64/Windows preview bundles sequentially, inspect packaged notices/icon resources, verify hashes, and install without clearing data.
- [ ] Inspect App info/notices on Redmagic and Windows native UI. No claim of live telemetry while the user is not connected/playing.
- [ ] Fresh review of the change, fix material findings, update platform matrix and checkpoint evidence, and commit the reviewed result. Full migration goal remains active.
