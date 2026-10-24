# Flutter migration status

Updated 2026-10-24. The universal port remains incomplete; the installed Android
0.7.2 build remains the current internal functional checkpoint. Active Flutter
source is at the repository root on `main`. The original Kotlin app is preserved
at its original root on the
[`legacy-kotlin` branch](https://github.com/WillyBilly06/BDK-AUDIO-APP/tree/legacy-kotlin).

The [beat-source comparison](../validation/2026-10-24-beat-source-comparison.md)
documents the read-only ESP32 investigation and an app-only fix for detected
onsets lost between notification delivery and a UI frame. A new timestamp
handoff preserves the latest onset separately from changing level samples. This source
change has not been installed on the phone. The
[owner-controls proposal](../proposals/owner-controls.md) considers issue #15;
speaker-wide protection is not implemented.

## Android 0.7.2 checkpoint — 2026-10-20

Implemented: focused Sound/Light/Speaker navigation; original active presets,
custom profiles and Android export import; fixed-band tone controls and accurate
sound options; real audio-first BLE discovery/session/reconnect; branded startup
and pairing; all 22 copied native LED effects with GPU diffusion and a clearly
estimated three-meter reactive preview; Ambient/Off controls; local sound import,
trim/conversion/preview and four-slot transfer clients; local raw/encrypted OTA
client; app information and bundled notices.

The Android completion adds current codec/rate/depth/channels/source/freshness,
explicit LDAC nominal bitrate/quality preferences including selection from its
default mode, identified LHDC V5 nominal target requests, same-device negotiated
confirmation, and a compact config strip on all three main tabs. Unknown vendor
quality fields remain device-managed. Actual
Bluetooth transmission bitrate is not reported through this Android contract.

Connection success skips the earlier five-second successful-discovery dwell for
an exact verified service candidate. Saving the last speaker no longer delays
healthy controls. Connected controls reveal without an additional readiness
delay and preserve state across reduced-motion changes. Brightness-only changes
use command 0x07 instead of resetting the effect. Meter onsets use timestamp-aware
adaptive flux; synthetic results and their weak-dynamics limits are documented.

Checkpoint integration evidence: 699 Flutter tests passed, two skipped; analyzer clean;
25 native renderer tests and 13 native codec checks passed; ARM64 release-mode
APK compiled with normal main and preview-only false. Package, installed phone
evidence and remaining gates are in the
[Android delivery receipt](../validation/2026-10-20-android-delivery.md).

The checked Redmagic A2DP API experiment confirmed LHDC V5 1000-to-900 kbps
target switching and exact original configuration restoration. A target is not
measured transmission bitrate. See the [API research and receipt](../validation/2026-10-20-android-codec-api.md).

Sound/OTA transfer state machines are fake-transport validated for this checkpoint;
no physical upload/delete/update was used for QA. ACK, worker COMPLETE, presence
readback and durable persistence remain separate evidence boundaries.

The Redmagic is the Android runtime target; prior Windows/Linux preview evidence
and Apple/Linux gaps remain in the [platform matrix](../platform-release-matrix.md).
The internal APK keeps the existing development certificate for a data-preserving
upgrade; public signing, platform release packaging and broad device validation
remain open. Original Android app and unrelated Linux WIP are preserved.

The 0.7.2 completion used no ESP32 source access, firmware edits/builds, serial
operations or flashing. The later 2026-10-24 source comparison is read-only;
existing BLE packets remain the only speaker preview input.
