import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bdk_audio/app.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/features/sound/widgets/tone_controls.dart';
import 'package:bdk_audio/features/sound/widgets/preset_shape.dart';
import 'package:bdk_audio/features/sound/widgets/sound_options_panel.dart';
import '../session_test.dart' as fixtures;
import 'package:bdk_audio/features/pairing/speaker_pairing_screen.dart';
import 'package:bdk_audio/connection/speaker_setup_controller.dart';
import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/platform/audio_connection_adapter.dart';
import 'package:bdk_audio/protocol/speaker_protocol.dart';
import '../setup_controller_test.dart' as setup_fixtures;
import 'package:bdk_audio/features/codec/audio_quality_screen.dart';
import '../codec_test_support.dart';
import 'package:bdk_audio/features/codec/codec_models.dart';
import 'package:bdk_audio/features/sounds/sound_draft_store.dart';
import 'package:bdk_audio/features/sounds/sound_import_controller.dart';
import '../sound_import_controller_test.dart' as sound_fixtures;

class MemorySoundDrafts implements SoundDraftStore {
  final sounds = <int, PreparedSound>{};
  @override
  Future<Map<int, PreparedSound>> load() async => Map.unmodifiable(sounds);
  @override
  Future<void> save(int type, PreparedSound sound) async {
    sounds[type] = sound;
  }
}

void main() {
  testWidgets('phone Demo has an explicit Pair action that opens setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final transport = fixtures.FakeTransport();
    final session = SpeakerSession(transport);
    final setup = SpeakerSetupController(
      session,
      setup_fixtures.FakeAudio(),
      pollInterval: Duration.zero,
    );
    addTearDown(() async {
      setup.dispose();
      session.dispose();
      await transport.close();
    });
    await tester.pumpWidget(
      BdkApp(
        session: session,
        setup: setup,
        previewOnly: true,
        initialDemoMode: true,
      ),
    );
    await tester.pump();
    expect(find.text('Pair'), findsOneWidget);
    await tester.tap(find.text('Pair'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.byType(SpeakerPairingScreen), findsOneWidget);
    expect(find.text('Waiting for your speaker'), findsOneWidget);
    expect(transport.scanStarts, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'phone design build prepares and retains a local sound without speaker writes',
    (tester) async {
      final store = MemorySoundDrafts();
      final transport = fixtures.FakeTransport(),
          link = fixtures.FakeLink('speaker');
      transport.links.add(link);
      link.onWrite = (p) {
        if (p[0] == 0xf0) link.status(fixtures.fullStatus);
      };
      final session = SpeakerSession(transport);
      await session.connect('speaker');
      final ios = <sound_fixtures.FakeSoundIO>[];
      addTearDown(() async {
        session.dispose();
        await transport.close();
        for (final io in ios) {
          io.events.close().ignore();
        }
      });
      await tester.pumpWidget(
        BdkApp(
          session: session,
          previewOnly: true,
          soundDraftStore: store,
          soundImportIOFactory: () {
            final io = sound_fixtures.FakeSoundIO();
            ios.add(io);
            return io;
          },
        ),
      );
      await tester.tap(find.text('Speaker').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Speaker sounds'),
        140,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('Speaker sounds'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speaker sounds'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('speaker-sounds-switch')))
            .onChanged,
        isNull,
      );
      await tester.tap(find.text('Startup'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose audio'));
      await tester.pumpAndSettle();
      expect(store.sounds[0]?.name, 'Chime.wav');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Upload to speaker'),
            )
            .onPressed,
        isNull,
      );
      expect(link.writes.where((p) => p[0] >= 0x10 && p[0] <= 0x14), isEmpty);
      await tester.runAsync(session.disconnect);
      await tester.pumpAndSettle();
      expect(find.text('Chime.wav'), findsOneWidget);
      expect(find.byType(SpeakerPairingScreen), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SpeakerPairingScreen), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('pairing-demo')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('pairing-demo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speaker').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Speaker sounds'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speaker sounds'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Startup'));
      await tester.pumpAndSettle();
      expect(find.text('Chime.wav'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'audio quality starts below the title on a tall disconnected phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter = FakeCodecAdapter();
      adapter.onSnapshot = (_) async =>
          CodecSnapshot(access: CodecAccess.noAudioDevice);
      await tester.pumpWidget(
        BdkApp(initialDemoMode: true, codecAdapterFactory: () => adapter),
      );
      await tester.tap(find.text('Speaker').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Audio quality'));
      await tester.tap(find.text('Audio quality'));
      await tester.pumpAndSettle();
      final titleBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      final contentTop = tester
          .getTopLeft(find.text('Preview only · changes are disabled.'))
          .dy;
      expect(contentTop - titleBottom, inInclusiveRange(16, 48));
    },
  );
  for (final previewOnly in [false, true]) {
    testWidgets(
      '${previewOnly ? 'Phone preview' : 'Demo'} audio quality is read-only and releases its adapter',
      (tester) async {
        final adapter = FakeCodecAdapter();
        final transport = fixtures.FakeTransport();
        final session = SpeakerSession(transport);
        if (previewOnly) {
          final link = fixtures.FakeLink('speaker');
          transport.links.add(link);
          link.onWrite = (p) {
            if (p[0] == 0xf0) link.status(fixtures.fullStatus);
          };
          await session.connect('speaker');
        }
        addTearDown(() async {
          session.dispose();
          await transport.close();
        });
        await tester.pumpWidget(
          BdkApp(
            session: session,
            previewOnly: previewOnly,
            initialDemoMode: !previewOnly,
            codecAdapterFactory: () => adapter,
          ),
        );
        await tester.tap(find.text('Speaker').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Audio quality'));
        await tester.tap(find.text('Audio quality'));
        await tester.pumpAndSettle();
        final screen = tester.widget<AudioQualityScreen>(
          find.byType(AudioQualityScreen),
        );
        expect(screen.allowChanges, isFalse);
        expect(screen.controller.allowChanges, isFalse);
        expect(screen.controller.canEdit, isFalse);
        await screen.controller.applyPreference();
        expect(adapter.writes, isEmpty);
        await tester.pageBack();
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(adapter.disposed, 0);
        await tester.pumpAndSettle();
        expect(adapter.disposed, 1);
      },
    );
  }
  testWidgets(
    'Demo stays isolated even if an old connected meter event arrives',
    (tester) async {
      final transport = fixtures.FakeTransport(),
          link = fixtures.FakeLink('speaker');
      transport.links.add(link);
      link.onWrite = (p) {
        if (p[0] == 0xf0) {
          link.status(fixtures.fullStatus);
        } else {
          link.status([0x10, p[0]]);
        }
      };
      final session = SpeakerSession(transport);
      await session.connect('speaker');
      addTearDown(() async {
        session.dispose();
        await transport.close();
      });
      await tester.pumpWidget(BdkApp(session: session, initialDemoMode: true));
      link.meter([30, 40, 50]);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Equalizer'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('Equalizer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Equalizer'));
      await tester.pumpAndSettle();
      tester.widget<ToneControls>(find.byType(ToneControls)).onChanged([
        5,
        2,
        1,
      ]);
      await tester.pump();
      expect(link.writes.where((p) => p[0] == 1), isEmpty);
    },
  );
  testWidgets('phone design build keeps EQ and sound-option edits local', (
    tester,
  ) async {
    final transport = fixtures.FakeTransport(),
        link = fixtures.FakeLink('speaker');
    transport.links.add(link);
    link.onWrite = (p) {
      if (p[0] == 0xf0) link.status(fixtures.fullStatus);
    };
    final session = SpeakerSession(transport);
    await session.connect('speaker');
    addTearDown(() async {
      session.dispose();
      await transport.close();
    });
    await tester.pumpWidget(BdkApp(session: session, previewOnly: true));
    await tester.scrollUntilVisible(
      find.text('Equalizer'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('Equalizer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Equalizer'));
    await tester.pumpAndSettle();
    tester.widget<ToneControls>(find.byType(ToneControls)).onChanged([8, 2, 4]);
    await tester.pump();
    expect(link.writes.where((p) => p[0] == 1), isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sound options'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('Sound options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sound options'));
    await tester.pumpAndSettle();
    tester
        .widget<SoundOptionsPanel>(find.byType(SoundOptionsPanel))
        .onChanged(5);
    await tester.pump();
    expect(link.writes.where((p) => p[0] == 3), isEmpty);
  });
  testWidgets('first launch shows pairing and Demo is explicit', (
    tester,
  ) async {
    await tester.pumpWidget(const BdkApp());
    expect(find.byType(SpeakerPairingScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('pairing-demo')));
    await tester.tap(find.byKey(const ValueKey('pairing-demo')));
    await tester.pumpAndSettle();
    expect(find.byType(SpeakerPairingScreen), findsNothing);
    expect(find.text('Demo · Pair speaker'), findsOneWidget);
    await tester.tap(find.text('Demo · Pair speaker'));
    await tester.pump();
    expect(find.byType(SpeakerPairingScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '390px Demo header stays compact at ${scale}x text and returns to pairing',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(const BdkApp(initialDemoMode: true));
        expect(find.text('Pair'), findsOneWidget);
        expect(find.text('Demo · Pair speaker'), findsNothing);
        expect(find.byTooltip('Pair speaker'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Pair'));
        await tester.pump();
        expect(find.byType(SpeakerPairingScreen), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'real setup gate proceeds to home only after matched audio and valid control sync',
    (tester) async {
      final transport = fixtures.FakeTransport(),
          audio = setup_fixtures.FakeAudio();
      final session = SpeakerSession(transport),
          setup = SpeakerSetupController(
            session,
            audio,
            pollInterval: const Duration(seconds: 1),
          );
      addTearDown(() async {
        setup.dispose();
        session.dispose();
        await transport.close();
      });
      await tester.pumpWidget(BdkApp(session: session, setup: setup));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<SpeakerPairingScreen>(find.byType(SpeakerPairingScreen))
            .stage,
        PairingStage.audio,
      );
      expect(transport.scanStarts, 0);
      audio.current = const AudioConnectionSnapshot(
        devices: [
          AudioDeviceIdentity(id: 'aa:bb:cc:dd:ee:01', name: 'BDK SPEAKER'),
        ],
      );
      await setup.refresh();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SpeakerPairingScreen>(find.byType(SpeakerPairingScreen))
            .stage,
        PairingStage.controls,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('pairing-search-controls')),
      );
      await tester.tap(find.byKey(const ValueKey('pairing-search-controls')));
      await tester.pump();
      final link = fixtures.FakeLink('aa:bb:cc:dd:ee:01');
      transport.links.add(link);
      link.onWrite = (p) {
        if (p[0] == 0xf0) link.status(fixtures.fullStatus);
      };
      transport.scanController.add(
        const DiscoveredSpeaker(
          id: 'aa:bb:cc:dd:ee:01',
          name: 'BDK SPEAKER',
          services: [SpeakerProtocol.service],
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('pairing-control-aa:bb:cc:dd:ee:01')),
      );
      await tester.tap(
        find.byKey(const ValueKey('pairing-control-aa:bb:cc:dd:ee:01')),
      );
      await tester.pumpAndSettle();
      expect(session.state.value.connected, isTrue);
      expect(find.byType(SpeakerPairingScreen), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Equalizer'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('Equalizer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Equalizer'));
      await tester.pumpAndSettle();
      expect(find.byType(ToneControls), findsOneWidget);
      audio.current = const AudioConnectionSnapshot();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(session.state.value.connected, isFalse);
      expect(find.byType(SpeakerPairingScreen), findsOneWidget);
    },
  );
  testWidgets(
    'current preset illustration follows selection and uses Choose preset label',
    (tester) async {
      await tester.pumpWidget(const BdkApp(initialDemoMode: true));
      expect(find.text('Choose preset'), findsOneWidget);
      expect(find.text('Favorites'), findsNothing);
      expect(
        tester
            .widget<PresetShape>(
              find.byKey(const ValueKey('current-preset-shape')),
            )
            .levels,
        [0, 0, 0],
      );
      await tester.ensureVisible(find.text('Deep Bass'));
      await tester.tap(find.text('Deep Bass'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('current-preset-shape')),
        -180,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester
            .widget<PresetShape>(
              find.byKey(const ValueKey('current-preset-shape')),
            )
            .levels,
        [8, -1, -2],
      );
    },
  );
  testWidgets('sound is focused and equalizer/options have their own routes', (
    tester,
  ) async {
    await tester.pumpWidget(const BdkApp(initialDemoMode: true));
    expect(find.text('Demo · Pair speaker'), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Equalizer'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('Equalizer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Equalizer'));
    await tester.pumpAndSettle();
    expect(find.text('150 Hz'), findsOneWidget);
    expect(find.text('6 kHz'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sound options'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('Sound options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sound options'));
    await tester.pumpAndSettle();
    expect(find.text('Full-range stereo'), findsOneWidget);
    expect(find.text('Bypass equalizer'), findsNothing);
  });
  testWidgets('narrow and enlarged text layout has no exception', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const BdkApp(initialDemoMode: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('All presets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All presets'));
    await tester.pumpAndSettle();
    expect(find.text('Cinema'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'older ACK preserves newest draft and rejection rolls back to accepted EQ',
    (tester) async {
      final transport = fixtures.FakeTransport(),
          link = fixtures.FakeLink('speaker');
      transport.links.add(link);
      link.onWrite = (p) {
        if (p[0] == 0xf0) link.status(fixtures.fullStatus);
      };
      final session = SpeakerSession(transport);
      await session.connect('speaker');
      addTearDown(() async {
        session.dispose();
        await transport.close();
      });
      await tester.pumpWidget(BdkApp(session: session));
      await tester.scrollUntilVisible(
        find.text('Equalizer'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('Equalizer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Equalizer'));
      await tester.pumpAndSettle();
      tester.widget<ToneControls>(find.byType(ToneControls)).onChanged([
        1,
        -1,
        2,
      ]);
      await tester.pump();
      tester.widget<ToneControls>(find.byType(ToneControls)).onChanged([
        3,
        -1,
        2,
      ]);
      await tester.pump();
      link.status([0x10, 1]);
      await tester.pump();
      await tester.pump();
      expect(tester.widget<ToneControls>(find.byType(ToneControls)).levels, [
        3,
        -1,
        2,
      ]);
      link.status([0x11, 1, 2]);
      await tester.pump();
      await tester.pump();
      expect(tester.widget<ToneControls>(find.byType(ToneControls)).levels, [
        1,
        -1,
        2,
      ]);
    },
  );
}
