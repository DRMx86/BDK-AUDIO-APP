import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/sounds/speaker_sounds_screen.dart';
import 'package:bdk_audio/features/sounds/sound_import_controller.dart';
import 'package:bdk_audio/features/sounds/wav_audio.dart';
import 'package:bdk_audio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../sound_transfer_test_support.dart';

class ScreenSoundIO implements SoundImportIO {
  final events = StreamController<SoundPreviewEvent>.broadcast(sync: true);
  AudioImportSource? picked = const AudioImportSource(
    path: 'clip.wav',
    name: 'Chime.wav',
  );
  AudioImportInfo metadata = const AudioImportInfo(
    duration: Duration(milliseconds: 100),
    sampleRate: 48000,
    channels: 2,
  );
  final decoded = <SoundClipPlan>[];
  int plays = 0, stops = 0, disposals = 0;
  @override
  Stream<SoundPreviewEvent> get previewEvents => events.stream;
  @override
  Future<AudioImportSource?> pick() async => picked;
  @override
  void cancelPick() {}
  @override
  Future<AudioImportInfo> inspect(AudioImportSource source) async => metadata;
  @override
  Future<Int16List> decode(AudioImportSource source, SoundClipPlan plan) async {
    decoded.add(plan);
    return Int16List(plan.frameCount!);
  }

  @override
  Future<void> play(Uint8List wave, {required int revision}) async {
    plays++;
    events.add(SoundPreviewEvent(revision, playing: true));
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await stop();
    await events.close();
  }
}

PreparedSound storedSound({
  Duration duration = const Duration(milliseconds: 100),
  String name = 'Stored chime.wav',
}) {
  final info = AudioImportInfo(
    duration: duration,
    sampleRate: 48000,
    channels: 2,
  );
  final plan = SoundClipPolicy.plan(total: info.duration);
  return PreparedSound(
    name: name,
    wave: Pcm16Wave.encodeMono(Int16List(plan.frameCount!), plan.outputRate!),
    plan: plan,
    sourceInfo: info,
  );
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('BDK_CAPTURE_SOUNDS')) return;
    for (final family in ['Manrope', 'SpaceGrotesk']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final ios = <ScreenSoundIO>[];
  SoundTestRig? rig;
  setUp(() {
    ios.clear();
    rig = null;
  });
  tearDown(() async {
    await rig?.close();
  });
  Future<void> mount(
    WidgetTester tester, {
    bool changes = false,
    Map<int, PreparedSound> sounds = const {},
    Future<void> Function(int, PreparedSound)? prepared,
    Duration? duration,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: bdkTheme(Brightness.dark),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('sounds-capture'),
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('Speaker sounds')),
          body: SpeakerSoundsScreen(
            session: rig?.session,
            speaker: rig?.session.state.value ?? const SpeakerState(),
            allowChanges: changes,
            initialSounds: sounds,
            onPrepared: prepared,
            importIOFactory: () {
              final io = ScreenSoundIO();
              if (duration != null) {
                io.metadata = AudioImportInfo(
                  duration: duration,
                  sampleRate: 48000,
                  channels: 2,
                );
              }
              ios.add(io);
              return io;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final found = find.text(label).last;
    await tester.ensureVisible(found);
    await tester.tap(found);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> connected({int flags = 15}) async {
    rig = SoundTestRig();
    await rig!.connect();
    rig!.link.soundFlags = flags;
    rig!.link.fullStatus();
  }

  testWidgets(
    'four focused rows separate confirmed speaker presence from local draft',
    (tester) async {
      await connected(flags: 1);
      await mount(tester, changes: true, sounds: {2: storedSound()});
      for (final label in ['Startup', 'Pairing', 'Connected', 'Volume limit']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('On speaker · Custom sound'), findsOneWidget);
      expect(find.text('On speaker · No custom sound'), findsNWidgets(3));
      expect(
        find.textContaining('Local draft · Stored chime.wav'),
        findsOneWidget,
      );
      expect(find.text('Upload to speaker'), findsNothing);
      expect(ios, isEmpty);
    },
  );

  testWidgets(
    'Demo imports prepares and previews locally without remote actions',
    (tester) async {
      final saved = <PreparedSound>[];
      await mount(
        tester,
        prepared: (type, sound) async {
          expect(type, 0);
          saved.add(sound);
        },
      );
      await tap(tester, 'Startup');
      await tap(tester, 'Choose audio');
      expect(find.text('Chime.wav'), findsOneWidget);
      expect(saved, hasLength(1));
      expect(ios.single.plays, 0);
      final upload = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Upload to speaker'),
      );
      expect(upload.onPressed, isNull);
      await tap(tester, 'Preview locally');
      expect(ios.single.plays, 1);
      expect(find.text('Stop preview'), findsOneWidget);
      expect(find.text('On speaker · Custom sound'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(ios.single.disposals, 1);
    },
  );

  testWidgets('long source requires explicit clip selection before prepare', (
    tester,
  ) async {
    await mount(tester, duration: const Duration(minutes: 1));
    await tap(tester, 'Pairing');
    await tap(tester, 'Choose audio');
    expect(ios.single.decoded, isEmpty);
    expect(find.text('Choose a short clip'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Prepare clip'),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, 'Use first 3 seconds');
    await tap(tester, 'Prepare clip');
    expect(ios.single.decoded.single.duration, const Duration(seconds: 3));
    expect(find.textContaining('Excerpt'), findsOneWidget);
  });

  testWidgets(
    'stored draft previews but does not pretend missing original can be edited',
    (tester) async {
      await mount(tester, sounds: {0: storedSound()});
      await tap(tester, 'Startup');
      expect(find.byType(RangeSlider), findsNothing);
      expect(
        find.textContaining('Pick the original file again'),
        findsOneWidget,
      );
      expect(find.text('Adjust clip'), findsNothing);
      await tap(tester, 'Preview locally');
      expect(ios.single.plays, 1);
      expect(ios.single.decoded, isEmpty);
    },
  );

  testWidgets(
    'existing custom sound requires concrete replacement confirmation before writes',
    (tester) async {
      await connected(flags: 1);
      rig!.respondUpload();
      await mount(tester, changes: true, sounds: {0: storedSound()});
      await tap(tester, 'Startup');
      await tap(tester, 'Upload to speaker');
      expect(find.text('Replace startup sound?'), findsOneWidget);
      expect(
        find.textContaining('may lose the current custom sound'),
        findsOneWidget,
      );
      expect(rig!.link.writes, isEmpty);
      await tap(tester, 'Keep current');
      expect(rig!.link.writes, isEmpty);
      await tap(tester, 'Upload to speaker');
      await tap(tester, 'Replace sound');
      expect(rig!.link.writes.last, [0xf0]);
      expect(find.text('Upload confirmed by speaker'), findsOneWidget);
      expect(rig!.link.disconnectCalls, 0);
    },
  );

  testWidgets(
    'default slot uploads without replacement prompt and updates only confirmed presence',
    (tester) async {
      await connected(flags: 0);
      rig!.link.onWrite = (packet) async {
        if (packet.first == 0x12 || packet.first == 0x13) {
          rig!.link.status([0x31]);
        }
        if (packet.first == 0x14) {
          // Keep the fake's stored state consistent with its unsolicited
          // notification so the subsequent fresh F0 confirms the same slot.
          rig!.link.soundFlags = 1;
          rig!.link.status([6, 1]);
          rig!.link.status([0x32]);
        }
      };
      await mount(tester, changes: true, sounds: {0: storedSound()});
      await tap(tester, 'Startup');
      await tap(tester, 'Upload to speaker');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Upload confirmed by speaker'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('On speaker · Custom sound'), findsOneWidget);
    },
  );

  testWidgets(
    'shipping parity refreshes presence without an unsolicited slot status',
    (tester) async {
      await connected(flags: 0);
      rig!.link.onWrite = (packet) async {
        if (packet.first == 0x12 || packet.first == 0x13) {
          rig!.link.status([0x31]);
        }
        if (packet.first == 0x14) {
          rig!.link.soundFlags = 1;
          rig!.link.status([0x32]);
        }
      };
      await mount(tester, changes: true, sounds: {0: storedSound()});
      await tap(tester, 'Startup');
      await tap(tester, 'Upload to speaker');

      expect(find.text('On speaker · Custom sound'), findsOneWidget);
      expect(find.text('Remove custom sound'), findsOneWidget);
      expect(find.text('Upload confirmed by speaker'), findsOneWidget);
      await tap(tester, 'Upload to speaker');
      expect(find.text('Replace startup sound?'), findsOneWidget);
      await tap(tester, 'Keep current');
    },
  );

  testWidgets(
    'shipping parity warns before replacing an upload with unconfirmed presence',
    (tester) async {
      await connected(flags: 0);
      // A valid full status still says absent after COMPLETE. This is not proof
      // that a second upload is safe to treat as a first installation.
      rig!.respondUpload();
      await mount(tester, changes: true, sounds: {0: storedSound()});
      await tap(tester, 'Startup');
      await tap(tester, 'Upload to speaker');

      expect(find.textContaining('presence'), findsWidgets);
      expect(find.text('Upload confirmed by speaker'), findsOneWidget);
      final writesBeforeRetry = rig!.link.writes.length;
      await tap(tester, 'Upload to speaker');
      expect(find.text('Replace startup sound?'), findsOneWidget);
      expect(rig!.link.writes.length, writesBeforeRetry);
      await tap(tester, 'Keep current');
    },
  );

  testWidgets(
    'mute switch stays at confirmed status until command ACK and flags',
    (tester) async {
      await connected(flags: 15);
      await mount(tester, changes: true);
      await tester.tap(find.byKey(const ValueKey('speaker-sounds-switch')));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(rig!.link.writes.single, [0x10, 1]);
      rig!.link.status([6, 0x8f]);
      rig!.link.status([0x10, 0x10]);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    },
  );

  testWidgets(
    'restore default requires ACK and status then retains local draft',
    (tester) async {
      await connected(flags: 1);
      rig!.link.onWrite = (packet) async {
        if (packet.first == 0x11) {
          rig!.link.status([0x10, 0x11]);
          rig!.link.status([6, 0]);
        }
      };
      await mount(tester, changes: true, sounds: {0: storedSound()});
      await tap(tester, 'Startup');
      await tap(tester, 'Remove custom sound');
      await tap(tester, 'Remove sound');
      expect(rig!.link.writes.single, [0x11, 0]);
      expect(find.text('On speaker · No custom sound'), findsOneWidget);
      expect(find.text('Stored chime.wav'), findsOneWidget);
    },
  );

  testWidgets(
    'cancel upload explains BLE disconnect and never sends abort command',
    (tester) async {
      await connected(flags: 0);
      await mount(tester, changes: true, sounds: {0: storedSound()});
      await tap(tester, 'Startup');
      await tester.ensureVisible(find.text('Upload to speaker'));
      await tester.tap(find.text('Upload to speaker'));
      await tester.pump();
      expect(
        find.textContaining('Cancel disconnects speaker controls'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Cancel upload'));
      await tester.tap(find.text('Cancel upload'));
      // Stream subscription cancellation includes root-zone async completion.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(rig!.link.disconnectCalls, 1);
      expect(rig!.link.writes.map((packet) => packet.first), [0x12]);
      expect(find.text('On speaker · Custom sound'), findsNothing);
    },
  );

  testWidgets('playback stops on background and editor route exit', (
    tester,
  ) async {
    await mount(tester, sounds: {0: storedSound()});
    await tap(tester, 'Startup');
    await tap(tester, 'Preview locally');
    final before = ios.single.stops;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(ios.single.stops, greaterThan(before));
    expect(find.text('Preview locally'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tap(tester, 'Preview locally');
    final second = ios.single.stops;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(ios.single.stops, greaterThan(second));
  });

  for (final width in [280.0, 320.0]) {
    testWidgets(
      'list and editor fit ${width.toInt()} pixels at 2x with 48px actions',
      (tester) async {
        await mount(tester, width: width, scale: 2, sounds: {0: storedSound()});
        expect(tester.takeException(), isNull);
        await tap(tester, 'Startup');
        await tester.ensureVisible(find.text('Upload to speaker'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = find.widgetWithText(FilledButton, 'Upload to speaker');
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        await tester.ensureVisible(find.text('Preview locally'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tap(tester, 'Choose another file');
        await tap(tester, 'Adjust clip');
        await tap(tester, 'Set exact times');
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const ValueKey('clip-length-seconds')),
          '13',
        );
        await tap(tester, 'Apply clip');
        expect(
          find.text('Choose up to 12.797 seconds within this audio.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const ValueKey('clip-length-seconds')),
          '0.05',
        );
        await tap(tester, 'Apply clip');
        await tap(tester, 'Prepare clip');
        expect(
          ios.single.decoded.last.duration,
          const Duration(milliseconds: 50),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('connected preview build still guards mute upload and removal', (
    tester,
  ) async {
    await connected(flags: 1);
    await mount(tester, sounds: {0: storedSound()});
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    await tap(tester, 'Startup');
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Upload to speaker'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Remove custom sound'),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, 'Preview locally');
    expect(ios.single.plays, 1);
    expect(rig!.link.writes, isEmpty);
  });

  testWidgets(
    'new local draft cannot inherit the previous upload success message',
    (tester) async {
      await connected(flags: 0);
      rig!.respondUpload();
      await mount(tester, changes: true, sounds: {0: storedSound()});
      await tap(tester, 'Startup');
      await tap(tester, 'Upload to speaker');
      expect(find.text('Upload confirmed by speaker'), findsOneWidget);
      await tap(tester, 'Choose another file');
      expect(find.text('Chime.wav'), findsOneWidget);
      expect(find.text('Upload confirmed by speaker'), findsNothing);
    },
  );

  testWidgets(
    'local save failure keeps preview usable without claiming speaker upload',
    (tester) async {
      await mount(
        tester,
        prepared: (_, _) async => throw StateError('disk full'),
      );
      await tap(tester, 'Startup');
      await tap(tester, 'Choose audio');
      expect(
        find.textContaining('saving this local draft failed'),
        findsOneWidget,
      );
      await tap(tester, 'Preview locally');
      expect(ios.single.plays, 1);
      expect(find.text('Upload confirmed by speaker'), findsNothing);
    },
  );

  testWidgets('lower sample rate is explained in prepared clip information', (
    tester,
  ) async {
    await mount(tester, duration: const Duration(seconds: 5));
    await tap(tester, 'Startup');
    await tap(tester, 'Choose audio');
    expect(find.textContaining('16 kHz'), findsOneWidget);
    expect(
      find.text('Reduced sample rate to fit the 200 KiB limit.'),
      findsOneWidget,
    );
  });

  testWidgets('selects an exact nonzero short excerpt from a ten minute file', (
    tester,
  ) async {
    await mount(tester, duration: const Duration(minutes: 10));
    await tap(tester, 'Startup');
    await tap(tester, 'Choose audio');
    await tap(tester, 'Set exact times');
    await tester.enterText(
      find.byKey(const ValueKey('clip-start-seconds')),
      '125.25',
    );
    await tester.enterText(
      find.byKey(const ValueKey('clip-length-seconds')),
      '3',
    );
    await tap(tester, 'Apply clip');
    await tap(tester, 'Prepare clip');
    expect(
      ios.single.decoded.single.start,
      const Duration(milliseconds: 125250),
    );
    expect(ios.single.decoded.single.duration, const Duration(seconds: 3));
    expect(find.text('Chime.wav'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editor exit cancels pending upload without abandoning the writer',
    (tester) async {
      await connected(flags: 0);
      await mount(tester, changes: true, sounds: {0: storedSound()});
      await tap(tester, 'Startup');
      await tester.ensureVisible(find.text('Upload to speaker'));
      await tester.tap(find.text('Upload to speaker'));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(rig!.link.disconnectCalls, 1);
      expect(rig!.link.writes.map((packet) => packet.first), [0x12]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing preview policy updates an open editor without late build notifications',
    (tester) async {
      await connected(flags: 1);
      await mount(tester, changes: true, sounds: {0: storedSound()});
      await tap(tester, 'Startup');
      await mount(tester, changes: false, sounds: {0: storedSound()});
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Upload to speaker'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      expect(rig!.link.writes, isEmpty);
    },
  );

  if (const bool.fromEnvironment('BDK_CAPTURE_SOUNDS')) {
    testWidgets('capture simulated native sounds screens', (tester) async {
      await connected(flags: 1);
      final draft = storedSound(
        duration: const Duration(seconds: 2),
        name: 'Soft startup chime.wav',
      );
      await mount(tester, changes: true, sounds: {0: draft});
      tester.view.physicalSize = const Size(390, 844);
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('sounds-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${Directory.systemTemp.path}/bdk-speaker-sounds-simulated-$name.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('list');
      await tap(tester, 'Startup');
      await capture('editor');
    });
  }
}
