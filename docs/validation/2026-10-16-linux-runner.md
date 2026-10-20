# Local Linux runner, 2026-10-16

Status: **0.5.6+14 passed the native Linux preview build, actual setup/Demo/Light/gallery GUI checks, native WAV/LED FFI checks, complete bundle export verification, and a separate actual app Sound-import/file-picker/isolate/local-draft check.** The Light-theme defect reproduced in 0.5.5 is corrected and confirmed in the real Linux GUI. Both baseline failures and repaired evidence are preserved. Scope remains this Ubuntu 24.04.5 x86_64 software-rendered guest, one owned PCM16 WAV, and no playback or physical device validation.

## Scope and isolation

This runner is a local QEMU guest, not a cloud job. Its writable disk, NoCloud seed, temporary SSH key, known-hosts file, console logs and receipts are confined to ignored `artifacts/linux-runner/`. No host directory share, USB, serial-device passthrough, Bluetooth adapter, audio device, ADB or physical target is attached. The virtual serial console writes a workspace log file only.

The runner uses QEMU 11.1.0, TCG software emulation, two virtual CPUs, 4096 MiB RAM, and a 48 GiB sparse QCOW2 overlay. Networking uses QEMU user-mode NAT for guest toolchain downloads. Only `127.0.0.1:33422` (SSH) and `127.0.0.1:33423` (QMP) are forwarded/listening; both ports were checked free before each launch. No host OS, virtualization setting, firewall or service was changed. No existing app, miner or VM was stopped.

Ubuntu image: [official pinned release-20261008](https://cloud-images.ubuntu.com/minimal/releases/noble/release-20261008/ubuntu-24.04-minimal-cloudimg-amd64.img), 264503296 bytes. Its SHA-256 is `2f119f50bf29fe40e73b69ae2a736e8210d8146796f036e0324315b6b3a777df`, matching the filename entry in the [official SHA256SUMS](https://cloud-images.ubuntu.com/minimal/releases/noble/release-20261008/SHA256SUMS), preserved locally. This verifies consistency with the official HTTPS manifest; detached-signature verification was not performed.

The read-only base image is `artifacts/linux-runner/ubuntu-24.04-minimal-cloudimg-amd64.img`. The current overlay is `runner-seed-virtio.qcow2` with that relative backing filename. The original failed overlay `runner.qcow2` is preserved. The generated `seed.iso` is labeled CIDATA and contains user-data and meta-data as specified in the [official NoCloud documentation](https://docs.cloud-init.io/en/latest/reference/datasources/nocloud.html). A new, guest-only Ed25519 key authenticates the `runner` account, with guest-only passwordless sudo and password/root SSH disabled. Python dependency `pycdlib==1.14.0` was installed into the ignored runner directory only to generate the ISO.

## Actual bootstrap observations

- Initial PID 32180 exited immediately: `The -accel and "-machine accel=" options are incompatible`. The duplicate accelerator selection was removed.
- UEFI PID 36492 listened on the expected localhost ports but showed an uninitialized display and no virtual serial output under BelowNormal priority. The cause has not been established. Its argument receipt and screenshot were preserved; only that process was terminated through its QMP port.
- SeaBIOS PID 30568 reached GRUB, then Linux kernel `6.8.0-146-generic`, mounted the root filesystem and started `/sbin/init`. BelowNormal priority accumulated very little CPU on the saturated host. Changing only this runner process to Normal priority allowed observable boot progress. Whether priority alone explains the UEFI symptom remains unknown.
- PID 30568 reached login but had neither a visible seed CD-ROM nor cloud-init startup in the captured kernel/systemd log. The seed used the default AHCI CD-ROM bus, which was not available during the image's initrdless early boot. Only this process was stopped through QMP; its console/arguments and overlay were preserved.
- Current PID **20036**, Normal priority, uses SeaBIOS and the seed as a read-only virtio block device, matching the official NoCloud example. Kernel output identifies `/dev/vdb`; cloud-init reports `DataSourceNoCloud [seed=/dev/vdb]`, status `done`, and empty errors/recoverable-errors.
- Guest SSH succeeded as `runner`; `uname -a` identifies `bdk-linux-runner` and `6.8.0-146-generic x86_64`. `nproc` reports 2; memory totals 3914 MiB; root filesystem is 46 GiB with 45 GiB free. The guest address is `10.0.2.15` behind QEMU user-mode NAT. Guest sudo works without a password. The guest-only SSH host fingerprint is `SHA256:O+JxznVXdMo3nl3q9rfMfef7buyEaqJ9DQtOv+GyYoE`.
- Fresh listener evidence confirms both `127.0.0.1:33422` and `127.0.0.1:33423` are owned by PID 20036. Guest details and cloud-init JSON are saved in `guest-isolation.txt`; listeners are in `listener-receipt.json`.

Exact current QEMU arguments are preserved in `artifacts/linux-runner/qemu-arguments.json`; Windows process command line is in `process-receipt.json`; PID is in `qemu.pid`. Launches used `Start-Process -WindowStyle Hidden` with the runner artifact directory as working directory. There is no host runner automation script.

## Next gate

The guest SSH/cloud-init/capacity/listener gate has passed. `tools/linux_runner/bootstrap-guest.sh` passed guest `bash -n` and rejected execution as guest root before apt (its account guard). It was copied into the guest, then started there as guest PID **948** with `nohup timeout 1800 nice -n 5 bash ~/bootstrap-guest.sh > ~/bootstrap.log 2>&1`. It installs GTK/clang/CMake/Ninja/pkg-config/GStreamer and Flutter pinned to `ad70ec4617166f1c38e5d2bfd388af71fda14f06` (the requested Flutter 3.44.4/Dart 3.12.2 SDK). `git ls-remote https://github.com/flutter/flutter.git refs/tags/3.44.4` independently confirmed that tag resolves to the requested revision; the result is saved in `flutter-tag-receipt.txt`. Check the installed SDK version rather than assume it. The 30-minute timeout bounds this guest-only installation; host QEMU is capped by its two emulated CPUs and 4 GiB memory.

Guest PID **1855** ran a second bounded prerequisites command: `timeout 1200 sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=900 install -y --no-install-recommends python3-gi desktop-file-utils`, with output in `~/launcher-prereqs.log`. It waited on the main apt transaction rather than interfering with it. These packages support the parent task's actual GLib desktop-launch regression check. Installation is now verified: `desktop-file-validate 0.27`, `desktop-file-utils 0.27-2build1`, and `python3-gi 3.48.2-1`. The parent independently confirmed `gi` and `Gio.DesktopAppInfo` import. The current tracked bootstrap includes both prerequisites for subsequent runs.

The main native package transaction and SDK bootstrap/precache completed; the guest SDK checkout matches the requested commit. The Linux x64 Dart SDK download completed (222 MiB). The original running bootstrap fetched the revision directly; the official `3.44.4` tag was subsequently fetched and checked against that same revision to provide SDK version metadata. Installed native package versions are saved in `guest-prerequisites.txt`: clang 18, CMake 3.28.3, Ninja 1.11.1, GTK 3.24.41 and GStreamer 1.24.2.

## Finalized source and native build gate

After the parent finalized its changes and explicitly authorized the transfer, only `app-source-055.tar.gz` and `app-source-055-manifest.json` were copied as application inputs. The archive SHA-256 is `3a53662d313def14f4e722d41ac395220889012dd2d075b1138f6ba536d049b4`. Extraction required a fresh `/home/runner/bdk-audio-055`, archive path equality with the 307-file allowlist, no links or special archive entries, and safe relative paths excluding `.git`, artifacts, build outputs and caches. Every extracted file's SHA-256 matched the manifest before any `pub get`. The machine-readable receipt is `source-verification.json`.

The final metadata-only snapshot is `app-source-055-final.tar.gz` with SHA-256 `68afde65a044548aec0497b83d63b3192c18460660f30d69bbfd93c2ee363b95`. All 307 files were reverified in fresh `/home/runner/bdk-audio-055-final`; only `.gitattributes` differs from the first snapshot. The final rules preserve audited notice bytes across checkouts. Both receipts are retained; the final build must use the final directory.

The bounded SDK version gate exited successfully: actual Flutter 3.44.4, framework `ad70ec4617166f1c38e5d2bfd388af71fda14f06`, Dart 3.12.2 and engine `a10d8ac38de835021c8d2f920dbf50a920ccc030`, recorded in `flutter-version.json`. Initial Flutter-tool snapshot compilation took several minutes under TCG; CPU/RSS observations showed progress and no error/OOM. Bootstrap completed Linux precaching and doctor. The Linux toolchain passes; driver information remains unavailable without `eglinfo`. Other doctor warnings concern intentional detached SDK channel metadata and absent Android SDK/Chrome in this Linux-only guest.

Guest PID **12120** started the authorized build phase at `2026-10-16T21:23:53Z`: `flutter pub get --enforce-lockfile` followed by `flutter build linux --debug -t lib/main.dart --dart-define=BDK_PREVIEW_ONLY=true --verbose`, inside `/home/runner/bdk-audio-055-final`. A single 1800-second timeout bounded dependency resolution and build. It finished at `2026-10-16T21:29:08Z`, exit **0**, producing `build/linux/x64/debug/bundle/bdk_audio`. Flutter reports Linux CLI duration 251617 ms and native build duration 242.4 s; these are finite TCG guest observations, not physical-host performance claims. Receipts were copied to `artifacts/linux-runner/native-preview-build.{started,finished,exit,log}`. The launch exported `CMAKE_BUILD_PARALLEL_LEVEL=2`, and the VM itself retained two CPUs and 4 GiB RAM. No app source was edited to force a build outcome; all 307 manifest files still match after the native build.

## Native runtime and functional baseline

The actual built bundle was registered through its installed `register-launcher.sh` into an isolated guest `XDG_DATA_HOME`. Its desktop entry passed `desktop-file-validate`, then `Gio.DesktopAppInfo.launch_uris_as_manager` launched the real application. The app was guest PID **13204**, GTK XID **4194307**, title `BDK Audio`, class `com.bdkaudio.bdk_audio`, exact executable `/home/runner/bdk-audio-055-final/build/linux/x64/debug/bundle/bdk_audio`, on isolated Xvfb display `:99` with a fresh session bus. Inputs required that identity and a fresh inspected native screenshot. `Explore Demo` was clicked in the shipped `lib/main.dart` setup flow, followed by the visible Light tab. No Bluetooth-settings, connect, playback, host-setting or physical-device action occurred.

The first visible-window screenshot was black during startup. A subsequent fresh capture showed the full setup UI, followed by the Sound and Light screens. Both early and later captures are preserved. Runtime logs contain missing AT-SPI accessibility-bus warnings and an `atk_socket_embed` assertion; they did not prevent the observed native UI flow. Graphics diagnostics from the same isolated environment report Mesa 25.2.8, **llvmpipe (LLVM 20.1.2)** and **Accelerated: no**. Guest-only `mesa-utils`, `x11-utils` and `xdotool` support those diagnostics and exact-window input; the bootstrap package list now includes them.

- **Decoder functional gate passed:** the actual bundled `libbdk_audio_decoder.so` (SHA-256 `7affdb9546b3256c1b06ed39b112447cecad99df0dab6ee8b6ef5df277a16a03`) probed an owned PCM16 stereo WAV at 16000 Hz, two channels, 4096 source frames. It decoded a 512-frame mono excerpt starting at output frame 123, returned success/written=512, sample range -12000..12000, with **zero absolute sample error** against the identical-channel owned fixture. No audio was played. This validates that WAV/PCM path only, not all codecs or audio playback.
- **LED FFI gate passed:** the actual bundled `libbdk_led_engine.so` (SHA-256 `39c461e990f3744b8e3ea4920b7aef2dee2edfec216ba06ae80af3399346942e`) rendered 32 Rainbow Wave demo frames, each 1024 RGBA bytes; all 32 hashes differ, RGB values are nonzero and every alpha byte is 255.
- **Actual GUI native LED mapping confirmed:** `/proc/13204/maps` identifies that same bundled LED library after the Light screen opens. The default factory is the shipped native renderer; no renderer or loader override was supplied.
- **Light appearance failed:** Spectrum Bars' optical panel is gray/white. Two native captures 3.191 s apart have identical preview-region hashes and **0/140800 changed pixels**, preserved in `native-gui-animation.json` and `linux-light-animation-a.png` / `linux-light-animation-b.png`.
- **Dark comparison passed:** changing only the app's Appearance selection to Dark restores colored Spectrum Bars. The same PID/XID and preview region have **43475/140800 changed pixels** across 3.249 s, preserved in `native-gui-dark-animation.json` and `linux-light-dark-animation-a.png` / `linux-light-dark-animation-b.png`. This isolates Light-theme additive compositing over a near-white background. Dark is diagnostic evidence, not a repair for Light appearance.

The owned GUI session was intentionally ended through its controller's completion file. The controller verified its child identity, sent SIGTERM only to PID 13204, and reaped it; teardown records wait status 15 as intentional cleanup. Its DBus/Xvfb jobs exited. QEMU PID 20036 remains available for the parent's reviewed fix and repeat validation.

## Bundle ABI baseline

All five bundled ELF files resolve their runtime dependencies in this Ubuntu 24.04.5 guest; `ldd` reports no missing libraries. Imported symbol requirements were read with `readelf --version-info`, not inferred from compiler versions:

| Bundled ELF | Highest numeric GLIBC | Highest numeric GLIBCXX | Highest numeric CXXABI |
| --- | --- | --- | --- |
| `bdk_audio` | 2.34 | 3.4 | 1.3 |
| `libaudioplayers_linux_plugin.so` | 2.14 | 3.4.29 | 1.3.13 |
| `libbdk_audio_decoder.so` | 2.34 | 3.4.29 | 1.3 |
| `libbdk_led_engine.so` | **2.38** | 3.4 | 1.3 |
| `libflutter_linux_gtk.so` | 2.18 | none | none |

The bundle therefore includes a **GLIBC 2.38** requirement and **GLIBCXX 3.4.29** requirement, plus GTK/GStreamer and other dynamically resolved system libraries. The full per-ELF requirements and actual resolved paths are in `linux-bundle-elf-abi.json` and `linux-bundle-ldd.txt` inside the preserved QA artifacts. These are necessary ABI constraints, not an all-distribution compatibility guarantee. Only this Ubuntu guest was exercised.

Native Linux compilation/runtime under Xvfb is evidence for the guest Linux ABI and software rendering only; physical BLE, physical audio, bare-metal GPU and other Linux distributions remain outside this validation.

## Preserved baseline export and reviewed 0.5.6 rebuild

The complete baseline bundle is preserved as `artifacts/linux-runner/bdk-audio-0.5.5-linux-x64-debug-preview-baseline.tar.gz`, **39192001 bytes**, SHA-256 `dacc9416de867fdcaff7fe4fdac984c263439702a965ce435d40196c7a9dfe6f`. Its archive was transferred locally and independently checked against the per-entry manifest: **42 entries / 28 regular files / zero symlinks**, matching contents, modes and paths. Both `bdk_audio` and `register-launcher.sh` retain mode `0755`. The `baseline` label deliberately retains the known Light-theme defect; this is a reproduction artifact, not the repaired deliverable. The QA archive, manifests, dependency/symbol receipts and failed/passed screenshots are preserved alongside it.

The parent supplied reviewed version **0.5.6+14** as `app-source-056.tar.gz`, SHA-256 `0fcb10a86eb935986326008e9cec64cc5f66541a54734e84f3b071d83714ed50`. All **308** files were checked in fresh `/home/runner/bdk-audio-056` before dependency/build operations, with the same safe path/type/exact-manifest checks. Its manifest differs from the prior snapshot only in `lib/features/light/light_screen.dart`, `pubspec.yaml` and new `test/ui/light_theme_color_test.dart`; native algorithm sources are unchanged. The receipt is `source-056-verification.json`.

Guest PID **14607** completed the separate bounded 0.5.6 build with the same locked dependency resolution and `lib/main.dart` preview-only target. Its records are `native-preview-056-build.*`: start `2026-10-16T21:43:08Z`, finish `2026-10-16T21:46:41Z`, exit **0**. Flutter reports 202532 ms for its Linux CLI / 196.5 s for the native build. The SDK/pub cache was reused; the app source directory was fresh. No older evidence was overwritten.

## Repaired 0.5.6 native GUI and functional checks

The installed bundle launcher/desktop entry again passed registration and native GLib launch. A fresh QA profile/session launched guest app PID **15399**, verified XID **4194307**, title/class/executable identity, on isolated Xvfb `:99`. The actual shipped setup flow was used: **Explore Demo**, Speaker → Appearance → explicitly **Light**, then Light preview and **Choose an effect**. Each action followed a fresh inspected native screenshot and exact PID/XID/executable checks. The packaged version asset identifies version **0.5.6**, build **14**.

- The Light-theme optical panel now shows colored Spectrum Bars. A first short 3.259 s pair was identical and remains preserved in `native-056-gui-light-animation.json`. A subsequent bounded observation, with no source/lifecycle changes, captured **four distinct native preview hashes** at 0, 7.515, 20.052 and 32.642 s. Relative to the first frame, **16866 / 16986 / 38878** of the 140800 preview pixels changed. All 140800 sampled pixels in the short-pair color check are chromatic. `native-056-gui-light-animation-extended.json` is the passing animation observation; neither sample is a physical FPS claim.
- The actual app maps the newly built bundled `libbdk_led_engine.so`. No LED renderer factory, library-loader path or alternate app entrypoint override was supplied. Fresh images `linux-056-light-first-fixed.png`, `linux-056-light-before-gallery.png` and `light-fixed-extended-*.png` show the corrected optical panel surrounded by the selected Light appearance.
- Gallery image `linux-056-gallery-light-loaded.png` shows readable white labels and cyan selected/check state on dark optical tiles. Six fully visible native thumbnails were inspected: Spectrum Bars, Beat Pulse, Ripple, Fire, Plasma and Matrix Rain. Their artwork samples contain respectively **18667 / 20630 / 10149 / 7275 / 17619 / 141** chromatic pixels out of 23760 each. This checks the visible gallery viewport, not every effect or off-screen tile. The receipt is `native-056-gallery-light-evidence.json`.
- The rebuilt decoder `.so` (SHA-256 `ec867de7f2b619cce979d631468d3ba8f13cb48d36098ebaa4eff6bc9cd569c4`) again probed the 16000 Hz / stereo / 4096-frame owned PCM16 fixture and decoded the requested 512 mono frames at start 123 with **zero sample error**. No audio was played.
- The rebuilt LED `.so` (SHA-256 `09acc424da61f76536c2c30b9a909d848648ec12240c3f5405004848d3933fcb`) again produced **32 unique / 1024-byte / opaque-alpha** Rainbow Wave frames. First/last frame hashes exactly match the baseline. These functional results are in `native-056-ffi-qa.json`.

The owned 0.5.6 GUI session ended intentionally after those checks. Its controller reaped only app PID 15399 via SIGTERM, with wait status 15 recorded as cleanup; its Xvfb/DBus jobs exited. At that checkpoint app Sound selection/isolate import had not been exercised; the separately authorized follow-up below now covers that path. Playback, upload, delete, OTA and BLE/device controls were not exercised.

## Final 0.5.6 exported checkpoint

The complete bundle is `artifacts/linux-runner/bdk-audio-0.5.6-linux-x64-debug-preview.tar.gz`, **39192054 bytes**, SHA-256:

```text
73a8f337fbc3f6bca87af97046b06c97fb8e51e20e05ab3d73cb1048fe5854a2
```

An adjacent `.sha256` file supports `sha256sum -c`. Independent local archive verification matched **all 42 entries / 28 regular files / zero symlinks**, contents, sizes and modes against `linux-bundle-056-manifest.json`. Both executable and installed launcher retain `0755`; no symlinks were lost. Receipt: `linux-bundle-056-archive-verification.json`.

Fresh post-GUI/export hashing found **all 308 approved source files unchanged**, in `source-056-after-gui-export.json`. The new bundle's five ELF files again resolve every runtime dependency in this guest. Its fresh `linux-bundle-056-elf-abi.json` / `linux-bundle-056-ldd.txt` confirm the same maxima as the baseline: **GLIBC 2.38, GLIBCXX 3.4.29, CXXABI 1.3.13**, plus dynamically supplied GTK/GStreamer/graphics and other system libraries. This does not establish other-distribution compatibility.

The preserved QA archive is `native-preview-056-qa.tar.gz`; direct JSON summaries, screenshots, source receipts and `native-056-checkpoint-verdict.json` are alongside it in ignored artifacts. QEMU host PID **20036** remains available for parent review/next separate QA; fresh listener evidence still identifies only `127.0.0.1:33422` / `127.0.0.1:33423` owned by that process. There are no active owned GUI jobs. No physical BLE, audio output, bare-metal GPU or host-global configuration was changed or validated.

## Separate native app Sound import, 22:04–22:18 UTC

This follow-up reused the exact exported 0.5.6 bundle; no rebuild, app source change, loader override or injected picker/decoder was used. The initial phase was bounded to approximately 15 minutes. Controller PID **16968** ran the fresh private session, app PID **17010** / XID **4194307** on Xvfb `:99`. Actual inspected UI actions were Explore Demo → Speaker → Speaker sounds → Startup → Choose audio; the real chooser then selected only the owned fixture. Adjust clip was opened only to inspect its existing selection.

**Actual chooser prerequisite:** locked `file_picker 13.1.0` delegates to `file_picker_linux 2.0.0`, package lock SHA-256 `e7db600f50672ce5ebbe422ac0906e0f3d2a476188cc93e7126afee12bf08063`. Its cached primary source calls session-bus `org.freedesktop.portal.Desktop`, `org.freedesktop.portal.FileChooser.OpenFile`; it does not call Zenity. The minimal guest lacked portal service/backend packages. This was reported before guest-only installation of `xdg-desktop-portal 1.18.4-1ubuntu2.24.04.3` and `xdg-desktop-portal-gtk 1.15.1-1build2`. Package output and source/interface evidence are preserved. The bootstrap now includes these actual prerequisites.

A private QA `XDG_CONFIG_HOME` selected GTK according to the [official portal configuration reference](https://flatpak.github.io/xdg-desktop-portal/docs/portals.conf.html), and the private bus received its own display/authentication environment. Initial literal newline escapes in that QA configuration were caught by readback and corrected before picker use; the original is preserved. A precautionary frontend restart was aborted by a strict process-parent guard before any signal was sent. The already-running real FileChooser interface was introspected and worked. Missing PipeWire context and unparented-chooser warnings were logged; neither prevented file selection. No host service or configuration changed.

The real GTK chooser was PID **17040**, XID **6291463**, title `Choose a speaker sound`, executable `/usr/libexec/xdg-desktop-portal-gtk`, resolved through its name on the owned session bus. Each input required this exact identity and a fresh native screenshot. Ctrl+L entered only `/home/runner/native-preview-smoke/ffi/owned-stereo-pcm16-16000.wav`; its existing SHA-256 `5ebf783f2d722cc4c6eff2af500bcf6c54038c9b5d27edc2c9efa5ac925ddc62` was checked before selection. `Select` confirmed that actual native dialog; no synthetic URI response was supplied.

**Actual app result passed:** the UI showed `Local draft`, the owned filename, and `0.3 s · Mono PCM16 · 22.05 kHz · 11.1 KiB`. Its app-written `sound_previews_v1.json` contains Startup slot 0, source metadata **16000 Hz / stereo / 256000 µs**, selection **0–256000 µs**, and **22050 Hz** mono output. The decoded WAV has **5644 frames / 11332 bytes / 0.2559637 s**, SHA-256 `c0cbe15548ecc07e1ca6cefe5a67517e2e15c640c3dae8c9d321e5ce220f9bab`. All 5644 PCM samples exactly match a separate call to the shipped native decoder at that output rate: **maximum absolute error 0**. The actual app process maps the bundled decoder `.so`; its package implements probe/decode workers using `Isolate.run`, so the real picker/file-copy/Dart-isolate/native-loader/draft path was exercised.

The shipped editor exposes a clip-range selector, not a plotted waveform curve. The actual persisted decoded PCM waveform was inspected numerically: range **-11985..11991**, RMS **8459.9379**, positive-zero-crossing frequency **439.9786 Hz**, consistent with the owned 440 Hz fixture. The real decoded WAV and native screenshots are exported; this does not claim an unimplemented GUI waveform plot or audio playback.

Evidence: `native-sound-056-app-import-result.json`, `native-sound-056-source-receipt.json`, `native-sound-056-actual-app-decoded-draft.wav`, `linux-sound-056-chooser-owned-path-before-select.png`, `linux-sound-056-import-after-picker.png`, and `linux-sound-056-decoded-waveform.png`. Complete QA archive `native-sound-056-qa.tar.gz` has SHA-256 **`62be681856a5ec3835a32b492f8afeb8aadfb5ff8673e21058d29d00e99fab09`**. It preserves setup errors/warnings and every actual input/capture receipt without overwriting prior checkpoints.

Parent verification independently checked that archive hash, parsed the exported
WAV/header/PCM statistics, and matched it byte-for-byte to the app-persisted
base64 draft. A separate parent native decoder call used identity-checked source
fixture/library hashes and again matched all 5,644 output samples with maximum
error 0. These checks are in `root-native-sound-056-{verification,persisted-verification,reference}.json`.

Owned app/controller/bus/portal/chooser PIDs **17010 / 16968 / 16970 / 17018 / 17040**, Xvfb and associated dconf jobs all exited after intentional owned-session cleanup. The app was reaped with SIGTERM wait status 15, not a crash. QEMU PID **20036** remains for the parent's next task. All **308** source files, the app executable SHA-256 **`66d84f6bbe30a44113f228f9629362e23f4a71b0aff89fe895df59dbb9e5bbd4`**, original fixture and exported bundle SHA remain unchanged. No Play/preview-audio, upload, delete, OTA or BLE/device controls were used.

Read-only future-tool inventory found `/usr/bin/mount`, `/usr/sbin/chroot`, `/usr/bin/unshare` and `/usr/bin/tar`; `debootstrap` was absent. No Jammy/ARM setup, mount or chroot job was started by this task.
