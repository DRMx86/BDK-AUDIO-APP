# BDK Audio guide

The Android 0.7.2 internal build enables connected speaker controls, sound
transfers, audio preferences and local-file firmware updates. Demo keeps speaker
changes disabled. Builds explicitly made with `BDK_PREVIEW_ONLY=true` also disable
those changes. Platform and device restrictions still apply.

## Getting started

Choose **Explore Demo** without a speaker. Demo light effects use sample input
and are labeled as a preview.

For a real connection, first connect the speaker for Bluetooth audio in your
device's settings. The app then checks that audio connection before looking for
its BLE controls. A paired name alone does not establish the control connection.
On platforms using manual audio confirmation, the setup screen offers
**I connected Bluetooth audio**. Use it after your device's settings
show the speaker connected for audio. The app labels this as your confirmation;
it still has to find and synchronize the speaker's controls.
If verification fails, follow the displayed connection message. Platform and
driver limitations are recorded in the [platform matrix](platform-release-matrix.md).

The full connection flow remembers your last successfully connected speaker.
Where the platform can verify audio identity, it can find and reconnect that
speaker's controls automatically. Cancel or Disconnect stops this until you
choose Search or Connect again. After repeated failures, choose Search to retry.
If Bluetooth cannot confirm a previous disconnect, choose the speaker manually.
Automatic connections are available in the normal build. Preview-only builds
keep them disabled.

## Sound

**Choose preset** offers familiar starting points. Each card illustrates its
sound shape; **Your sound** shows the current settings. **All presets** opens the
full built-in collection.

**Equalizer** adjusts Bass, Mid and Treble. Drag a pillar, use its plus/minus
buttons, use keyboard arrows, or use a screen reader's adjustment actions. Level
0 is neutral; levels run from −12 to +12. These are control levels, not measured
loudness in decibels. **Reset** returns to neutral.

**Save preset** names the current sound. In **Saved presets**, the three-dot menu
can rename it, replace its saved settings with the current sound, or delete it.
Deleting a saved entry keeps the current sound. **Import presets** previews a
compatible Android export before you add it to the library. Importing does not
automatically apply it. [Import instructions](migration/presets.md).

**Sound options** reflects the speaker's actual controls. Full-range changes the
crossover output mode; the equalizer still applies. Output swapping exchanges
the low/high outputs in split mode. Bass boost is a separate setting.

## Light

The large card previews the selected effect with diffused light. **Choose an
effect** opens the named gallery. **Ambient** has its own color, brightness and
movement controls. Both Ambient selection paths reach the same settings.

**Lights on** remembers the last brightness when switched off. **Off** in the
gallery also turns lights down to zero. Turning them back on restores the last effect
used in this app session, or Spectrum on a fresh session; colors are retained.

The small **Preview** pause/play control stops only the app animation. It does
not pause music or change the physical speaker's lights.

With a synchronized speaker, the app uses received audio levels for its reactive
preview. Meter values run from 0 to 100 percent, with 0 at the baseline. They do
not measure room loudness. Missing or stale levels are shown as waiting/stale;
they never become unlabeled demo input. The preview uses the source effects, but
the limited meter data cannot reconstruct every physical frame or random state.

## Speaker

**Audio quality** separates **Current connection** from the preference you edit.
The current card shows Android's observed codec, Bluetooth sample rate, bit depth
and channels, with its observation source and freshness. Refresh an old reading
before relying on it. These describe the Bluetooth connection, not the original
music file or measured acoustic output.

A compact current-config strip stays above Sound, Light and Speaker. Tap it for
full Audio quality details. It refreshes while the app is in use, pauses in the
background and marks old readings as stale instead of displaying them as live.

Available codec, rate, depth and channel choices depend on the device and
connection. Android may ask for normal companion-device consent, and some OS
versions still restrict codec access afterward. Apply first checks capabilities,
then waits for matching negotiated readback; a submitted request alone is not
confirmation. LDAC quality may include a **Nominal target**, separate from actual
transmitted bitrate. The app says when Android does not report Bluetooth bitrate.
Unavailable controls remain device-managed; **Open Bluetooth settings** is the
recovery path when appropriate.

For a recognized LDAC connection, **Advanced preferences → Bitrate / quality**
offers 990/660/330 kbps nominal targets at 48/96 kHz, or 909/606/303 at
44.1/88.2 kHz, plus Adaptive. Android's default LDAC mode can also choose an
explicit target. The choice remains a draft until Apply and matching readback.
Unknown vendor quality fields are not rewritten.

For an identified **LHDC V5** connection, the same chooser offers requested
nominal targets appropriate to the sample rate, plus Adaptive. At 96/192 kHz,
fixed requests range from 256 to 1000 kbps; at 44.1/48 kHz, from 64 to 900 kbps.
The peer can impose a narrower range. Lossless mode permits Adaptive only.
Chooser and header values use short labels such as **256 kbps**, **900 kbps**,
**1000 kbps** and **Adaptive**. The detail explanation identifies these as
configured targets rather than measured transmitted bitrate.
Changing sample rate adjusts an incompatible local target visibly before Apply.
The app confirms only the exact requested result; a clamped target is shown as
the current reading rather than successful confirmation of a different request.

Draft editing remains available when a reading ages. Apply still obtains fresh
same-device capabilities before writing and checks the negotiated result. The
current-reading card and summary never substitute a draft for a live observation.

**Speaker sounds** lets you choose local audio, select an excerpt and listen to
the prepared file. A saved local preview is separate from a speaker upload.
Connected uploads wait for the speaker's COMPLETE reply, then separately request
slot presence. Missing presence readback leaves an explicit warning and does not
automatically repeat a replacement. Replacing a previously completed upload
still asks for confirmation when its presence is uncertain.

**Firmware update** inspects a local file and presents a separate explicit
installation action in connected normal builds. File checks do not authenticate
a publisher or establish compatibility with a physical board. Hardware update
delivery has not been tested for the 0.7.0 checkpoint. No firmware update is needed
to use the app. Demo and preview-only builds disable installation.

**Appearance** offers system, dark and light themes. Larger system text and
reduced-motion preferences are respected. Native spoken screen-reader behavior
still needs platform testing; widget semantics checks alone do not prove it.

**App info** shows the installed app version and build, with the original
creator credit. A missing version is shown as unavailable.
**Licenses and notices** opens the bundled font, package and native component
notices, including when version information is unavailable.
