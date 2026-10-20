# Verified control connection timing — 2026-10-20

The controller no longer waits for the five-second discovery/help window when
automatic discovery has exactly one service-advertising candidate whose address
matches the selected, currently OS-verified Bluetooth audio identity. It closes
the scan through the existing cleanup queue, then connects on the next eligible
turn. Empty, read-only and ambiguous discovery retain their existing window;
empty search still reveals help after five seconds and continues scanning.

This removes an app-imposed wait of up to roughly five seconds for an early
matching advertisement. It does not claim a five-second reduction in physical
connection time: native advertisement arrival, scan cleanup, GATT connection,
service discovery, MTU negotiation, notification subscription and full-status
response times have not been measured by these tests.

After FULL_STATUS and the final fresh OS audio-identity check, saving the speaker
preference runs separately with the existing three-second bound. A slow save no
longer keeps synchronized controls in the controller's `connecting` state.
Success/failure callbacks are guarded by controller generation and disposal;
save failure retains its warning without invalidating a healthy connection.

## Retained identity and readiness gates

- Current OS audio permission and selected A2DP identity are required for the
  automatic path. A saved ID or manual audio confirmation alone cannot authorize
  it. Unrelated MAC addresses and missing advertised service UUIDs are excluded.
- The transport still requires one real compatible GATT service, required
  command/status/meter characteristic properties, and a negotiated capacity
  adequate for the existing unframed full status.
- A requested, complete FULL_STATUS and a fresh same-device OS audio recheck
  remain required. Partial status cannot produce a ready connection.
- Scan cleanup ownership, uncertain-cleanup blocking, cancellation/background
  generation guards and the finite reconnect backoff are retained.

`SpeakerSession` native operations remain awaited in their established order;
timeout values are bounds, not fixed sleeps. Initial preference loading and
native/platform discovery performance remain separate optimization options.

## Android foreground scan configuration

The locked `universal_ble` 3.1.0 Android plugin creates a `ScanSettings.Builder`
and applies scan mode/report delay only when its Android configuration supplies
them. The app previously supplied no configuration, selecting Android's default
low-power scan mode. It now uses the package's public Dart API:

```dart
PlatformConfig(
  android: AndroidOptions(
    scanMode: AndroidScanMode.lowLatency,
    reportDelayMillis: 0,
  ),
)
```

The plugin forwards `PlatformConfig.android` through its generated
`UniversalScanConfig` into native `setScanMode` and `setReportDelay` calls.
`AndroidScanConfig` is not a public type in the locked package.

Android documents low latency as its highest scan duty cycle and recommends it
for foreground use; low power is the default and is enforced outside foreground.
See [ScanSettings](https://developer.android.com/reference/android/bluetooth/le/ScanSettings#SCAN_MODE_LOW_LATENCY).
Android documents zero report delay as immediate result delivery rather than
batching; see [ScanSettings.Builder.setReportDelay](https://developer.android.com/reference/android/bluetooth/le/ScanSettings.Builder#setReportDelay(long)).
This does not promise a particular advertisement-arrival time or override OS
radio policy. Explicit zero batching delay is not evidence that the previous
default was batching.

Foreground setup still owns and stops scanning on cancellation/background/exit.
Identity matching, connection readiness, discovery-help timing and scan cleanup
are unchanged by this transport configuration. No background service, firmware
change, permission expansion or native plugin modification was added.

## Test evidence

`test/setup_connection_latency_test.dart` adds fifteen deterministic fake-
transport cases. An exact verified candidate must synchronize within a 500 ms
virtual test window rather than wait five seconds. Other cases preserve the
status gate, unknown/manual/permission/ambiguous/wrong-MAC/missing-service blocks,
empty-search help timing, cancellation/background/audio-change invalidation and
read-only discovery behavior. A gated-save test isolates persistence from
discovery and verifies that it does not hold controls busy.

Root-agent SDK receipts were independently read back:

- `artifacts/android-ship-20261020/latency-red.log`: twelve passed and three
  expected behavioral failures before the controller change: early matching
  connection, early full-status synchronization, and pending preference save.
- `artifacts/android-ship-20261020/latency-green.log`: all 78 tests passed across
  latency, discovery flow, automatic reconnect, setup identity and continuous
  discovery suites.
- `artifacts/android-ship-20261020/scan-mode-red.log`: six native adapter tests
  passed and the new explicit scan-mode test failed with `lowLatency` expected
  and null configuration observed before the transport change. The new real-
  adapter foreground-stop regression already passed. A fresh post-change SDK
  receipt is required before claiming this configuration test passes.

Two prior discovery tests that intentionally enforced a five-second successful
automatic scan were updated for the user's faster-connection request. Empty
discovery/help and read-only timing expectations remain unchanged.

Reproduce from the Flutter app directory:

```powershell
flutter test test/setup_connection_latency_test.dart test/discovery_flow_test.dart test/setup_auto_connect_test.dart test/setup_controller_test.dart test/continuous_discovery_test.dart --reporter expanded
flutter test test/session_test.dart --plain-name "native adapter contract" --reporter expanded
```

These fake-transport results establish controller behavior and guards. They do
not establish fresh Android installation, phone-to-speaker elapsed latency, RF
delivery, acoustic output, or connected-transition visual quality; those require
the separate root-agent device checks.
