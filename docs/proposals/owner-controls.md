# Owner controls and guest playback

Proposal only, reviewed on 2026-10-24. This feature is not implemented.

[Firmware issue #15](https://github.com/WillyBilly06/ESP32-A2DP-SINK-WITH-CODECS-UPDATED/issues/15)
requests protection against other users changing a chosen sound profile while
still allowing normal Bluetooth music playback.

## Intended experience

- Guest playback continues through the normal Bluetooth audio connection.
- An owner can lock speaker settings separately from audio playback.
- Locked controls remain understandable and read-only, with one clear Unlock
  action instead of a password prompt on every screen.
- Access settings belong under Speaker, keeping Sound and Light focused.
- Recovery and owner-device replacement need a deliberate physical confirmation
  path on the speaker, so a lost phone does not permanently lock out its owner.

## Two different protections

A local app PIN or biometric prompt can protect the controls on a shared phone.
It cannot enforce ownership across other phones or independently written
clients. That distinction must be explicit in the UI and documentation.

Speaker-wide protection requires firmware authorization of settings changes,
with a securely established owner identity, protected credential storage,
revocation/recovery and appropriate pairing/link security. Existing connection
generation identifiers used for queued work are not proof of owner identity.
Bluetooth audio pairing alone should not silently grant permanent administrative
rights to every guest audio source.

The proposed protected settings include sound profiles/EQ, output controls,
lights, rename, sound uploads/deletions and firmware updates. Exact policy and
recovery behavior require agreement before implementation. Audio codec
preferences are phone-local OS operations and need a separate policy decision.

## Current boundary

No PIN UI, credentials, command authorization or firmware changes were added in
this review. Firmware implementation remains outside the app-only change scope.
An app-only convenience lock must not be shipped under a claim that the speaker
is protected against changes from other phones.
