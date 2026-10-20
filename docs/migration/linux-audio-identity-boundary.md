# Linux audio identity verification boundary

Decision: retain explicit OS-managed audio confirmation on Linux. The current
manual path does not prove the same device identity or completed A2DP profile
connection as the Android/Windows automatic gates. This note introduces no
runtime adapter or dependency change.

## Why a BlueZ transport is insufficient

The proposed read-only predicate was `Device1.Connected == true` plus a live
`MediaTransport1` whose `Device` references that device, whose local endpoint
`UUID` is A2DP Source (`0000110a-0000-1000-8000-00805f9b34fb`), and whose
`State` is `idle`, `pending`, or `active`.

There is a concrete configured-before-OPEN counterexample in BlueZ commit
`fa6ba55020dee3c3183041c854c347b4582448be`:

1. The device's ACL connection already makes `Device1.Connected` true. Its
   getter also accepts an LE connection; it does not report A2DP profile state.
2. `media.c:set_configuration()` creates and exports the transport before
   sending asynchronous endpoint `SetConfiguration`. The transport can be
   observed while the endpoint has not yet accepted configuration.
3. `a2dp.c:endpoint_open_cb()` calls `avdtp_open()` after endpoint acceptance.
   `sink.c` completes the remote-sink profile connection only on
   `AVDTP_STATE_OPEN`; `AVDTP_STATE_CONFIGURED` does not complete it.
4. Public transport state remains `idle` across that transition. Transport
   callbacks distinguish playing from not playing, not CONFIGURED from OPEN.

Primary sources: [Device getter](https://github.com/bluez/bluez/blob/fa6ba55020dee3c3183041c854c347b4582448be/src/device.c),
[transport creation](https://github.com/bluez/bluez/blob/fa6ba55020dee3c3183041c854c347b4582448be/profiles/audio/media.c),
[open sequence](https://github.com/bluez/bluez/blob/fa6ba55020dee3c3183041c854c347b4582448be/profiles/audio/a2dp.c),
[profile connection completion](https://github.com/bluez/bluez/blob/fa6ba55020dee3c3183041c854c347b4582448be/profiles/audio/sink.c),
[transport state handling](https://github.com/bluez/bluez/blob/fa6ba55020dee3c3183041c854c347b4582448be/profiles/audio/transport.c).

Healthy BlueZ removes transports on configuration failure, stream teardown, and
endpoint exit. Another process owning the endpoint is normal. Neither fact
removes the setup window. Repeated snapshots or a settling delay cannot prove
OPEN; the inspected public Device1/MediaTransport1 APIs expose no discriminator
for an initially connected-but-idle stream versus configured-before-OPEN.

## Why a generic libpulse join does not close the window

PipeWire commit `e86cffd0e42c9a9db3fed56c6493a1030892680f` marks a profile
connected during endpoint `SetConfiguration`, before replying. Sink emission
uses that profile bit and the transport without an AVDTP OPEN check.
`pipewire-pulse` exposes those sinks through libpulse, so sink/card corroboration
is not independent proof of completed profile connection.

Primary sources: [configuration handler](https://github.com/PipeWire/pipewire/blob/e86cffd0e42c9a9db3fed56c6493a1030892680f/spa/plugins/bluez5/bluez5-dbus.c),
[sink emission](https://github.com/PipeWire/pipewire/blob/e86cffd0e42c9a9db3fed56c6493a1030892680f/spa/plugins/bluez5/bluez5-device.c),
[Pulse sink serialization](https://github.com/PipeWire/pipewire/blob/e86cffd0e42c9a9db3fed56c6493a1030892680f/src/modules/module-protocol-pulse/pulse-server.c).

Stock PulseAudio differs: outbound A2DP_SINK initialization requires successful
nonoptional Acquire before creating the sink. BlueZ returns an actual AVDTP
transport FD on acquisition success. A freshly published stock PulseAudio
output sink is therefore stronger evidence, but this implementation behavior
is not a universal libpulse connected-profile contract or general Linux proof.
See [PulseAudio initialization](https://github.com/pulseaudio/pulseaudio/blob/77d25a1e613095bdf87a1d13b65e7c330565077a/src/modules/bluetooth/module-bluez5-device.c)
and the pinned BlueZ transport source above.

## Required future regression

Before enabling automatic verification, test an ACL-connected device exposing
the exact outbound transport while endpoint configuration or AVDTP opening is
delayed and then rejected. The gate must remain closed throughout; also verify
that completed, connected-but-idle A2DP works without requiring music.
Simulated lifecycle tests are regression evidence, not physical support proof.
