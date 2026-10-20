# Saved speaker and reconnect checkpoint

Development preview 0.5.4. The full production goal remains active.

## Implemented connection behavior

The client remembers the last speaker only after valid full status and a fresh
final OS audio check. A saved ID is a preference among verified connected audio
identities; it never authorizes discovery by itself. Unknown multiple identities,
denied permissions and missing audio remain manual/recovery states.

In full connection builds, verified audio starts discovery. The matching saved
or sole candidate connects after two seconds. Failed discovery or connection
gets three retries after 2, 4 and 8 seconds, then stops. A stable 30-second
connection, a new audio epoch or a new foreground activation permits recovery
later; rapid ready/lost cycles do not continuously reset the retry budget.
Cancel and Disconnect remain stopped until explicit Search/Connect.

Backgrounding cancels pending work; desktop `hidden` is handled as well as mobile
`paused`. Old connection cleanup is published before phase callbacks and fences
replacement scan/connect calls. Native close is bounded by the existing timeout;
its expiry does not prove physical disconnection. Uncertain cleanup stops
automation, including a retry already waiting on that cleanup. Manual selection
can establish a new fully synchronized link before automation resumes.

Versioned `last_speaker_v1` preference storage is independent of presets. Reads
and writes are queued, identifiers are bounded, and unreadable/newer records
survive refused writes. Storage failure shows a warning without tearing down a
healthy connection.

`BDK_PREVIEW_ONLY=true` disables automatic discovery/connection in every installed
QA package. Manual-confirmation platforms also retain manual control selection.
No physical automatic reconnect or Apple/Linux identity validation is claimed.

## Verification and review

Final analyzer clean; full suite **517 passed**, one optional screenshot capture
skipped. Added checks cover preference storage, cancellation/generations, full
status, fresh OS rechecks, finite retries, stable/flapping links, cleanup fencing,
native pre-return failures and app Disconnect/desktop-hidden integration.

Meaningful RED failures preceded the fixes. Tests drain the Dart SDK's cached
root-zone stream-cancellation future separately from the virtual widget clock;
the diagnosed test hang required no production workaround.

One independent integrated review found two Important issues: native cleanup
failure during rejected discovery was swallowed before a BleLink reached the
session, and desktop `hidden` did not stop foreground automation. Both were
reproduced and fixed in one pass. A typed cleanup-uncertainty receipt retains
the original discovery cause and reaches Session before failure notification.
No second review or physical release approval is implied.

## Native packages

Android ARM64 and Windows x64 Debug builds use `lib/main.dart` with the preview
flag. The Redmagic APK's local, transferred and installed base.apk hashes match.
Version 0.5.4 / code 2012 cold launched in 907ms; transfer completed in 149.7s.

- `artifacts/bdk-audio-design-preview-0.5.4.apk`: 90,344,322 bytes.
- SHA256: `f352d6fe89792fa9de7a3e5d7003beb01c11cc44530dedd1bfb99f6ed8f67f7d`.

Native phone startup stays on Bluetooth audio setup with no connected speaker;
Demo remains explicit. App info shows Version 0.5.4 / Build 2012. Startup,
information and Light screenshots were inspected. Two native Spectrum demo
captures differ at 133,482 of 520,000 pixels in a fixed interior artwork region
(25.67%), excluding the clock and controls. This demonstrates animation after
the initial Light visit, not a frame-rate or live-audio measurement. The phone
was left on animated Spectrum at 70% in labeled Demo.

Windows native startup and Demo were inspected; App info shows Version 0.5.4 /
Build 12. A different configuration window initially occluded the preview; BDK
was activated and its own screen verified before any click. No driver settings
were changed. The tested BDK window was closed afterward.

- `artifacts/bdk-windows-design-preview-0.5.4.zip`: 45,995,031 bytes.
- SHA256: `4fe867563c2d61bb591f5bdedd13dfbb335bb8a0a5aed91b447908806671d3dc`.
- All 20 archived bundle files match built sizes and SHA256 hashes.

These are local development packages. Original app installation/data, older
ADB/VM processes and other devices are preserved. Exact self-created remote QA
files were removed; local captures and reports remain ignored artifacts.

## Remaining gates

The original saved/single-speaker convenience is implemented in the client.
Physical reconnection, OEM/driver close behavior and actual music/meter/codec
evidence remain pending user audio readiness. Apple/Linux native execution,
spoken accessibility, full-app/long-running audio performance, branding,
signing/distribution and trusted updates remain open in the
[platform matrix](../platform-release-matrix.md). No ESP32 source changes, builds,
serial access, flashing, controls, sound transfers or updates were performed.
