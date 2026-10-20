# Continuous discovery and connection help

**Goal:** Keep the foreground finding screen checking until the matching speaker
is found, with refined motion and explicit Bluetooth connection help.

**Design:** This user revision supersedes the five-second empty-state stop in
the brand/discovery spec. Five seconds now reveals inline “Connected to your
speaker?” help while checking continues. Only tapping Connect speaker opens OS
Bluetooth settings. Preserve the existing audio-first and exact-device gates.
Replace the radar wedge with slow, soft original light motion; use one status
surface, with Cancel and an explicit Demo exit. Reduced motion stays static.

**Constraints:** App only; emulator-5580 only; PreviewOnly; no phone or ESP32
operations. Stop discovery on background, cancellation, permission/error,
connection or disposal. Preserve Linux WIP. No new dependency or global setting.

- [x] Root: write/observe RED for ongoing audio checking and BLE scan beyond
  five/15 seconds, later audio/matched peer, unrelated peer, cancellation,
  background and explicit-only settings. Keep legacy session.scan bounded by
  default; add continuous:true only for controller-owned discovery.
- [x] UI owner: test then implement optional continuousDiscovery presentation,
  inline connection help with active settings action during scanning, quiet
  replacement motion, Demo/Cancel and 280px/2x reduced-motion coverage. Root
  binds continuousDiscovery to setup.autoDiscoverEnabled.
- [x] Root: review, full suite/analyzer/export checks; build/install normal-main
  PreviewOnly0.6.4 in owned emulator; record searching beyond prior deadline,
  inline help and explicit settings redirect/foreground return. Document actual
  evidence, retain physical-radio limits and commit only this scope.
