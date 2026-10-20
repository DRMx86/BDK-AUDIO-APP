# Older Linux ABI validation implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and exercise the unchanged Flutter preview in an isolated Ubuntu 22.04 x64 userland, lowering the measured Ubuntu 24 bundle's GLIBC 2.38 requirement where the locked dependencies permit it.

**Architecture:** Use a separate Jammy root inside the existing owned QEMU guest. Build from the same verified 0.5.6 source snapshot and pinned SDK; keep its package database, application profile, generated files and evidence separate from the Noble baseline. No host distribution or application is modified.

**Tech Stack:** Flutter 3.44.4 / Dart 3.12.2, Ubuntu 22.04, clang14, CMake3.22, GTK3, GStreamer, QEMU TCG, Xvfb and a private D-Bus session.

**Spec:** `docs/superpowers/specs/2026-10-16-flutter-audio-design.md`, native target validation in `docs/platform-release-matrix.md`, and the measured ABI baseline in `docs/validation/2026-10-16-linux-runner.md`.

## Global constraints

- No supplied ESP32 source access, physical serial, Bluetooth/audio setting changes, physical device controls, playback, transfers or OTA.
- Only the existing owned guest may receive packages; no Windows-global SDK, virtualization or OS changes.
- Use `lib/main.dart`, `BDK_PREVIEW_ONLY=true`, framework revision `ad70ec4617166f1c38e5d2bfd388af71fda14f06` and the committed lockfile.
- Preserve all copied native algorithm bytes and `-fno-fast-math`; do not bypass native library loading to manufacture a successful preview.
- Preserve every previous artifact and failed observation. Ubuntu22 success does not establish Debian, older Ubuntu, ARM64, physical Bluetooth, GPU performance or signed release support.
- Source manifest: 308 files in the existing reviewed `app-source-056.tar.gz`, SHA256 `0fcb10a86eb935986326008e9cec64cc5f66541a54734e84f3b071d83714ed50`.

## Review focus

- A stale Noble object/library must not enter the Jammy output: fresh build directory, compiler-path receipt and per-ELF version requirements.
- The root/mount/job identity must be bounded: resolved guest-only root, private mount namespace, exact owned process cleanup and no QEMU restart.
- Locked dependencies and reviewed source must survive setup/build unchanged: manifest hashes before and after, lockfile enforcement.
- A compiled binary must actually launch under the target userland: fresh native PID/XID/executable identity, inspected GUI and loaded-library paths.
- A missing portal or renderer service must be reported honestly: actual app Sound import and LED evidence are distinct from direct ABI probes or startup alone.

## Task 1: Isolated Jammy build and native validation

**Files:** Create focused guest setup/job helpers only as needed under `tools/linux_runner/`; create `docs/validation/2026-10-16-linux-jammy.md`; update `docs/platform-release-matrix.md` after evidence. Logs, package inventories, source/ELF manifests, fixtures, images and exported bundles remain ignored under `artifacts/linux-runner/jammy/`.

**Interfaces:** Consume the verified source archive/manifest and pinned SDK checkout already in the owned guest. Produce a complete Debug preview bundle, hashes/modes/type manifest, exact runtime/ABI receipts and a separately labeled compatibility verdict. A Release build is an additional gate, never inferred from Debug success.

- [ ] Record the live owned QEMU/SSH identity and wait for the existing Noble Sound QA to finish before starting guest package/mount work.
- [ ] Create a fresh resolved Jammy root within the guest's owned workspace; use official Ubuntu repositories with signature verification. Reject an unexpected account/root/path rather than reusing or deleting it.
- [ ] Install the exact build/runtime prerequisites in that root, with a bounded guest-only job and preserved start/log/exit records. Record `/etc/os-release`, libc/compiler/CMake/GTK/GStreamer versions and the private mount strategy.
- [ ] Extract the reviewed source into a fresh path with the existing exact-entry/path/type/hash checks. Provide the pinned SDK in a distinct userland path; no Noble application build outputs are copied.
- [ ] Run `flutter pub get --enforce-lockfile`, then `flutter build linux --debug --no-pub -t lib/main.dart --dart-define=BDK_PREVIEW_ONLY=true` with native parallelism2. Record complete output and exit status; do not restart a live job because an observation timed out.
- [ ] Inspect all packaged ELF machine types, dependencies and version requirements. The initial compatibility target is maximum GLIBC2.35 and GLIBCXX3.4.29; retain and explain any higher dependency instead of relabeling it compatible.
- [ ] Launch the actual shipped entrypoint in a separate Xvfb/private-D-Bus session under Jammy. Select Explore Demo after a fresh inspected screenshot and exact PID/XID/title/executable match.
- [ ] Capture colored Light/gallery artwork and bounded animation observations; verify the Jammy-built native LED library is mapped in that same app process.
- [ ] Use the actual Sound file picker and an owned PCM16 WAV to verify local draft duration/waveform through the app's decoder isolate. Capture failure if unavailable; never substitute a direct ABI call for this gate.
- [ ] Rehash every reviewed source file after build/QA. Export the complete bundle preserving executable modes and any symlinks, then independently verify the transferred archive against its manifest.
- [ ] End only owned QA processes/mounts and record their final state; retain the root and all receipts for review.
- [ ] Obtain one fresh focused review of new helper code and evidence claims. Fix material issues, update the platform matrix, and commit this checkpoint without marking the overall migration goal complete.

Execution follows the user's existing authorization to build the approved design, use high-effort agents and validate native applications. No new product behavior, external publication or hardware operation is proposed by this plan.
