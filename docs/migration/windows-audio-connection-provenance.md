# Windows audio connection identity adapter

2026-10-16. App/host-only implementation. No Bluetooth inquiry, BLE discovery,
pairing, connection request, endpoint selection, settings launch, playback,
ESP32 operation, serial access, firmware build, flash or ADB was performed.

## Identity evidence

The adapter publishes a device only when all of these OS observations agree:

1. MMDevice enumerates an active **render** endpoint.
2. Its `PKEY_Device_ContainerId` matches the container of a present MEDIA devnode.
3. That devnode has the OS Bluetooth service property for **Audio Sink** (110B)
   and an explicit Bluetooth device-address property.
4. The same canonical address occurs in a Classic Bluetooth record with
   `fConnected=true`, enumerated with `fIssueInquiry=false`.

Container and address properties are compared directly. The implementation does
not parse opaque endpoint/PnP IDs, reverse a container GUID into a MAC, match
names, assume a paired device is connected, guess Classic/LE address offsets,
or treat every audio endpoint as Bluetooth. The address uses the same colon
format as the installed `universal_ble` Windows implementation. The existing
setup controller still requires that exact address and the BDK BLE service.

Audio Source (110A), HFP, capture, inactive and non-Bluetooth routes are excluded.
Unknown Bluetooth profiles, missing identity properties and ambiguous container
mapping are unsupported. A display name is metadata only. This is an OS-reported
connection/route identity snapshot; it does not prove current playback, audible
output, that the endpoint is default, or a successful BLE connection.

Primary references:

- [Core Audio device properties](https://learn.microsoft.com/en-us/windows/win32/coreaudio/device-properties)
  describe the endpoint's PnP container property.
- [Audio endpoint state constants](https://learn.microsoft.com/en-us/windows/win32/coreaudio/device-state-xxx-constants)
  distinguish active, disabled, absent and unplugged endpoints.
- [Bluetooth search parameters](https://learn.microsoft.com/en-us/windows/win32/api/bluetoothapis/ns-bluetoothapis-bluetooth_device_search_params)
  document connected-record selection and the separate inquiry flag.
- [Bluetooth device-address property](https://learn.microsoft.com/en-us/windows/win32/properties/props-system-deviceinterface-bluetooth-deviceaddress)
  and [service-GUID property](https://learn.microsoft.com/en-us/windows/win32/properties/props-system-deviceinterface-bluetooth-serviceguid)
  define the native identity/profile properties.
- [SetupDiGetDevicePropertyW](https://learn.microsoft.com/en-us/windows/win32/api/setupapi/nf-setupapi-setupdigetdevicepropertyw)
  documents the read-only devnode property query.

Property keys and Audio Sink/Source UUIDs were also checked against the installed
Windows SDK 10.0.26100.0 `propkey.h` and `bthdef.h`. Native code uses typed property
values and bounds every property buffer; no registry scraping is used.

## Contract and fail-closed behavior

Windows uses `bdk_audio/audio_connection`, method `snapshot`. Android keeps the
existing `bdk_audio/codec` channel and its permission behavior unchanged.

Native successful replies have `protocolVersion=1`, `state=ready|unsupported`,
`canVerifyIdentity`, `devices=[{id,name}]`, and `message`. Only native-verified
identities enter the device list. A complete empty result is `ready`; unsupported
mapping has a different diagnostic state/message. A partially supported snapshot
may contain its verified subset while clearly reporting unsupported routes.

The Dart Windows snapshot always **enforces the native identity gate**. Its
`canVerifyIdentity=true` means setup requires a verified listed identity; it does
not claim an unsupported driver was mapped. Unsupported mapping never enables
manual confirmation. Native query errors, incomplete enumeration, timeout,
malformed payload, or a missing bridge throw; setup clears prior authorization.
Other platforms without this native adapter retain their existing explicit
OS-managed confirmation path. There is no shared-controller API expansion.

## Thread, deadline and lifetime bounds

There is one process-scoped native worker and at most one physical query. Native
enumeration has a two-second between-call budget, 256-entry limits and 8 KiB
property buffers. The platform-thread reply deadline is three seconds, and Dart's
channel deadline is four seconds. A synchronous OS provider call cannot be safely
force-killed; if it outlives the reply deadline, its single worker remains occupied
and new requests fail closed instead of spawning more threads.

COM MTA initialization and MMDevice interfaces exist only within the worker's
query and are released before apartment teardown. No audio client or stream is
opened. The worker never owns Flutter channel/result objects. It posts only a
unique generation token; completion and errors are delivered on the platform
thread. Destroying the bridge invalidates its receiver and request gate before
the engine is destroyed. Shutdown never joins a blocked OS call. A queued timer
from an old request cannot expire a newer request before its own deadline.

## Fresh evidence and limits

The native read-only diagnostic on this host returned:

```json
{"status":"ready","canVerifyIdentity":true,"activeRenderEndpoints":15,"presentAudioAdapters":18,"a2dpSinkAdapters":3,"connectedClassicDevices":0,"verifiedRouteCount":0,"unsupportedActiveRoutes":0,"elapsedMs":13}
```

This proves an actual complete **empty-state** query on this host. No unrelated
device names, addresses or opaque IDs were printed. An earlier separate PnP
property read found a Microsoft A2DP adapter reporting Audio Source 110A; source
classification is excluded, not treated as a speaker sink. **Physical matching
against a connected Bluetooth sink remains pending.** OEM drivers that omit these
properties, LE Audio identity paths and other unsupported stacks remain open
platform capabilities, not successful hardware validation.

Recorded RED then GREEN verification:

- 14 compiled native tests: evidence matching/exclusion, ambiguity, normalization,
  request generation, queued timer replacement, bounded worker and shutdown.
- 10 Dart adapter tests plus 15 existing setup-controller regressions: strict
  Windows contract, timeout/late result, unsupported/missing data fail-closed,
  and preserved Android behavior.
- Targeted Dart analysis is clean; Windows Debug host application builds.

Reproduce without opening the app or changing any OS/audio/Bluetooth state:

```text
cmake -S windows/runner/audio_connection_tests -B build/audio_connection_native_tests -G "Visual Studio 17 2022" -A x64
cmake --build build/audio_connection_native_tests --config Release
build/audio_connection_native_tests/Release/bdk_audio_connection_tests.exe
build/audio_connection_native_tests/Release/bdk_audio_connection_tests.exe --inspect
flutter test --no-pub test/audio_connection_adapter_test.dart test/setup_controller_test.dart
```

`--inspect` has a three-second diagnostic deadline and emits counts/status only.
The application executable was built for compile/link evidence; it was not
launched as part of this adapter task. No physical speaker or BLE validation is
claimed by native unit tests, mocked method-channel tests, or that host build.
