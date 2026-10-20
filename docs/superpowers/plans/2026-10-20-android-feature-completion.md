# Android feature completion and Redmagic delivery

Continue the approved Flutter design and the user's request to finish codec and
remaining Android features, improve beat detection, and install the functional
app on Redmagic 9125299103B7. This is an internal Android delivery. The broader
universal port still needs platform and distribution validation.

## Boundaries

- Work in the existing separate Flutter repository and feature branch. Preserve
  unrelated Linux decoder/runner work and the original Android installation.
- No ESP32 source access, firmware changes/builds, serial operations, or flashing.
- Test normal app codec requests on the selected BDK audio device, then restore
  the starting negotiated configuration. No hidden API exemptions or root.
- Exercise sound upload and OTA with fake transports; do not transfer to hardware.
- Install by data-preserving upgrade on the identity-checked Redmagic only.

## Implementation

1. Codec controller/screen: bounded A2DP initialization and delayed same-device
   readback retries, truthful timeout/refusal handling, persistent draft controls,
   recovery actions, and a separate negotiated-config card with observation
   source/age. Show codec, sample rate, depth, channels, recognized quality and
   nominal LDAC target. Never label an estimate as measured Bluetooth bitrate.
2. Meter processor: timestamp-aware positive onset novelty on the existing three
   bass meters, adaptive noise threshold, hysteresis and gap rebasing. Preserve
   duplicate/out-of-order caching, source mapping and freshness. Compare against
   a frozen old detector on development and held-out synthetic fixtures; report
   this separately from listening/live music evidence.
3. Android parity: preserve actionable setup errors; distinguish completed sound
   transfer from confirmed slot presence using bounded status readback and
   epoch-scoped receipts. Preserve uncertain replacement confirmations.
4. Brightness: dispatch command 0x07 when only brightness differs from accepted
   LED state. Choose at queue dispatch so accepted/refused prior effect changes
   retain correct semantics. Full effect changes keep 0x05.
5. Delivery: normal main entrypoint with preview-only false, fresh analysis/full
   Flutter tests/native checks, Android ARM64 release build, package/signature
   receipt, identity-checked upgrade, native UI and reversible codec verification.
   Document exact platform, OS/API limitations, deferred checks and installed hash.

## Ownership and verification

Root owns protocol/session brightness, shared app integration, SDK serialization,
ADB, packaging, documentation and final review. Codec, onset and Android parity
agents own disjoint feature/test files. Regression tests ran RED before product
changes; artifacts/android-ship-20261020 contains the assertion output. Run all
Flutter commands sequentially to avoid shared native-assets copy collisions.

Completion requires fresh evidence, not agent reports. A submitted codec request
is confirmed only by fresh same-device negotiated readback. ACKs prove speaker
acceptance, not durable persistence or acoustics. Public signing, Apple/Linux and
store packaging remain separate release gates.

## Accepted follow-ups during implementation

- Show explicit LDAC bitrate/quality targets, including selection from Android's
  source-defined default code zero. Preserve unknown vendor-field refusal and
  exact post-request quality readback. Fixed targets remain nominal.
- Connect immediately after finding one service-advertising device whose identity
  matches the verified A2DP speaker; retain five seconds for empty-search help.
  Move bounded last-speaker preference saving off the control-readiness path.
- Add a compact, tappable current-config strip shared by Sound/Light/Speaker,
  with read-only foreground observation, identity/freshness guards and no invented
  bitrate. Pause its polling while the full codec screen is open.
- Reveal connected controls with a 280 ms fade and eight-pixel rise. Readiness
  has no extra dwell; reduced motion shows controls immediately. Ordinary meter
  updates and tab selection must not replay the connection animation.
- Research the A2DP/vendor bitrate path against Android and official Savitech
  sources. Enable LHDC V5 requests only after this phone's raw codec name, command
  tag and V5 feature tag match that contract. Preserve opaque fields, apply
  sample-rate/lossless limits and confirm exact same-device readback. Keep local
  drafts editable after observation expiry; Apply still requires fresh evidence.
- Use explicit Android foreground low-latency scan mode and zero report delay.
  Retain lifecycle stop and identity gates; do not claim a fixed physical latency.
