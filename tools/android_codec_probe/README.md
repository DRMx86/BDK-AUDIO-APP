# Read-only Android codec API probe

Development instrumentation for the explicitly authorized Android device. It
targets the installed BDK app, uses its normal permission/attribution context,
queries one connected device named BDK SPEAKER and prints codec fields,
selectable rows, extended wire identities and available codec/LHDC profile method
signatures. It does not query other device identities or invoke any setter,
pair/connect/disconnect, route change, private encoder API or hidden-API exemption.

Build as a separate instrumentation APK against android.jar, sign with the same
development certificate as the internal BDK APK, and run through standard Android
instrumentation. This can stop/restart the app's process, so its BLE session must
reconnect afterward. Never use `--no-hidden-api-checks` or change OS policies.
Read-only probe success does not establish that a production setter works or
that a nominal target is an observed encoder bitrate. Remove the probe package
after the finite research run. No probe code is bundled in the production app.

## Explicit LHDC preference check

`com.bdkaudio.codecprobe.LHDCPreferenceCheck` is a separate **mutating**
instrumentation entry point. `CodecProbe.java` remains unchanged and read-only;
the new check reports `readOnly: false`. Include both Java classes in the separate
instrumentation APK and use the existing development signing certificate. It
requires the target package's already granted normal Bluetooth permission and
checks that the instrumentation certificate matches the target certificate.
Do not include this tool in the production APK.

Root may run the following only on the specifically authorized Redmagic after
reviewing the captured read-only fixture and this source:

```powershell
adb -s 9125299103B7 shell am instrument -w com.bdkaudio.codecprobe/com.bdkaudio.codecprobe.LHDCPreferenceCheck
```

This starts one finite check, not a general codec setter. It refuses to write
unless exactly one connected device is named `BDK SPEAKER` and its active tuple
matches LHDC V5 type 15, priority 1000000, rate mask 32 (192 kHz), depth mask 2
(24-bit), stereo mask 2, quality `0x8008`, `cs2=0`, `cs3=0x5C000000`, `cs4=0`,
extended codec ID 889535231 and name `LHDC V5`. It captures every tuple field
before mutation, constructs and checks a copy with only quality `0x8007`
(900 kbps nominal target), rechecks identity and the entire tuple, then invokes
the ordinary `setCodecConfigPreference` once. No access-check exemption is used.

It polls direct `getCodecStatus` at 100 ms intervals for up to 3 seconds, requiring
the requested quality with every other captured field unchanged. In `finally`
it attempts one restoration with the exact captured original config and verifies
the complete original tuple using the same bounded polling. Restoration also
runs after a setter exception/unknown outcome if the original identity and
non-quality fields can still be freshly verified. Unexpected device/format/opaque
changes abort the check and refuse an unsafe restore. A timed-out native call
retains its single-call lease; restoration is never blindly queued behind it.
If that lease does not drain within 3 seconds, restoration is explicitly
unverified/skipped and the original tuple remains in the result. Deadline guards
prevent a delayed preflight from issuing a setter after its stage has ended.

The `lhdc_preference_check` JSON result includes `before`, latest `after`, latest
`restored`, setter-invocation flags, restoration eligibility/outcome, and errors.
Keep failure results. A successful preference readback is **not** measured audio
bitrate; `measuredBitrateKbps` is always null. The check never opens a microphone,
changes audio routing, invokes a private encoder, pairs/connects/disconnects the
speaker, or retries either setter. Closing its profile proxy only releases its
app-side handle. Instrumentation may restart the target app, so reconnect its BLE
controls afterward and remove the separate probe APK after the finite run.

## Explicit LDAC switch and quality check

`com.bdkaudio.codecprobe.LDACPreferenceCheck` is another separate **mutating**
entry point. Include its Java class in the separately signed instrumentation APK;
the read-only `CodecProbe` entry is unchanged. Root may explicitly run it on the
authorized Redmagic after source review:

```powershell
adb -s 9125299103B7 shell am instrument -w com.bdkaudio.codecprobe/com.bdkaudio.codecprobe.LDACPreferenceCheck
```

The check captures the **current** exact LHDC V5 **or LDAC** tuple, including its
raw immutable Android config and every opaque field. It accepts a recognized,
valid V5 quality/rate, including fixed 1000 or Adaptive where permitted, or a
known LDAC default/canonical quality with a supported current format. It does not
assume the user has left the speaker on LHDC or at 192 kHz/1000. It requires one connected
`BDK SPEAKER`, the same target certificate/normal Bluetooth permission, positive
extended identity for the captured codec (plus V5 vendor tags when on LHDC), and a fresh selectable LDAC row
supporting 96 kHz, 32-bit stereo.

If already on LDAC 96 kHz/32-bit/stereo, it skips the initial codec switch and
records `initialCodecSwitchSkipped:true`. Otherwise it makes one normal-client
LDAC 96 kHz/32-bit/stereo request with default `cs1=0`
and zero vendor fields. Direct readback must confirm that format and a known
LDAC default/canonical quality. It then makes exactly one request each for
330 (`1002`), 660 (`1001`), 990 (`1000`), and Adaptive (`1003`). Every setter has
a fresh same-speaker/current-complete-tuple preflight and fresh LDAC selectable
capability check. Each quality write copies every non-quality field from the
preceding confirmed LDAC tuple; each readback must preserve those fields and
match the requested quality. All polling is finite: up to 3 seconds, 100 ms
intervals. The sequence fails fast on unconfirmed or unexpected state, without
blind retries, then enters restoration.

After **any** possibly committed mutation, `finally` attempts one restoration of
the captured original raw config (including an initial LDAC Adaptive state) when the real native lease drains and
fresh same-speaker/permission checks show a stable recognized experiment state.
It verifies the entire original tuple. It refuses stale/overlapping setters and
reports restoration unknown/skipped if the native call stays pending, identity or
permission cannot be rechecked, or the current codec is outside the recognized
experiment states. Stage guards atomically close against setter commitment;
native calls never hold those tiny locks. Closing the profile proxy releases the
handle and does not disconnect audio.

The `ldac_preference_check` result reports `readOnly:false`, exact `before`, each
stage's request/readback/commit/unknown outcome, exact `restored`, restoration
verification and errors. Keep failures and incomplete restoration evidence.
The reported numbers are **nominal requested targets**, not measured encoder or
transmission bitrate; `measuredBitrateKbps` remains null. No route, connection,
microphone, private encoder or hidden-API exemption is used. This is tooling only,
not production APK code. Instrumentation may restart the BDK app; reconnect its
BLE controls afterward and remove the probe package when research is complete.
