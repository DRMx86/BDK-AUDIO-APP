# Saved speaker reconnect implementation plan

> **For agentic workers:** Use superpowers:executing-plans for the controller and superpowers:subagent-driven-development for the isolated preference store. Review the integrated change before native preview packaging.

**Goal:** Restore the approved saved-speaker/automatic reconnect behavior while preserving verified audio identity, full-status readiness and explicit cancellation.

**Architecture:** SpeakerSetupController owns one bounded foreground discovery/connection attempt. A separate versioned preference store remembers only a successfully synchronized speaker. Automatic discovery/connection requires a verified OS audio identity; preview-only builds and OS-managed/manual-confirmation platforms retain manual control selection.

**Tech Stack:** Existing Flutter/Dart, SpeakerSession/BleTransport, SharedPreferencesAsync; no new dependency.

**Spec:** docs/superpowers/specs/2026-10-16-flutter-audio-design.md, connection inventory and bounded reconnect decisions. Original active source evidence: docs/validation/original-feature-parity-audit.md, finding2.

## Global constraints

- App-only work; no supplied ESP32 reads/edits/builds, serial, flashing or hardware operations.
- Original Android is read-only. Preserve current packet IDs and fresh full-status gate.
- All installed native QA builds remain BDK_PREVIEW_ONLY=true; automatic discovery/connection is disabled there.
- Remembered IDs cannot authorize a scan or bypass service/audio identity matching.
- Preserve the approved minimal connecting screen, explicit Demo and cancel action.
- Apple/Linux native identity and physical validation remain release gates.

## Review focus

- A cancelled/backgrounded attempt must not restart when a delayed OS query, scan callback or retry completes.
- A stored device must never override a different currently connected audio identity. A previously selected saved ID can disambiguate currently verified identities; multiple unknown identities require user selection.
- An intentional disconnect must not immediately reconnect; manual Search/Connect explicitly resumes the workflow.
- Failed status synchronization or final audio recheck must not persist a speaker as successful; storage failure must not tear down a healthy connection.
- Repeated failure must stop after a finite attempt budget; no endless scan/connection loop or concurrent connection owner.

### Task1: Versioned saved-speaker preference store

**Files:** lib/persistence/saved_speaker_store.dart; test/saved_speaker_store_test.dart.

**Interfaces:** SavedSpeaker(id,name); SavedSpeakerStore.load()→Future<SavedSpeaker?>; save(SavedSpeaker)→Future<void>. SharedPreferencesSavedSpeakerStore(SharedPreferencesAsync) implements it using a separate versioned key.

- [x] RED for valid round-trip, absent/corrupt/newer/oversized input, validated identifiers and queued writes.
- [x] Implement bounded versioned JSON; preserve unreadable/newer records on refused save, independent of preset storage.
- [x] Focused GREEN and analyzer; hand source and evidence to root.

### Task2: Foreground automatic connection and explicit stop

**Files:** lib/connection/speaker_setup_controller.dart; lib/connection/speaker_session.dart; lib/main.dart; lib/app.dart; test/setup_auto_connect_test.dart; test/session_cleanup_fence_test.dart; existing setup/UI tests.

- [x] RED: verified audio starts bounded discovery; matching saved/sole candidate connects after2s and requires full status; no-audio, permission-denied, manual-confirmation, disabled preview and ambiguous identities never auto-connect.
- [x] RED: cancel/background/audio-change invalidate pending timers and rechecks; intentional disconnect suppresses automation until an explicit Search/Connect; failure retries are bounded2/4/8s then stop.
- [x] RED: a stable30s connection resets the retry budget; rapid ready/lost cycles do not. Logical old-link cleanup fences later scan/connect before phase callbacks; timeout cannot prove physical disconnection.
- [x] Implement optional store and auto-connect configuration, latest identity/generation checks, finite retries and ready-only persistence; retain manual behavior.
- [x] Wire normal app automation and preview-build exclusion; show a rare storage warning without technical format details.
- [x] GREEN focused/full suite and analyzer; independent review, fix material findings, Android/Windows preview builds and native no-audio/Demo checks. Do not exercise a physical control link while user audio readiness is pending.

The current goal remains active. This task restores an app-side capability and cannot prove physical BLE, Apple/Linux runtime or signed production distribution.
