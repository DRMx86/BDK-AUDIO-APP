import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/features/pairing/speaker_pairing_screen.dart';
import 'package:bdk_audio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Actions {
  int settings = 0,
      permission = 0,
      search = 0,
      cancel = 0,
      demo = 0,
      retryAudio = 0,
      confirm = 0;
  final audio = <String>[];
  final controls = <String>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Manrope', 'SpaceGrotesk']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$family.ttf'));
      await loader.load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<_Actions> mount(
    WidgetTester tester, {
    PairingStage stage = PairingStage.audio,
    List<PairingAudioDevice> audio = const [],
    String? selected,
    List<DiscoveredSpeaker> controls = const [],
    bool busy = false,
    bool permission = false,
    bool verification = true,
    bool completed = false,
    bool audioCompleted = false,
    bool continuous = false,
    bool checkingAudio = false,
    bool searching = false,
    String? message,
    double width = 390,
    double scale = 1,
    bool reducedMotion = false,
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final actions = _Actions();
    await tester.pumpWidget(
      MaterialApp(
        theme: bdkTheme(brightness),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('pairing-capture'),
            child: ColoredBox(
              color: bdkTheme(brightness).colorScheme.surface,
              child: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 844),
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: reducedMotion,
                ),
                child: SpeakerPairingScreen(
                  stage: stage,
                  audioDevices: audio,
                  selectedAudioId: selected,
                  controlDevices: controls,
                  busy: busy,
                  permissionRequired: permission,
                  audioVerificationAvailable: verification,
                  searchCompleted: completed,
                  audioSearchCompleted: audioCompleted,
                  continuousDiscovery: continuous,
                  checkingAudio: checkingAudio,
                  searching: searching,
                  message: message,
                  onOpenBluetoothSettings: () => actions.settings++,
                  onRequestPermission: () => actions.permission++,
                  onSelectAudioDevice: actions.audio.add,
                  onSearchControls: () => actions.search++,
                  onConnectControls: actions.controls.add,
                  onCancel: () => actions.cancel++,
                  onExploreDemo: () => actions.demo++,
                  onConfirmAudioConnection: () => actions.confirm++,
                  onRetryAudio: () => actions.retryAudio++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return actions;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('BDK_CAPTURE_PAIRING')) return;
    if (find.text('BDK AUDIO').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('BDK AUDIO'));
    }
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('pairing-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${Directory.systemTemp.path}/bdk-pairing-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'legacy busy discovery does not offer persistent connection help',
    (tester) async {
      await mount(tester, busy: true, audioCompleted: true);
      expect(find.text('Checking Bluetooth audio…'), findsOneWidget);
      expect(find.text('Connected to your speaker?'), findsNothing);
      expect(find.byKey(const ValueKey('pairing-open-settings')), findsNothing);
      expect(find.byKey(const ValueKey('pairing-demo')), findsNothing);
    },
  );

  for (final stage in [PairingStage.audio, PairingStage.controls]) {
    testWidgets(
      'continuous ${stage.name}: connection help keeps searching and opens settings only on tap',
      (tester) async {
        final actions = await mount(
          tester,
          stage: stage,
          continuous: true,
          busy: true,
          checkingAudio: stage == PairingStage.audio,
          searching: stage == PairingStage.controls,
          audioCompleted: stage == PairingStage.audio,
          completed: stage == PairingStage.controls,
        );
        expect(find.text('Connected to your speaker?'), findsOneWidget);
        expect(find.textContaining('We’ll keep'), findsOneWidget);
        expect(find.text('No speaker found'), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        await tester.pump(const Duration(seconds: 8));
        expect(tester.hasRunningAnimations, isTrue);
        expect(actions.settings, 0);
        expect(actions.search, 0);
        expect(actions.retryAudio, 0);
        expect(actions.controls, isEmpty);
        final connect = find.byKey(const ValueKey('pairing-open-settings'));
        await tester.ensureVisible(connect);
        expect(find.text('Connect speaker'), findsOneWidget);
        expect(tester.getSize(connect).height, greaterThanOrEqualTo(52));
        await tester.tap(connect);
        expect(actions.settings, 1);
        expect(actions.controls, isEmpty);
        await tester.ensureVisible(find.byKey(const ValueKey('pairing-demo')));
        await tester.tap(find.byKey(const ValueKey('pairing-demo')));
        expect(actions.demo, 1);
        await tester.ensureVisible(
          find.byKey(const ValueKey('pairing-cancel')),
        );
        await tester.tap(find.byKey(const ValueKey('pairing-cancel')));
        expect(actions.cancel, 1);
        await capture(tester, 'persistent-${stage.name}');
      },
    );

    testWidgets(
      'continuous ${stage.name}: reduced motion and 280px 2x text keep help usable',
      (tester) async {
        final actions = await mount(
          tester,
          stage: stage,
          continuous: true,
          busy: true,
          audioCompleted: stage == PairingStage.audio,
          completed: stage == PairingStage.controls,
          reducedMotion: true,
          width: 280,
          scale: 2,
        );
        expect(find.text('Connected to your speaker?'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.hasRunningAnimations, isFalse);
        final connect = find.byKey(const ValueKey('pairing-open-settings'));
        await tester.ensureVisible(connect);
        expect(tester.getSize(connect).height, greaterThanOrEqualTo(52));
        await tester.tap(connect);
        expect(actions.settings, 1);
        final demo = find.byKey(const ValueKey('pairing-demo'));
        await tester.ensureVisible(demo);
        expect(tester.getSize(demo).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await capture(tester, 'persistent-${stage.name}-large-text');
      },
    );
  }

  testWidgets(
    'completed audio search is a still full-page recovery and retries only the audio check',
    (tester) async {
      final actions = await mount(tester, audioCompleted: true);
      expect(find.text('No speaker found'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pairing-discovery-hero')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pairing-status-surface')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      final retry = find.byKey(const ValueKey('pairing-retry-audio'));
      await tester.ensureVisible(retry);
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(52));
      await tester.tap(retry);
      expect(actions.retryAudio, 1);
      expect(actions.search, 0);
      expect(actions.controls, isEmpty);
      await tester.ensureVisible(
        find.byKey(const ValueKey('pairing-open-settings')),
      );
      await tester.tap(find.byKey(const ValueKey('pairing-open-settings')));
      expect(actions.settings, 1);
      expect(
        find.byKey(const ValueKey('pairing-search-controls')),
        findsNothing,
      );
      await capture(tester, 'audio-empty');
    },
  );

  testWidgets(
    'a repeated audio query takes priority over the previous empty result',
    (tester) async {
      await mount(tester, audioCompleted: true, busy: true);
      expect(find.text('Checking Bluetooth audio…'), findsOneWidget);
      expect(find.text('No speaker found'), findsNothing);
      expect(find.byKey(const ValueKey('pairing-retry-audio')), findsNothing);
      expect(
        find.byKey(const ValueKey('pairing-search-controls')),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);
    },
  );

  testWidgets(
    'finding remains the full page when an early candidate arrives during discovery',
    (tester) async {
      final actions = await mount(
        tester,
        stage: PairingStage.controls,
        busy: true,
        controls: const [
          DiscoveredSpeaker(id: 'early', name: 'Nearby speaker'),
        ],
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Finding your speaker…'), findsOneWidget);
      expect(find.byKey(const ValueKey('pairing-control-early')), findsNothing);
      expect(
        find.byKey(const ValueKey('pairing-search-controls')),
        findsNothing,
      );
      expect(tester.hasRunningAnimations, isTrue);
      await tester.tap(find.byKey(const ValueKey('pairing-cancel')));
      expect(actions.cancel, 1);
      expect(actions.controls, isEmpty);
    },
  );

  testWidgets(
    'finding gives the speaker illustration room above one large status surface',
    (tester) async {
      await mount(tester, stage: PairingStage.controls, busy: true);
      final hero = find.byKey(const ValueKey('pairing-discovery-hero'));
      final status = find.byKey(const ValueKey('pairing-status-surface'));
      expect(hero, findsOneWidget);
      expect(status, findsOneWidget);
      expect(tester.getSize(hero).height, greaterThanOrEqualTo(250));
      expect(tester.getSize(status).width, greaterThanOrEqualTo(330));
      expect(
        tester.getTopLeft(status).dy,
        greaterThan(tester.getTopLeft(hero).dy),
      );
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'empty search keeps the full finding composition and a large usable retry',
    (tester) async {
      final actions = await mount(
        tester,
        stage: PairingStage.controls,
        completed: true,
      );
      expect(
        find.byKey(const ValueKey('pairing-discovery-hero')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pairing-status-surface')),
        findsOneWidget,
      );
      final retry = find.byKey(const ValueKey('pairing-search-controls'));
      await tester.ensureVisible(retry);
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(52));
      await tester.tap(retry);
      expect(actions.search, 1);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'disconnected waiting animates without claiming a connection or exposing controls',
    (tester) async {
      await mount(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);
      expect(find.text('Waiting for your speaker'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
      expect(
        find.byKey(const ValueKey('pairing-search-controls')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'reduced motion keeps waiting readable without an animation ticker',
    (tester) async {
      for (final stage in [PairingStage.audio, PairingStage.connecting]) {
        await mount(tester, stage: stage, reducedMotion: true);
        await tester.pumpAndSettle();
        expect(tester.hasRunningAnimations, isFalse);
        expect(find.byKey(const ValueKey('pairing-cancel')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'permission and recovery states do not imply work is still running',
    (tester) async {
      await mount(tester, permission: true);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      await mount(tester, stage: PairingStage.controls, completed: true);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('Search again'), findsOneWidget);
    },
  );

  testWidgets(
    'active connection keeps the finding composition and only cancellation',
    (tester) async {
      await mount(
        tester,
        stage: PairingStage.connecting,
        busy: true,
        selected: 'audio-one',
        audio: const [PairingAudioDevice(id: 'audio-one', name: 'BDK SPEAKER')],
      );
      expect(find.text('BDK SPEAKER'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pairing-discovery-hero')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pairing-status-surface')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pairing-demo')), findsNothing);
      expect(find.byKey(const ValueKey('pairing-open-settings')), findsNothing);
      expect(find.textContaining('of 2'), findsNothing);
      expect(find.byKey(const ValueKey('pairing-cancel')), findsOneWidget);
    },
  );

  testWidgets(
    'first setup directs to Bluetooth audio and exposes no control search',
    (tester) async {
      final actions = await mount(tester);
      expect(find.text('Waiting for your speaker'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pairing-search-controls')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('pairing-connect-ble')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pairing-open-settings')));
      expect(actions.settings, 1);
      expect(actions.search, 0);
      await capture(tester, 'audio');
    },
  );

  testWidgets(
    'audio device selection emits exact identity and cannot locally advance setup',
    (tester) async {
      final actions = await mount(
        tester,
        selected: 'audio-one',
        audio: const [
          PairingAudioDevice(id: 'audio-one', name: 'BDK SPEAKER'),
          PairingAudioDevice(id: 'audio-two', name: 'Desk speaker'),
        ],
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('pairing-audio-audio-two')),
      );
      await tester.tap(find.byKey(const ValueKey('pairing-audio-audio-two')));
      expect(actions.audio, ['audio-two']);
      expect(find.text('Choose your speaker'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pairing-search-controls')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'OS-managed audio requires explicit confirmation without claiming verification',
    (tester) async {
      final actions = await mount(
        tester,
        verification: false,
        audioCompleted: true,
      );
      expect(find.textContaining('cannot check'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pairing-confirm-audio')),
        findsOneWidget,
      );
      expect(actions.confirm, 0);
      await tester.tap(find.byKey(const ValueKey('pairing-confirm-audio')));
      expect(actions.confirm, 1);
      expect(
        find.byKey(const ValueKey('pairing-search-controls')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'controls stage shows the selected audio name and permits an explicit search',
    (tester) async {
      final actions = await mount(
        tester,
        stage: PairingStage.controls,
        selected: 'audio-one',
        audio: const [PairingAudioDevice(id: 'audio-one', name: 'BDK SPEAKER')],
      );
      expect(find.text('BDK SPEAKER'), findsOneWidget);
      expect(find.text('Find your speaker'), findsOneWidget);
      expect(find.text('Bluetooth audio connected'), findsOneWidget);
      expect(find.text('Find speaker'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pairing-search-controls')));
      expect(actions.search, 1);
      expect(find.text('Connected'), findsNothing);
    },
  );

  testWidgets(
    'completed empty search offers Bluetooth settings and retry instead of a dead list',
    (tester) async {
      final actions = await mount(
        tester,
        stage: PairingStage.controls,
        completed: true,
        selected: 'audio-one',
        audio: const [PairingAudioDevice(id: 'audio-one', name: 'BDK SPEAKER')],
      );
      expect(find.text('No speaker found'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('pairing-open-settings')),
      );
      await tester.tap(find.byKey(const ValueKey('pairing-open-settings')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('pairing-search-controls')),
      );
      await tester.tap(find.byKey(const ValueKey('pairing-search-controls')));
      expect(actions.settings, 1);
      expect(actions.search, 1);
      await capture(tester, 'recovery');
    },
  );

  testWidgets(
    'control candidate connects only the tapped identity and stays unconfirmed',
    (tester) async {
      final actions = await mount(
        tester,
        stage: PairingStage.controls,
        completed: true,
        controls: const [
          DiscoveredSpeaker(id: 'ble-one', name: 'BDK control'),
          DiscoveredSpeaker(id: 'ble-two', name: 'Desk control'),
        ],
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('pairing-control-ble-two')),
      );
      await tester.tap(find.byKey(const ValueKey('pairing-control-ble-two')));
      expect(actions.controls, ['ble-two']);
      expect(find.text('Connected'), findsNothing);
      expect(find.textContaining('setup complete'), findsNothing);
    },
  );

  testWidgets(
    'denied permission remains recoverable and suppresses search until root authorizes it',
    (tester) async {
      final actions = await mount(
        tester,
        stage: PairingStage.controls,
        permission: true,
        message: 'Bluetooth permission was denied. You can try again.',
      );
      expect(find.textContaining('denied'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('pairing-permission')),
      );
      await tester.tap(find.byKey(const ValueKey('pairing-permission')));
      expect(actions.permission, 1);
      expect(
        find.byKey(const ValueKey('pairing-search-controls')),
        findsNothing,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('pairing-demo')));
      await tester.tap(find.byKey(const ValueKey('pairing-demo')));
      expect(actions.demo, 1);
    },
  );

  testWidgets(
    'connecting waits for verified settings and allows cancellation without fake success',
    (tester) async {
      final actions = await mount(
        tester,
        stage: PairingStage.connecting,
        busy: true,
      );
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pairing-cancel')));
      expect(actions.cancel, 1);
      expect(actions.controls, isEmpty);
    },
  );

  testWidgets(
    'busy discovery disables duplicate search and candidate connection but leaves Cancel',
    (tester) async {
      final actions = await mount(
        tester,
        stage: PairingStage.controls,
        busy: true,
        controls: const [DiscoveredSpeaker(id: 'ble-one', name: 'BDK control')],
      );
      expect(
        find.byKey(const ValueKey('pairing-search-controls')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pairing-control-ble-one')),
        findsNothing,
      );
      expect(actions.search, 0);
      expect(actions.controls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('pairing-cancel')));
      expect(actions.cancel, 1);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name}: full discovery and recovery render fixtures',
      (tester) async {
        for (final state in [
          'searching',
          'found',
          'permission',
          'empty',
          'help',
          'audio-help',
        ]) {
          await mount(
            tester,
            stage: state == 'audio-help'
                ? PairingStage.audio
                : PairingStage.controls,
            brightness: brightness,
            busy:
                state == 'searching' ||
                state == 'help' ||
                state == 'audio-help',
            permission: state == 'permission',
            completed: state == 'empty' || state == 'found' || state == 'help',
            audioCompleted: state == 'audio-help',
            continuous: state == 'help' || state == 'audio-help',
            selected: 'audio-one',
            audio: state == 'audio-help'
                ? const []
                : const [
                    PairingAudioDevice(id: 'audio-one', name: 'BDK SPEAKER'),
                  ],
            controls: state == 'found'
                ? const [DiscoveredSpeaker(id: 'ble-one', name: 'BDK SPEAKER')]
                : const [],
          );
          await tester.pump(const Duration(milliseconds: 450));
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('pairing-status-surface')),
            findsOneWidget,
          );
          expect(find.byType(Dialog), findsNothing);
          await capture(tester, '${brightness.name}-$state');
        }
        await mount(
          tester,
          stage: PairingStage.controls,
          busy: true,
          width: 1180,
          brightness: brightness,
        );
        final hero = find.byKey(const ValueKey('pairing-discovery-hero'));
        final status = find.byKey(const ValueKey('pairing-status-surface'));
        expect(
          tester.getTopLeft(status).dx,
          greaterThan(tester.getTopRight(hero).dx),
        );
        expect(tester.getSize(status).width, lessThan(520));
        expect(tester.takeException(), isNull);
        await capture(tester, '${brightness.name}-desktop-searching');
      },
    );
  }

  for (final stage in PairingStage.values) {
    testWidgets(
      '${stage.name}: 280px and 2x text remain usable with 48px actions',
      (tester) async {
        await mount(
          tester,
          stage: stage,
          width: 280,
          scale: 2,
          verification: false,
          completed: true,
          controls: const [
            DiscoveredSpeaker(id: 'ble-one', name: 'BDK speaker controls'),
          ],
        );
        expect(tester.takeException(), isNull);
        final action = find.byKey(
          ValueKey(
            stage == PairingStage.connecting
                ? 'pairing-cancel'
                : 'pairing-demo',
          ),
        );
        await tester.ensureVisible(action);
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await capture(tester, '${stage.name}-large-text');
      },
    );
  }
}
