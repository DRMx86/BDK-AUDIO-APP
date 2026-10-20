import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:bdk_audio/theme.dart';
import 'package:bdk_led_engine/bdk_led_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Frames implements LightFrameRenderer {
  final additional = <_Frames>[];
  final configurations = <List<int>>[];
  final demos = <bool>[];
  final audioInputs = <List<double>?>[];
  final beatInputs = <bool>[];
  final activeInputs = <bool>[];
  int disposed = 0;

  @override
  void configure(List<int> payload) => configurations.add(List.of(payload));

  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) {
    demos.add(demo);
    audioInputs.add(audio == null ? null : List<double>.of(audio));
    beatInputs.add(beat);
    activeInputs.add(audioActive);
    final frame = Uint8List(1024);
    for (var pixel = 0; pixel < 256; pixel++) {
      frame[pixel * 4] = demos.length % 256;
      frame[pixel * 4 + 1] = 220;
      frame[pixel * 4 + 2] = 40;
      frame[pixel * 4 + 3] = 255;
    }
    return frame;
  }

  @override
  void dispose() => disposed++;
}

class _ActualFirmwareFrames implements LightFrameRenderer {
  final _engine = NativeLedEngine(
    library: DynamicLibrary.open(
      '${Directory.current.path}/build/native_renderer/Release/bdk_led_engine.dll',
    ),
  );
  @override
  void configure(List<int> payload) => _engine.configure(payload);
  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) => _engine.render(
    demo: demo,
    audio: audio,
    beat: beat,
    audioActive: audioActive,
  );
  @override
  void dispose() => _engine.dispose();
}

void main() {
  const initial = LedSettings(
    effect: 0,
    brightness: 70,
    speed: 50,
    color1: 0x65D9F4,
    color2: 0xBCABFF,
    gradient: 1,
  );

  Future<_Frames> mount(
    WidgetTester tester, {
    LedSettings settings = initial,
    ValueChanged<LedSettings>? changed,
    MeterLevels? meter,
    bool connected = false,
    List<double>? previewAudio,
    bool previewBeat = false,
    bool previewAudioActive = false,
    bool reduceMotion = false,
    double width = 600,
    double scale = 1,
  }) async {
    var current = settings;
    final frames = _Frames();
    var mainCreated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: MediaQuery(
                data: MediaQueryData(
                  disableAnimations: reduceMotion,
                  textScaler: TextScaler.linear(scale),
                ),
                child: StatefulBuilder(
                  builder: (context, setState) => LightScreen(
                    settings: current,
                    onChanged: (value) {
                      changed?.call(value);
                      setState(() => current = value);
                    },
                    meter: meter,
                    connected: connected,
                    previewAudio: previewAudio,
                    previewBeat: previewBeat,
                    previewAudioActive: previewAudioActive,
                    rendererFactory: () {
                      if (!mainCreated) {
                        mainCreated = true;
                        return frames;
                      }
                      final next = _Frames();
                      frames.additional.add(next);
                      return next;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return frames;
  }

  Future<void> decode(WidgetTester tester) async {
    // A settings change may discard an older decode and request the latest one.
    // Give both native image callbacks a turn without settling an active ticker.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
  }

  testWidgets('paused preview ignores incoming meter redraws until Play', (
    tester,
  ) async {
    final frames = _Frames();
    final meter = ValueNotifier(MeterLevels(100, 50, 25, DateTime.now()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: ValueListenableBuilder(
              valueListenable: meter,
              builder: (context, value, _) => LightScreen(
                settings: initial,
                onChanged: (_) {},
                connected: true,
                meter: value,
                previewAudio: const [.5, .3, .2, -18, -24, -30, .7],
                previewAudioActive: true,
                rendererFactory: () => frames,
              ),
            ),
          ),
        ),
      ),
    );
    await decode(tester);
    final before = frames.demos.length;
    meter.value = MeterLevels(90, 60, 40, DateTime.now());
    await tester.pump();
    await decode(tester);
    expect(frames.demos.length, before);
    await tester.tap(find.byTooltip('Play preview'));
    await tester.pump();
    await decode(tester);
    expect(frames.demos.length, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    await decode(tester);
    meter.dispose();
  });

  testWidgets(
    'one received meter beat is consumed once across multiple render ticks',
    (tester) async {
      final frames = await mount(
        tester,
        connected: true,
        meter: MeterLevels(100, 50, 25, DateTime.now()),
        previewAudio: const [.5, .3, .2, -18, -24, -30, .7],
        previewBeat: true,
        previewAudioActive: true,
      );
      await decode(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await decode(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await decode(tester);
      expect(frames.beatInputs.where((value) => value), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
  );

  testWidgets(
    'connected preview forwards the supplied audio estimate into the native source effect',
    (tester) async {
      final frames = await mount(
        tester,
        connected: true,
        reduceMotion: true,
        meter: MeterLevels(100, 50, 25, DateTime.now()),
        previewAudio: const [.5, .3, .2, -18, -24, -30, .7],
        previewBeat: true,
        previewAudioActive: true,
      );
      await decode(tester);
      expect(find.text('Audio-reactive preview · estimated'), findsOneWidget);
      expect(frames.demos, everyElement(isFalse));
      expect(frames.audioInputs.first, [.5, .3, .2, -18, -24, -30, .7]);
      expect(frames.beatInputs.first, isTrue);
      expect(frames.activeInputs.first, isTrue);
      expect(find.textContaining('mirror'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
  );

  testWidgets('stale meters supply silence without substituting a demo', (
    tester,
  ) async {
    final frames = await mount(
      tester,
      connected: true,
      reduceMotion: true,
      meter: MeterLevels(
        100,
        50,
        25,
        DateTime.now().subtract(const Duration(seconds: 2)),
      ),
      previewAudio: const [.5, .3, .2, -18, -24, -30, .7],
      previewBeat: true,
      previewAudioActive: true,
    );
    await decode(tester);
    expect(
      find.text('Audio-reactive preview · waiting for audio levels'),
      findsOneWidget,
    );
    expect(frames.demos, everyElement(isFalse));
    expect(frames.audioInputs.first, [0, 0, 0, -60, -60, -60, 0]);
    expect(frames.beatInputs.first, isFalse);
    expect(frames.activeInputs.first, isFalse);
    await tester.pumpWidget(const SizedBox());
    await decode(tester);
  });

  testWidgets(
    'capture actual firmware artwork with purposeful effect symbols',
    (tester) async {
      for (final family in ['Manrope', 'SpaceGrotesk']) {
        await (FontLoader(
          family,
        )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: bdkTheme(Brightness.dark),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('native-light-capture'),
              child: Material(
                color: bdkTheme(Brightness.dark).colorScheme.surface,
                child: MediaQuery(
                  data: const MediaQueryData(disableAnimations: true),
                  child: LightScreen(
                    settings: initial.copyWith(effect: 21),
                    onChanged: (_) {},
                    rendererFactory: _ActualFirmwareFrames.new,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await decode(tester);
      Future<void> snapshot(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('native-light-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${Directory.systemTemp.path}/bdk-light-native-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await snapshot('selected');
      await tester.ensureVisible(find.text('Choose an effect'));
      await tester.tap(find.text('Choose an effect'));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await decode(tester);
        if (find
                .byWidgetPredicate(
                  (widget) =>
                      widget is CustomPaint &&
                      widget.painter is FirmwareLightPainter &&
                      (widget.painter! as FirmwareLightPainter).image != null,
                )
                .evaluate()
                .length ==
            22) {
          break;
        }
      }
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter is FirmwareLightPainter &&
              (widget.painter! as FirmwareLightPainter).image != null,
        ),
        findsNWidgets(22),
      );
      await snapshot('gallery');
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
    skip:
        !const bool.fromEnvironment('BDK_CAPTURE_LIGHT') || !Platform.isWindows,
  );

  test(
    'diffuse artwork preserves a square source within a rectangular tile',
    () {
      expect(
        FirmwareLightPainter.containedRect(const Size(300, 160)),
        const Rect.fromLTWH(70, 0, 160, 160),
      );
      expect(
        FirmwareLightPainter.coverRect(const Size(300, 160)),
        const Rect.fromLTWH(0, -70, 300, 300),
      );
    },
  );

  testWidgets(
    'gallery caches all 22 square source frames and disposes images and its temporary renderer',
    (tester) async {
      final frames = await mount(tester, reduceMotion: true);
      await tester.ensureVisible(find.text('Choose an effect'));
      await tester.tap(find.text('Choose an effect'));
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await decode(tester);
        if (find
                .byWidgetPredicate(
                  (widget) =>
                      widget is CustomPaint &&
                      widget.painter is FirmwareLightPainter &&
                      (widget.painter! as FirmwareLightPainter).image != null,
                )
                .evaluate()
                .length ==
            22) {
          break;
        }
      }
      final paints = tester.widgetList<CustomPaint>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is FirmwareLightPainter,
        ),
      );
      final images = paints
          .map((paint) => (paint.painter! as FirmwareLightPainter).image!)
          .toList();
      expect(images.length, 22);
      expect(
        images.every((image) => image.width == 16 && image.height == 16),
        isTrue,
      );
      expect(frames.additional, hasLength(1));
      expect(frames.additional.single.disposed, 1);
      final samples = frames.additional.single.demos.length;
      expect(samples, lessThanOrEqualTo(22 * 72));
      await tester.tap(find.text('Light').first);
      await tester.pump();
      await tester.ensureVisible(find.text('Choose an effect'));
      await tester.tap(find.text('Choose an effect'));
      await tester.pump();
      expect(frames.additional, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
      expect(images.every((image) => image.debugDisposed), isTrue);
      expect(frames.disposed, 1);
    },
  );

  testWidgets(
    'unavailable native renderer reports a preview failure instead of inventing light output',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LightScreen(
              settings: initial,
              onChanged: (_) {},
              rendererFactory: () => throw StateError('Renderer unavailable'),
            ),
          ),
        ),
      );
      expect(
        find.text('Firmware preview unavailable on this device'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('led-core')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'preview and brightness announce their action and value to screen readers',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, reduceMotion: true);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('preview-playback')))
            .label,
        'Play preview',
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('preview-playback')))
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('brightness')));
      await tester.pump();
      final brightness = tester.getSemantics(
        find.byKey(const ValueKey('brightness')),
      );
      expect(brightness.getSemanticsData().label, 'Brightness');
      expect(brightness.getSemanticsData().value, '70 percent');
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
  );

  testWidgets(
    'first Light visit renders effect zero and continues without a switch',
    (tester) async {
      final frames = await mount(tester);
      await decode(tester);
      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('led-core')),
      );
      final image = (paint.painter! as FirmwareLightPainter).image!;
      expect(image.width, 16);
      expect(image.height, 16);
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      expect(bytes!.getUint8(1), 220);
      expect(bytes.getUint8(3), 255);
      final first = frames.demos.length;
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));
      expect(frames.demos.length, greaterThan(first));
      expect(find.text('Preview · firmware demo'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('led-artwork')),
          matching: find.byTooltip('Pause preview'),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
      expect(frames.disposed, 1);
    },
  );

  testWidgets(
    'gallery exposes all 22 names and changes the native configuration',
    (tester) async {
      final frames = await mount(tester);
      await tester.ensureVisible(find.text('Choose an effect'));
      await tester.tap(find.text('Choose an effect'));
      await tester.pump();
      expect(find.byKey(const ValueKey('effect-0')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('effect-21')),
        300,
      );
      expect(find.byKey(const ValueKey('effect-21')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('effect-2')),
        -300,
      );
      await tester.tap(find.byKey(const ValueKey('effect-2')));
      await tester.pump();
      await decode(tester);
      expect(find.text('Ripple'), findsWidgets);
      expect(frames.configurations.last.first, 2);
      expect(find.byKey(const ValueKey('led-core')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
  );

  for (final route in ['quick', 'gallery']) {
    testWidgets(
      'Ambient via $route immediately exposes the same color and movement controls',
      (tester) async {
        LedSettings? received;
        await mount(tester, changed: (v) => received = v);
        if (route == 'gallery') {
          await tester.ensureVisible(find.text('Choose an effect'));
          await tester.tap(find.text('Choose an effect'));
          await tester.pump();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('effect-21')),
            300,
          );
          await tester.tap(find.byKey(const ValueKey('effect-21')));
        } else {
          await tester.ensureVisible(find.byKey(const ValueKey('quick-21')));
          await tester.tap(find.byKey(const ValueKey('quick-21')));
        }
        await tester.pump();
        expect(received?.effect, 21);
        expect(find.text('Ambient colors'), findsOneWidget);
        expect(find.text('Primary color'), findsOneWidget);
        expect(find.text('Secondary color'), findsOneWidget);
        expect(find.text('Color blend'), findsOneWidget);
        expect(find.text('Movement speed'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('primary-color')));
        await tester.tap(find.byKey(const ValueKey('primary-color')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('color-4584FF')));
        await tester.tap(find.text('Use color'));
        await tester.pump();
        expect(received?.color1, 0x4584FF);
        await tester.pumpWidget(const SizedBox());
        await decode(tester);
      },
    );
  }

  testWidgets(
    'Off remembers brightness and restores it without changing effect or colors',
    (tester) async {
      LedSettings? received;
      await mount(tester, changed: (v) => received = v);
      await tester.ensureVisible(find.byKey(const ValueKey('lights-power')));
      await tester.tap(find.byKey(const ValueKey('lights-power')));
      await tester.pump();
      expect(received?.brightness, 0);
      await tester.tap(find.byKey(const ValueKey('lights-power')));
      await tester.pump();
      expect(received?.brightness, 70);
      expect(received?.effect, 0);
      expect(received?.color1, 0x65D9F4);
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
  );

  testWidgets('persisted Off opens safely and power restores a usable effect', (
    tester,
  ) async {
    LedSettings? received;
    await mount(
      tester,
      settings: initial.copyWith(effect: 255),
      changed: (value) => received = value,
    );
    await decode(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Off'), findsWidgets);
    final power = find.byKey(const ValueKey('lights-power'));
    expect(tester.widget<Switch>(power).value, isFalse);
    expect(
      tester.widget<Slider>(find.byKey(const ValueKey('brightness'))).value,
      0,
    );
    await tester.ensureVisible(power);
    await tester.tap(power);
    await tester.pump();
    expect(received, initial);
    await tester.pumpWidget(const SizedBox());
    await decode(tester);
  });

  testWidgets(
    'gallery Off preserves Ambient for power restore and brightness activation',
    (tester) async {
      LedSettings? received;
      await mount(
        tester,
        settings: initial.copyWith(effect: 21, brightness: 37),
        changed: (value) => received = value,
        reduceMotion: true,
      );
      Future<void> selectOff() async {
        await tester.ensureVisible(find.text('Choose an effect'));
        await tester.tap(find.text('Choose an effect'));
        await tester.pumpAndSettle();
        final off = find.byKey(const ValueKey('effect-255'));
        expect(off, findsOneWidget);
        await tester.ensureVisible(off);
        await tester.tap(off);
        await tester.pumpAndSettle();
      }

      await selectOff();
      expect(received, initial.copyWith(effect: 21, brightness: 0));
      final power = find.byKey(const ValueKey('lights-power'));
      expect(tester.widget<Switch>(power).value, isFalse);
      await tester.ensureVisible(power);
      await tester.tap(power);
      await tester.pumpAndSettle();
      expect(received, initial.copyWith(effect: 21, brightness: 37));
      await selectOff();
      final brightness = find.byKey(const ValueKey('brightness'));
      tester.widget<Slider>(brightness).onChanged!(62);
      await tester.pumpAndSettle();
      expect(received, initial.copyWith(effect: 21, brightness: 62));
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
  );

  testWidgets(
    'color picker suspends background rendering and resumes on close',
    (tester) async {
      final frames = await mount(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('quick-21')));
      await tester.tap(find.byKey(const ValueKey('quick-21')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('primary-color')));
      await tester.tap(find.byKey(const ValueKey('primary-color')));
      await tester.pump(const Duration(milliseconds: 300));
      await decode(tester);
      final before = frames.demos.length;
      await tester.pump(const Duration(milliseconds: 100));
      await decode(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(frames.demos.length, before);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      await decode(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(frames.demos.length, greaterThan(before));
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
  );

  testWidgets('fresh meter expires even while motion is paused', (
    tester,
  ) async {
    await mount(
      tester,
      connected: true,
      reduceMotion: true,
      meter: MeterLevels(100, 50, 0, DateTime.now()),
    );
    await tester.ensureVisible(find.text('Audio activity'));
    await tester.tap(find.text('Audio activity'));
    await tester.pump();
    expect(find.text('Received from speaker'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Waiting for fresh audio levels'), findsOneWidget);
    expect(find.text('−30 dB'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await decode(tester);
  });

  testWidgets(
    'brightness changes use direct percentages and zero restores the latest nonzero level',
    (tester) async {
      LedSettings? received;
      await mount(tester, changed: (v) => received = v, reduceMotion: true);
      final slider = find.byKey(const ValueKey('brightness'));
      await tester.ensureVisible(slider);
      tester.widget<Slider>(slider).onChanged!(37);
      await tester.pump();
      expect(received?.brightness, 37);
      expect(received?.color2, 0xBCABFF);
      tester.widget<Slider>(slider).onChanged!(0);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('lights-power')));
      await tester.tap(find.byKey(const ValueKey('lights-power')));
      await tester.pump();
      expect(received?.brightness, 37);
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
  );

  testWidgets('Ambient speed and gradient preserve colors and brightness', (
    tester,
  ) async {
    LedSettings? received;
    await mount(tester, changed: (v) => received = v, reduceMotion: true);
    await tester.ensureVisible(find.byKey(const ValueKey('quick-21')));
    await tester.tap(find.byKey(const ValueKey('quick-21')));
    await tester.pump();
    final speed = find.byKey(const ValueKey('speed'));
    await tester.ensureVisible(speed);
    tester.widget<Slider>(speed).onChanged!(85);
    await tester.pump();
    expect(received?.speed, 85);
    expect(received?.brightness, 70);
    expect(received?.color1, 0x65D9F4);
    await tester.ensureVisible(find.byKey(const ValueKey('gradient-1')));
    await tester.tap(find.byKey(const ValueKey('gradient-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Radial').last);
    await tester.pumpAndSettle();
    expect(received?.gradient, 3);
    expect(received?.color2, 0xBCABFF);
    expect(received?.speed, 85);
    await tester.pumpWidget(const SizedBox());
    await decode(tester);
  });

  testWidgets('background suspends frame production and resume restarts it', (
    tester,
  ) async {
    final frames = await mount(tester);
    await decode(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = frames.demos.length;
    await tester.pump(const Duration(milliseconds: 300));
    await decode(tester);
    expect(frames.demos.length, paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(frames.demos.length, greaterThan(paused));
    await tester.pumpWidget(const SizedBox());
    await decode(tester);
  });

  testWidgets(
    'same-effect quick selection continues playback without reconfiguring renderer',
    (tester) async {
      final frames = await mount(tester);
      await decode(tester);
      final configurations = frames.configurations.length;
      await tester.ensureVisible(find.byKey(const ValueKey('quick-0')));
      await tester.tap(find.byKey(const ValueKey('quick-0')));
      await tester.pump();
      final before = frames.demos.length;
      await tester.pump(const Duration(milliseconds: 100));
      await decode(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(frames.configurations.length, configurations);
      expect(frames.demos.length, greaterThan(before));
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
  );

  testWidgets(
    'received meters show nonnegative 0–100 percent levels at 30/60/100Hz',
    (tester) async {
      final frames = await mount(
        tester,
        connected: true,
        meter: MeterLevels(100, 50, 0, DateTime.now()),
      );
      await tester.ensureVisible(find.text('Audio activity'));
      await tester.tap(find.text('Audio activity'));
      await tester.pump();
      expect(find.text('30 Hz'), findsOneWidget);
      expect(find.text('60 Hz'), findsOneWidget);
      expect(find.text('100 Hz'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('Level · 0–100%'), findsOneWidget);
      expect(find.textContaining('dB'), findsNothing);
      expect(
        find.text('Audio-reactive preview · waiting for audio levels'),
        findsOneWidget,
      );
      expect(find.textContaining('Live mirror'), findsNothing);
      expect(frames.demos, everyElement(isFalse));
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
  );

  testWidgets('old audio meter data is visibly stale', (tester) async {
    await mount(
      tester,
      connected: true,
      meter: MeterLevels(
        90,
        60,
        30,
        DateTime.now().subtract(const Duration(seconds: 3)),
      ),
    );
    await tester.ensureVisible(find.text('Audio activity'));
    await tester.tap(find.text('Audio activity'));
    await tester.pump();
    expect(find.text('Waiting for fresh audio levels'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await decode(tester);
  });

  testWidgets('reduced motion starts paused and explicit Play animates', (
    tester,
  ) async {
    final frames = await mount(tester, reduceMotion: true);
    await decode(tester);
    expect(find.byTooltip('Play preview'), findsOneWidget);
    final first = frames.demos.length;
    await tester.pump(const Duration(milliseconds: 200));
    expect(frames.demos.length, first);
    await tester.tap(find.byTooltip('Play preview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(frames.demos.length, greaterThan(first));
    await tester.pumpWidget(const SizedBox());
    await decode(tester);
    expect(frames.disposed, 1);
  });

  testWidgets(
    '320px and enlarged text keeps Light and Ambient controls inside layout',
    (tester) async {
      await mount(tester, width: 280, scale: 2, reduceMotion: true);
      await decode(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byTooltip('Play preview')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('quick-21')));
      await tester.tap(find.byKey(const ValueKey('quick-21')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('secondary-color')));
      await tester.tap(find.byKey(const ValueKey('secondary-color')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('color-4584FF')));
      await tester.tap(find.byKey(const ValueKey('color-4584FF')));
      await tester.tap(find.text('Use color'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await decode(tester);
    },
  );
}
