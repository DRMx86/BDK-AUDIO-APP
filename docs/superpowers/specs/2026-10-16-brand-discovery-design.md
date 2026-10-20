# BDK brand reveal and discovery design

The user rejected the 0.6.0 static B intro and text-heavy setup. They want an
animated zoom into the B letter that transitions to a proper device-finding
screen, with a visible search phase before results, music-related identity and
depth/shadows on cards. This supersedes the prior 750 ms static intro and idle
two-step page presentation. The existing audio-first hardware gate remains.

JBL One 2.8.4 was inspected on the actual Redmagic at the user's request. Its
observed launch uses a centered brand, and its PartyTogether discovery view uses
a full-page radar with one large lower status card. The user completed JBL's
first-run legal/privacy choices. A subsequent permission gate limits further
reference inspection; no JBL artwork or code is copied into BDK.

## Product sequence

1. Android's matching solid starting surface hands off to a real Flutter brand animation.
   Keep the B recognizable, add a clear musical-note cue, then zoom the vector
   letter forward as the wordmark fades and the actual discovery page is revealed.
   The latest user timing requires a two-second B hold and a 700 ms zoom reveal.
   Start the hold after the engine rasterizes its first frame, so engine startup
   cannot consume visible logo time. Application loading runs in parallel.
   Slow initialization and real errors stay truthful; reduced motion uses a short
   static brand and direct transition. A running app resume does not replay splash.
2. The initial app surface is a complete discovery page, rather than a compact
   dialog or a form with multiple instruction boxes. Use an airy header, animated
   radar/speaker illustration and one large lower status/action surface with
   subtle gradient, edge highlight and cast shadow. At narrow/large text sizes,
   scroll normally instead of clipping. At desktop widths, retain intentional
   centered or two-column composition.
3. Audio checking, actual BLE discovery, connecting, permission guidance, matched
   results and no-results are distinct truthful states in the same full-screen
   flow. A missing speaker stays in a full-page recovery state with retry and
   Bluetooth settings; it does not report success or appear as a snackbar.
4. Existing Android OS audio identity is required before BLE discovery. A new
   read-only discovery option is independent from automatic connection. In the
   installed PreviewOnly app it starts discovery, but never automatically connects
   or sends speaker settings. Keep actual scanning alive for a five-second window
   before presenting an already-found candidate. Search again uses that same
   five-second window. No-results requires the actual
   scan deadline, error, or completed repeated OS audio check. Stop/cancel,
   background, replaced requests and stale callbacks cannot revive old searches.
5. Result selection and a synchronized Ready state still require the existing
   exact identity/service/status gates. Explicit Demo remains available with a
   visible Pair action; returning to Pair re-enters discovery.
6. Reuse a restrained card shadow and subtle border across Sound, Light, Speaker
   and focused option cards. Preserve LED source geometry/diffusion and actual
   controls; this is a presentation pass rather than a protocol change.

## Implementation decisions

- The user also requested replacing Android's default launch splash. API 31+
  uses the native SplashScreen exit listener to remove the starting surface at
  Flutter's first frame, with a transparent platform icon and matching solid
  background, so the custom B scene is the only visible logo sequence. Legacy
  launch drawables also contain only the matching background. Android's starting
  window still exists while the engine initializes; its launcher-icon flash is
  removed. See the [official SplashScreen API guidance](https://developer.android.com/develop/ui/views/launch/splash-screen).

- Preserve `BdkStartupApp(loadApplication: ...)`; mount the ready application only
  during the reveal, so discovery is not invisibly consumed during a long intro.
- Brand owner adds `BdkBrandMark` as a vector widget and updates the SVG/icon
  exports. A musical note replaces/extends the small signal accent; the B remains
  the primary zoom subject, as explicitly requested by the user.
- `SpeakerPairingScreen` retains its callback/data contract and adds optional
  `searching` and `checkingAudio` booleans, both default false. `busy` continues
  to disable duplicate actions. Search remains the finding surface even when
  candidates arrive before the real scan completes.
- Root provides `bdkSurfaceDecoration(BuildContext context, {double radius = 24,
  Color? color, bool emphasis = false})` in `lib/widgets/surface_decoration.dart`.
  It is a reusable decoration, not a modal or a new navigation layer.
- `SpeakerSetupController` adds `autoDiscoverEnabled = false` independently of
  `autoConnectEnabled`. Normal main enables read-only discovery. Existing tests
  and consumers retain prior defaults. Root owns source timing/cancellation.

## Scope and acceptance

The latest user revision keeps the original speaker/rings artwork and changes
only its scanning motion to soft, slow outward light pulses. Automatic foreground
discovery now keeps checking until the matching speaker is found; the five-second
empty window reveals inline “Connected to your speaker?” help while discovery
continues. A Connect speaker button opens Bluetooth settings only on an explicit
tap. This supersedes the bounded empty-search stop in product sequence item 4.
Verified audio choices remain accessible during polling. Background, cancellation,
permission/error, connection and disposal still stop discovery. Scan errors must
stop native work before a replacement scan starts.

Only the Flutter app changes. Original ESP32 source/builds, serial, flashing,
speaker settings, audio/OTA writes and other attached devices remain out of scope.
The user subsequently requested emulator animation testing instead of phone
testing. All further device inputs use the owned AVD, serial `emulator-5580`;
no further phone testing or installation. Every installed app remains PreviewOnly,
with diagnostic tracing off. JBL terms/permissions remain the user's choices.
Do not modify or commit unrelated Linux decoder/runner work in this checkout.

Acceptance requires regression tests for early candidates, no device, permission,
background/cancel/race gates, reduced motion and 280 px/200 percent text. Inspect
actual rendered Flutter layouts before packaging, then verify icon, zoom motion,
full discovery, audio-only no-device recovery and retry on the emulator. Found
and BLE no-results states retain deterministic transport/widget checks; emulator
animation evidence does not establish physical radio or speaker discovery. Do not call the
full cross-platform product complete from this UI checkpoint.
