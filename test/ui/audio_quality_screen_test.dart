import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdk_audio/features/codec/audio_quality_screen.dart';
import 'package:bdk_audio/features/codec/codec_controller.dart';
import 'package:bdk_audio/features/codec/codec_models.dart';
import 'package:bdk_audio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../codec_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('BDK_CAPTURE_CODEC')) return;
    for (final family in ['Manrope', 'SpaceGrotesk']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('BDK_CAPTURE_CODEC')) return;
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('codec-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${Directory.systemTemp.path}/bdk-audio-quality-simulated-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<(CodecController, FakeCodecAdapter)> mount(
    WidgetTester tester, {
    CodecSnapshot? snapshot,
    bool allowChanges = true,
    bool controllerChanges = true,
    double width = 390,
    double scale = 1,
    DateTime Function()? now,
  }) async {
    var clock = DateTime.fromMillisecondsSinceEpoch(100000);
    var rate = 2;
    final adapter = FakeCodecAdapter();
    adapter.onSnapshot = (_) async =>
        snapshot ??
        codecFixture(
          rate: rate,
          stamp: (now?.call() ?? clock).millisecondsSinceEpoch,
        );
    adapter.onApply = (_, value) async {
      rate = value.sampleRateMask;
      clock = clock.add(const Duration(milliseconds: 1));
      return true;
    };
    final controller = CodecController(
      adapter: adapter,
      deviceId: 'AA',
      allowChanges: controllerChanges,
      now: () => now?.call() ?? clock,
    );
    await controller.refresh();
    addTearDown(controller.dispose);
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: bdkTheme(Brightness.dark),
        home: RepaintBoundary(
          key: const ValueKey('codec-capture'),
          child: Scaffold(
            appBar: AppBar(title: const Text('Audio quality')),
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: AudioQualityScreen(
                controller: controller,
                allowChanges: allowChanges,
                autoLoad: false,
              ),
            ),
          ),
        ),
      ),
    );
    return (controller, adapter);
  }

  testWidgets(
    'LHDC lower sample rate visibly selects a valid 900 kbps draft before apply',
    (tester) async {
      final (controller, adapter) = await mount(
        tester,
        snapshot: lhdcV5Fixture(),
      );
      controller.selectSampleRate(2);
      await tester.pump();
      await tester.ensureVisible(find.text('Advanced preferences'));
      await tester.tap(find.text('Advanced preferences'));
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('quality-selector'));
      expect(
        find.descendant(of: selector, matching: find.text('900 kbps')),
        findsOneWidget,
      );
      expect(controller.preference!.lhdcV5Quality, LhdcV5Quality.kbps900);
      expect(adapter.writes, isEmpty);
      expect(find.text('Nominal target: 1000 kbps'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'LHDC inconsistent lossless fields never display a fixed current bitrate target',
    (tester) async {
      await mount(
        tester,
        snapshot: lhdcV5Fixture(cs1: 0x8008, cs3: 0x5c000080),
      );
      expect(find.textContaining('Nominal target:'), findsNothing);
      expect(find.textContaining('1000 kbps'), findsNothing);
      expect(
        find.text('Bluetooth bitrate: Not reported by Android.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('current connection is separate from the editable preference', (
    tester,
  ) async {
    final (controller, adapter) = await mount(tester);
    await capture(tester, 'default');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('current-codec'))).data,
      'LDAC',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('codec-selector')));
    await tester.tap(find.byKey(const ValueKey('codec-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AAC').last);
    await tester.pumpAndSettle();
    expect(controller.preference!.codecType, 1);
    expect(controller.preference!.bitsMask, 1);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('current-codec'))).data,
      'LDAC',
    );
    expect(adapter.writes, isEmpty);
  });

  testWidgets(
    'LDAC quality is explicit and never presented as measured bitrate',
    (tester) async {
      await mount(tester);
      expect(find.text('LDAC quality: Adaptive'), findsOneWidget);
      expect(
        find.text('Bluetooth bitrate: Not reported by Android.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Advanced preferences'));
      await tester.tap(find.text('Advanced preferences'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quality-selector')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'advanced options expose reported choices without arbitrary bitrate input',
    (tester) async {
      await mount(tester);
      await tester.ensureVisible(find.text('Advanced preferences'));
      await tester.tap(find.text('Advanced preferences'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rate-selector')), findsOneWidget);
      expect(find.byKey(const ValueKey('depth-selector')), findsOneWidget);
      expect(find.byKey(const ValueKey('channel-selector')), findsOneWidget);
      expect(find.byKey(const ValueKey('quality-selector')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Nominal target: 990 kbps'), findsNothing);
    },
  );

  const allLdacFormats = [
    CodecConfiguration(
      codecType: 4,
      codecName: 'LDAC',
      sampleRateMask: 15,
      bitsMask: 3,
      channelMask: 2,
    ),
  ];
  for (final (rate, targets) in [
    (1, [909, 606, 303]),
    (2, [990, 660, 330]),
    (4, [909, 606, 303]),
    (8, [990, 660, 330]),
  ]) {
    testWidgets(
      'LDAC bitrate choices use the nominal targets for rate mask $rate',
      (tester) async {
        final (controller, adapter) = await mount(
          tester,
          snapshot: codecFixture(
            rate: rate,
            stamp: 100000,
            capabilities: allLdacFormats,
          ),
        );
        await tester.ensureVisible(find.text('Advanced preferences'));
        await tester.tap(find.text('Advanced preferences'));
        await tester.pumpAndSettle();
        expect(find.text('Bitrate / quality'), findsOneWidget);
        expect(find.textContaining('nominal LDAC targets'), findsOneWidget);
        final selector = find.byKey(const ValueKey('quality-selector'));
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        for (final label in [
          '${targets[0]} kbps',
          '${targets[1]} kbps',
          '${targets[2]} kbps',
          'Adaptive',
        ]) {
          expect(find.text(label), findsWidgets);
        }
        await tester.tap(find.text('${targets[1]} kbps').last);
        await tester.pumpAndSettle();
        expect(controller.preference!.ldacQuality, LdacQuality.balanced);
        expect(controller.snapshot!.active!.ldacQuality, LdacQuality.adaptive);
        expect(
          find.text('Bluetooth bitrate: Not reported by Android.'),
          findsOneWidget,
        );
        expect(adapter.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'draft sample rate changes bitrate choices without rewriting the current target',
    (tester) async {
      final (controller, adapter) = await mount(
        tester,
        snapshot: codecFixture(
          qualityCode: 1001,
          stamp: 100000,
          capabilities: allLdacFormats,
        ),
      );
      controller.selectSampleRate(1);
      await tester.pump();
      await tester.ensureVisible(find.text('Advanced preferences'));
      await tester.tap(find.text('Advanced preferences'));
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('quality-selector'));
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text('909 kbps'), findsWidgets);
      expect(find.text('606 kbps'), findsWidgets);
      expect(find.text('303 kbps'), findsWidgets);
      expect(find.text('990 kbps'), findsNothing);
      await tester.tap(find.text('909 kbps').last);
      await tester.pumpAndSettle();
      expect(controller.preference!.sampleRateMask, 1);
      expect(controller.preference!.ldacQuality, LdacQuality.high);
      expect(controller.snapshot!.active!.sampleRateMask, 2);
      expect(find.text('Nominal target: 660 kbps'), findsOneWidget);
      expect(adapter.writes, isEmpty);
    },
  );

  testWidgets('unrecognized LDAC quality does not advertise bitrate choices', (
    tester,
  ) async {
    await mount(
      tester,
      snapshot: codecFixture(qualityCode: 1009, stamp: 100000),
    );
    await tester.ensureVisible(find.text('Advanced preferences'));
    await tester.tap(find.text('Advanced preferences'));
    await tester.pumpAndSettle();
    expect(find.text('Bitrate / quality'), findsNothing);
    expect(find.byKey(const ValueKey('quality-selector')), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('Bluetooth bitrate: Not reported by Android.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'default LDAC shows bitrate choices without preselecting a fixed target',
    (tester) async {
      final (controller, adapter) = await mount(
        tester,
        snapshot: codecFixture(qualityCode: 0, stamp: 100000),
      );
      expect(find.text('LDAC quality: Device default'), findsOneWidget);
      expect(find.textContaining('Nominal target:'), findsNothing);
      expect(controller.preference!.ldacQuality, isNull);
      await tester.ensureVisible(find.text('Advanced preferences'));
      await tester.tap(find.text('Advanced preferences'));
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('quality-selector'));
      expect(selector, findsOneWidget);
      expect(find.text('Device default · Choose a bitrate'), findsOneWidget);
      expect(
        tester
            .widget<DropdownMenuItem<int>>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is DropdownMenuItem<int> && widget.value == 0,
              ),
            )
            .enabled,
        isFalse,
      );
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text('990 kbps'), findsWidgets);
      await tester.tap(find.text('990 kbps').last);
      await tester.pumpAndSettle();
      expect(controller.preference!.ldacQuality, LdacQuality.high);
      expect(controller.snapshot!.active!.cs1, 0);
      expect(find.text('LDAC quality: Device default'), findsOneWidget);
      expect(find.textContaining('Nominal target:'), findsNothing);
      expect(adapter.writes, isEmpty);
    },
  );

  testWidgets(
    'expired quality drafts remain locally editable while current data is stale',
    (tester) async {
      var clock = DateTime.fromMillisecondsSinceEpoch(100000);
      final (controller, adapter) = await mount(tester, now: () => clock);
      controller.selectLdacQuality(LdacQuality.high);
      await tester.ensureVisible(find.text('Advanced preferences'));
      await tester.tap(find.text('Advanced preferences'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quality-selector')), findsOneWidget);
      clock = clock.add(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 5001));
      final selector = find.byKey(const ValueKey('quality-selector'));
      expect(selector, findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.descendant(
                of: selector,
                matching: find.byType(DropdownButtonFormField<int>),
              ),
            )
            .onChanged,
        isNotNull,
      );
      expect(controller.preference!.ldacQuality, LdacQuality.high);
      expect(find.textContaining('out of date'), findsOneWidget);
      controller.selectLdacQuality(LdacQuality.balanced);
      expect(controller.preference!.ldacQuality, LdacQuality.balanced);
      expect(adapter.writes, isEmpty);
      await controller.refresh();
      await tester.pump();
      expect(controller.preference!.ldacQuality, LdacQuality.balanced);
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.descendant(
                of: selector,
                matching: find.byType(DropdownButtonFormField<int>),
              ),
            )
            .onChanged,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'probed LHDC V5 offers requested bitrate targets and keeps current nominal separate',
    (tester) async {
      var clock = DateTime.fromMillisecondsSinceEpoch(100000);
      final (controller, adapter) = await mount(
        tester,
        snapshot: lhdcV5Fixture(),
        now: () => clock,
      );
      expect(find.text('Nominal target: 1000 kbps'), findsOneWidget);
      expect(
        find.text('Bluetooth bitrate: Not reported by Android.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Advanced preferences'));
      await tester.tap(find.text('Advanced preferences'));
      await tester.pumpAndSettle();
      expect(find.text('Bitrate / quality'), findsOneWidget);
      expect(find.textContaining('may clamp or refuse'), findsOneWidget);
      clock = clock.add(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 5001));
      expect(find.textContaining('out of date'), findsOneWidget);
      final selector = find.byKey(const ValueKey('quality-selector'));
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      for (final target in [256, 320, 400, 500, 900, 1000]) {
        expect(find.text('$target kbps'), findsWidgets);
      }
      expect(find.text('192 kbps'), findsNothing);
      expect(find.text('Adaptive'), findsWidgets);
      await tester.tap(find.text('500 kbps').last);
      await tester.pumpAndSettle();
      expect(find.text('Nominal target: 1000 kbps'), findsOneWidget);
      expect(controller.snapshot!.active!.cs1, 0x8008);
      expect(adapter.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('LHDC bitrate chooser remains readable at 280px and 2x text', (
    tester,
  ) async {
    await mount(tester, snapshot: lhdcV5Fixture(), width: 280, scale: 2);
    await tester.ensureVisible(find.text('Advanced preferences'));
    await tester.tap(find.text('Advanced preferences'));
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('quality-selector'));
    expect(selector, findsOneWidget);
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.text('500 kbps'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('500 kbps').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'current telemetry without recognized quality visibly becomes stale',
    (tester) async {
      var clock = DateTime.fromMillisecondsSinceEpoch(100000);
      await mount(
        tester,
        now: () => clock,
        snapshot: codecFixture(qualityCode: 0, stamp: 100000),
      );
      expect(find.textContaining('out of date'), findsNothing);
      clock = clock.add(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 5001));
      expect(find.textContaining('out of date'), findsOneWidget);
      expect(find.byKey(const ValueKey('current-codec')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fixed LDAC current target is labeled nominal and stays separate from a draft',
    (tester) async {
      final (controller, adapter) = await mount(
        tester,
        snapshot: codecFixture(qualityCode: 1001, stamp: 100000),
      );
      expect(find.text('LDAC quality: Balanced'), findsOneWidget);
      expect(find.text('Nominal target: 660 kbps'), findsOneWidget);
      expect(
        find.text('Bluetooth bitrate: Not reported by Android.'),
        findsOneWidget,
      );
      final current = find.ancestor(
        of: find.byKey(const ValueKey('current-codec')),
        matching: find.byType(Card),
      );
      for (final field in ['48 kHz', '24-bit', 'Stereo']) {
        expect(
          find.descendant(of: current, matching: find.text(field)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: current,
          matching: find.text('Source: Android query'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: current,
          matching: find.text('Read within the last 5 seconds'),
        ),
        findsOneWidget,
      );
      controller.selectLdacQuality(LdacQuality.high);
      await tester.pump();
      expect(find.text('LDAC quality: Balanced'), findsOneWidget);
      expect(find.text('Nominal target: 660 kbps'), findsOneWidget);
      expect(find.text('Nominal target: 990 kbps'), findsNothing);
      expect(adapter.writes, isEmpty);
    },
  );

  testWidgets('apply confirmation changes current only after fresh readback', (
    tester,
  ) async {
    final (controller, adapter) = await mount(tester);
    controller.selectSampleRate(8);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('apply-codec')));
    await tester.tap(find.byKey(const ValueKey('apply-codec')));
    await tester.pumpAndSettle();
    expect(controller.phase, CodecOperationPhase.confirmed);
    expect(controller.snapshot!.active!.sampleRateMask, 8);
    expect(find.text('Current connection confirmed.'), findsOneWidget);
    expect(adapter.writes, hasLength(1));
  });

  testWidgets(
    'broadcast current telemetry identifies its source and observation age',
    (tester) async {
      final direct = codecFixture(stamp: 100000);
      await mount(
        tester,
        snapshot: CodecSnapshot(
          access: direct.access,
          devices: direct.devices,
          selectedDeviceId: direct.selectedDeviceId,
          active: direct.active,
          capabilities: direct.capabilities,
          canApply: direct.canApply,
          source: 'broadcast',
          observedAtMs: direct.observedAtMs,
        ),
      );
      expect(find.text('Source: Android broadcast'), findsOneWidget);
      expect(find.text('Read within the last 5 seconds'), findsOneWidget);
      expect(
        find.text('Bluetooth bitrate: Not reported by Android.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'submitted preference stays visibly pending while readback is unavailable',
    (tester) async {
      final (controller, adapter) = await mount(tester);
      final readback = Completer<CodecSnapshot>();
      adapter.onSnapshot = (_) async => adapter.writes.isEmpty
          ? codecFixture(stamp: 100000)
          : await readback.future;
      controller.selectSampleRate(8);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('apply-codec')));
      await tester.tap(find.byKey(const ValueKey('apply-codec')));
      await tester.pump();
      await tester.pump();
      expect(controller.phase, CodecOperationPhase.verifying);
      expect(find.text('Current connection confirmed.'), findsNothing);
      expect(controller.snapshot!.active!.sampleRateMask, 2);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('apply-codec')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      readback.complete(codecFixture(rate: 8, stamp: 100001));
      await tester.pump();
    },
  );

  testWidgets(
    'preview-only screen disables edits and apply even with a writable controller',
    (tester) async {
      final (_, adapter) = await mount(tester, allowChanges: false);
      expect(find.text('Preview only · changes are disabled.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('apply-codec')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('apply-codec')));
      await tester.tap(find.byKey(const ValueKey('apply-codec')));
      await tester.pump();
      expect(adapter.writes, isEmpty);
    },
  );

  testWidgets('unsupported platform has no invented codec selectors', (
    tester,
  ) async {
    await mount(
      tester,
      snapshot: CodecSnapshot(
        access: CodecAccess.unsupportedPlatform,
        reason: 'Managed by this platform.',
      ),
    );
    expect(
      find.text('Audio quality is managed by your device.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('codec-selector')), findsNothing);
    expect(find.byKey(const ValueKey('apply-codec')), findsNothing);
    expect(find.text('Open Bluetooth settings'), findsNothing);
  });

  for (final access in [CodecAccess.apiUnavailable, CodecAccess.error]) {
    testWidgets('${access.name} offers Bluetooth settings recovery', (
      tester,
    ) async {
      final (_, adapter) = await mount(
        tester,
        snapshot: CodecSnapshot(access: access),
      );
      final settings = find.text('Open Bluetooth settings');
      expect(settings, findsOneWidget);
      await tester.ensureVisible(settings);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(adapter.events, contains('settings'));
      expect(adapter.writes, isEmpty);
    });
  }

  testWidgets('read-only telemetry offers Bluetooth settings recovery', (
    tester,
  ) async {
    final (_, adapter) = await mount(
      tester,
      snapshot: codecFixture(writable: false, stamp: 100000),
    );
    final settings = find.text('Open Bluetooth settings');
    expect(settings, findsOneWidget);
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(adapter.events, contains('settings'));
    expect(adapter.writes, isEmpty);
  });

  testWidgets('preview-only restriction recovery cannot open system settings', (
    tester,
  ) async {
    final (_, adapter) = await mount(
      tester,
      allowChanges: false,
      snapshot: CodecSnapshot(access: CodecAccess.apiUnavailable),
    );
    final settings = find.widgetWithText(
      OutlinedButton,
      'Open Bluetooth settings',
    );
    expect(settings, findsOneWidget);
    expect(tester.widget<OutlinedButton>(settings).onPressed, isNull);
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pump();
    expect(adapter.events, isNot(contains('settings')));
  });

  testWidgets('permission recovery invokes only the normal consent action', (
    tester,
  ) async {
    final (_, adapter) = await mount(
      tester,
      snapshot: CodecSnapshot(access: CodecAccess.permissionRequired),
    );
    await tester.tap(find.byKey(const ValueKey('codec-permission')));
    await tester.pumpAndSettle();
    expect(adapter.events, contains('permission'));
    expect(adapter.writes, isEmpty);
  });

  testWidgets('preview-only access screen cannot open permission workflows', (
    tester,
  ) async {
    final (_, adapter) = await mount(
      tester,
      allowChanges: false,
      snapshot: CodecSnapshot(access: CodecAccess.permissionRequired),
    );
    final button = find.byKey(const ValueKey('codec-permission'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(button);
    await tester.pump();
    expect(adapter.events, isNot(contains('permission')));
  });

  testWidgets(
    'association explains API limits and targets the selected audio device',
    (tester) async {
      final (_, adapter) = await mount(
        tester,
        snapshot: CodecSnapshot(
          access: CodecAccess.associationRequired,
          selectedDeviceId: 'AA',
          devices: const [CodecAudioDevice(id: 'AA', name: 'BDK SPEAKER')],
        ),
      );
      expect(find.textContaining('Android may still restrict'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('codec-associate')));
      await tester.pumpAndSettle();
      expect(adapter.events, contains('associate:AA'));
      expect(adapter.writes, isEmpty);
    },
  );

  testWidgets(
    'read-only native telemetry keeps current information without advertising writes',
    (tester) async {
      await mount(
        tester,
        snapshot: codecFixture(writable: false, stamp: 100000),
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('current-codec'))).data,
        'LDAC',
      );
      expect(
        find.text('Your device manages these preferences.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('apply-codec')), findsNothing);
    },
  );

  testWidgets(
    '280px and 2x text keep advanced controls readable and actions at least48px',
    (tester) async {
      await mount(tester, width: 280, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Advanced preferences'));
      await tester.tap(find.text('Advanced preferences'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('channel-selector')),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('apply-codec')));
      expect(
        tester.getSize(find.byKey(const ValueKey('apply-codec'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'large-text');
    },
  );
}
