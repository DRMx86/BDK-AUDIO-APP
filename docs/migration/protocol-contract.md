# Current speaker protocol reference

Source-derived reference for the Flutter port, 2026-10-16. This is a design and
compatibility record, not a hardware capture or implementation. Source hashes are
in `evidence/firmware-protocol-source-snapshot.json`. Recheck them before coding
against a firmware tree changed by another task.

## Service and packet boundaries

| Role | UUID | Properties used |
| --- | --- | --- |
| Service | `12345678-1234-1234-1234-123456789000` | Discovery |
| CMD | `12345678-1234-1234-1234-123456789001` | Write / write without response |
| STATUS | `12345678-1234-1234-1234-123456789002` | Notify |
| METER | `12345678-1234-1234-1234-123456789003` | Notify |

Commands and status notifications begin with a one-byte ID. Meter notifications
have three raw bytes and no ID. Multi-byte integer fields are little endian.
EQ fields are signed int8 two's-complement; level/color/flag fields are unsigned.
Reads return no status data. Subscribe to STATUS and METER before requesting sync.
An ATT write response is sent before the application command is processed, so it
is not an application ACK or proof that an update was applied.

## Commands

| ID | Name | Payload after ID | Port constraints |
| --- | --- | --- | --- |
| 01 | SET_EQ | bass i8, mid i8, treble i8 | Each -12..12 wire levels; send actual values for app presets |
| 02 | SET_EQ_PRESET | firmwarePreset u8 | Only firmware IDs 0..11; not Android UI preset IDs |
| 03 | SET_CONTROL | flags u8 | bit0 bass boost, bit1 channel flip, bit2 crossover bypass |
| 04 | SET_NAME | name bytes | See current rename behavior below |
| 05 | SET_LED | effect, brightness, speed, r1,g1,b1,r2,g2,b2,gradient | Exactly 10 payload bytes; brightness/speed 0..100 |
| 06 | SET_LED_EFFECT | effect u8 | User effects 0..21; 22 is an internal volume effect |
| 07 | SET_LED_BRIGHT | brightness u8 | 0..100; use 0 for Off, preserving prior nonzero brightness |
| 10 | SOUND_MUTE | muted u8 | 0/1; affects notification sounds |
| 11 | SOUND_DELETE | soundType u8 | 0 startup, 1 pairing, 2 connected, 3 max-volume |
| 12 | SOUND_UP_START | soundType, size u24LE | Total WAV bytes, including header |
| 13 | SOUND_UP_DATA | seq u8, bytes | Starts at sequence 0, wraps 255 to 0 |
| 14 | SOUND_UP_END | none | Completion comes from worker status |
| 20 | OTA_BEGIN | size u32LE | Raw application image bytes, not encrypted container bytes |
| 21 | OTA_DATA | seq u8, bytes | Firmware currently discards the seq byte; not resumable |
| 22 | OTA_END | none | Finalize request, not a success claim |
| 23 | OTA_ABORT | none | Abort is translated to the existing ASCII handler |
| F0 | REQUEST_STATUS | none | Full status uses a separate cached state |
| FF | PING | none | Expect PONG FF |

Do not map shared `DeviceModels.kt` flags directly: that file reverses channel
flip and bypass compared with `main.cpp:143`. Ignore its unsupported TWS/mute bits.

## Status notifications

| ID | Name | Payload after ID |
| --- | --- | --- |
| 01 | STATUS_EQ | bass i8, mid i8, treble i8 |
| 02 | STATUS_CONTROL | control flags u8 |
| 03 | STATUS_NAME | name bytes |
| 04 | STATUS_FW | firmware version bytes |
| 05 | STATUS_LED | Same 10-byte unified LED format as SET_LED |
| 06 | STATUS_SOUND | bits0..3 sound file presence; bit7 notification sounds muted |
| 10 | ACK_OK | command ID |
| 11 | ACK_ERROR | command ID, error code |
| 20 | OTA_PROGRESS | percent u8 |
| 21 | OTA_READY | none |
| 22 | OTA_COMPLETE | none |
| 23 | OTA_FAILED | error code |
| 30 | SOUND_PROGRESS | percent u8 |
| 31 | SOUND_READY | none |
| 32 | SOUND_COMPLETE | none |
| 33 | SOUND_FAILED | error code |
| F0 | FULL_STATUS | Layout below |
| FF | PONG | none |

The general error namespace is NONE 00, INVALID_CMD 01, INVALID_PARAM 02, BUSY 03,
OTA_INIT_FAIL 10, OTA_WRITE_FAIL 11, OTA_VERIFY_FAIL 12, SOUND_INIT_FAIL 20,
SOUND_WRITE_FAIL 21. Sound worker failures also use context-specific codes 01..0B;
keep the raw code and response family rather than assuming one global enum.

Full status after response ID:

`[bass,mid,treble][control][LED x10][sound][nameLength][name...][fwLength][fw...]`

Including response ID, length is `18 + nameLength + fwLength`. Lengths count UTF-8
bytes, not characters. Empty strings still require both length fields. Do not
decode a truncated packet as a partial successful sync.

Current firmware may split this packet into notifications of `MTU - 3` bytes
without an envelope, offset, or fragment flag. A client cannot reliably separate
those fragments from interleaved status messages. Require sufficient capacity or
a negotiated framed extension; never guess a reassembly boundary.

## Meter data and LED behavior

METER is `[level30,level60,level100]`, normalized 0..100. Decode approximate dB as
`level * 0.6 - 60`. Thus `00 32 64` means about -60/-30/0 dB. These are DSP-relative
band levels, not acoustic SPL or EQ gain values. Mark missing data stale instead
of generating replacement sine/random audio that appears live.

The current sdkconfig requests a 30 ms meter period; it is not a guaranteed 50 ms
period. Meter traffic is best effort and skipped under low heap. The actual LED
renderer has its own cadence and reads AGC-normalized inputs, beat edges, effect
history/random state, and overlays. Three meter values alone cannot reproduce it.
For example, LED bass uses the sum of 30 Hz and 60 Hz linear levels, mid uses
100 Hz, and high uses a peak band, followed by boost and AGC. It is incorrect to
feed the three displayed meter positions into those three renderer inputs as if
they were identical quantities.

User effects are 0 Spectrum, 1 Beat Pulse, 2 Ripple, 3 Fire, 4 Plasma, 5 Matrix
Rain, 6 VU Meter, 7 Starfield, 8 Wave, 9 Fireworks, 10 Rainbow Wave, 11 Particle
Burst, 12 Kaleidoscope, 13 Frequency Spiral, 14 Bass Reactor, 15 Meteor Shower,
16 Breathing, 17 DNA Helix, 18 Audio Scope, 19 Bouncing Balls, 20 Lava Lamp,
21 Ambient. Gradients are 0 solid, 1 horizontal, 2 vertical, 3 radial, 4 diagonal.
Do not send 255 as a firmware effect: Off is zero brightness in this implementation.

Brightness travels 0..100, but the renderer stores 0..255. Preserve the firmware's
conversion/rounding and distinguish settings state from post-brightness pixels.
Random generation uses a static 16-bit recurrence seeded at 1337, shared among
effect calls; merely using the same initial seed does not synchronize a client
that joins after the speaker has been running. `setEffect()` re-initializes the
effect even when the ID repeats, so redundant effect writes can reset animation.

## Transfer constraints

Let `W` be the actual maximum characteristic-value bytes accepted by the platform,
bounded by `MTU - 3` and the attribute limit. Both sound and OTA data have a
two-byte command+sequence header. Use data capacity `W - 2`, not a hard minimum
payload size. At MTU 23, a 20-byte attribute value carries at most 18 data bytes.

Sound accepts at most 512 data bytes in its worker buffer, but that does not
increase the negotiated attribute capacity. Only one data write may be pending
at once in the baseline protocol: await both transport completion and SOUND_READY.
The START response allows transmission; data READY is emitted after worker write.
Wait for SOUND_COMPLETE or SOUND_FAILED at the end. Cancellation has no explicit
sound-abort command today; disconnecting BLE triggers cleanup and leaves Classic
audio as a separate connection. Do not invent a working abort packet.

The compatibility audio format is mono PCM16 WAV, preferred 22.05 kHz, with the
existing app's 200 KiB total bound and explicit lower-rate/trim feedback. Firmware
storage validation must also pass. The current sound worker deletes an old sound
before writing its replacement; cancellation/failure can therefore lose that old
file. Atomic replacement requires a firmware temporary-file/commit path and enough
storage. An app alone cannot promise preservation without protocol/file support.

OTA data with a one-byte raw payload is currently ignored as a legacy flush packet.
Partition outgoing chunks so there is no one-byte final remainder. Do not pad an
image or count ignored bytes as sent successfully. OTA sequence values are not
checked, so retrying an uncertain DATA write can duplicate bytes. Use finite
failure handling and a fresh transfer rather than claiming resumption.

OTA_BEGIN must receive OTA_READY before data. Wait for OTA_COMPLETE/OTA_FAILED,
then reconnect and verify firmware identity/version before success. ACK_OK for
OTA_ABORT is a different response from OTA_COMPLETE. The existing raw-byte counter
increments without checking the return of `g_update.write`, and `end(true)` skips
the updater's exact expected-size check. Neither a progress percentage nor a
transport ACK proves the full image was written.

## Source limitations outside the current app-only scope

These are read-only source findings; none has been patched or physically
reproduced here. The user explicitly cancelled firmware work. Handle these limits
in the app and report unsupported confirmation; do not edit/build/flash firmware.

- **Stale status cache:** SET_EQ/SET_EQ_PRESET and SET_CONTROL invoke callbacks
  that call `applyEq(...,false)` / `applyControlByte(...,false)`. Those functions
  update DSP/NVS but skip the only BLE-cache setters. `processCommand` then emits
  ACK_OK without updating cache. LED settings/effect/brightness callbacks similarly
  skip their BLE update calls. REQUEST_STATUS/reconnect can report stale settings.
  Cache mutation must be separate from whether to send an echo notification.
- **Rename bounds/state:** SET_NAME passes a length, but `onBleName` ignores it and
  calls C-string consumers. A nonterminated payload can be read beyond its intended
  bytes; it also does not update the BLE cached name. Use a bounded, terminated
  UTF-8 name and one consistent stored/cache/advertised identity. NVS loading uses
  a 32-byte buffer, so keep a maximum of 31 UTF-8 content bytes for compatibility.
- **Full-status size:** its stack buffer is 64 bytes while cached name/version
  arrays allow up to 63/31 content bytes. Enforce the computed packet bound and
  explicit fragmentation rather than relying on today's short version string.
- **OTA receipt/finalization:** check updater write acceptance, reject size
  mismatch before activation, propagate failures, remove the ambiguous single-byte
  flush behavior in a negotiated protocol revision, and verify after restart.
- **Sound replacement:** commit a verified temporary file atomically and retain the
  previous file on failure where storage permits; report lack of space explicitly.
- **Exact LED mirror:** the existing three-byte meters omit exact renderer
  state/history. Estimate reactive inputs on the app side and preserve the
  legacy UUIDs/commands. No frame/input telemetry extension is in scope. Source
  algorithm reuse is not proof of matching physical pixels or timing.

## Independent checks for implementation

Use `protocol-vectors.json` for signed bytes, flags, LED ordering, size endianness,
sound sequence wrapping, full-status string lengths, truncation, and meters. Those
vectors are source-derived examples, not prerecorded peripheral acknowledgments.

The necessary behavioral gates include write-then-request-status, reconnect after
an app write, encoder changes while the app is open, both Ambient selection paths,
first Spectrum visit, small MTU, invalid/truncated status, interrupted sound
replacement, OTA remainder sizes, write failure, END before complete data,
explicit abort, and restart/version verification. Keep fake-transport, native
hardware, codec negotiation, and renderer-fidelity evidence separate.

DSP source correction: EQ always applies. Crossover bypass selects full-range stereo;
bass boost stays available. Output swap changes low/high assignment only in split
mode. Actual filter centers are 150 Hz / 1 kHz / 6 kHz; wire levels are multiplied
by 0.5 / 0.7 / 0.7 before filter construction.
