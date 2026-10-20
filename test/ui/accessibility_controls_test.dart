import 'dart:ui' show SemanticsAction, SemanticsActionEvent, Tristate;

import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:bdk_audio/features/sound/widgets/tone_controls.dart';
import 'package:bdk_audio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Only pixels cross this boundary. The real LightScreen owns every interaction
// under test; this avoids loading native libraries or connecting to a speaker.
class _BlankFrames implements LightFrameRenderer {
  @override
  void configure(List<int> payload) {}

  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) => Uint8List(16 * 16 * 4);

  @override
  void dispose() {}
}

const _initialLight = LedSettings(
  effect: 0,
  brightness: 70,
  speed: 50,
  color1: 0x65D9F4,
  color2: 0xBCABFF,
  gradient: 1,
);

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double width = 600,
  double scale = 1,
}) async {
  tester.view.reset();
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: bdkTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

Future<void> _light(
  WidgetTester tester, {
  double width = 600,
  double scale = 1,
  ValueChanged<LedSettings>? changed,
}) async {
  var settings = _initialLight;
  await _mount(
    tester,
    StatefulBuilder(
      builder: (context, setState) => LightScreen(
        settings: settings,
        rendererFactory: _BlankFrames.new,
        onChanged: (value) {
          changed?.call(value);
          setState(() => settings = value);
        },
      ),
    ),
    width: width,
    scale: scale,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    // Give the outstanding image decode a turn after its owning page disposes.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  });
}

void _adjust(WidgetTester tester, Finder finder, SemanticsAction action) {
  final node = tester.getSemantics(finder);
  tester.binding.performSemanticsAction(
    SemanticsActionEvent(
      type: action,
      viewId: tester.view.viewId,
      nodeId: node.id,
    ),
  );
}

Future<void> _guidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

Future<void> _focusByTab(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  for (var step = 0; step < 32; step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (tester
            .getSemantics(target)
            .getSemanticsData()
            .flagsCollection
            .isFocused ==
        Tristate.isTrue) {
      return;
    }
  }
  fail('The named control could not be reached using Tab.');
}

void _testAccessible(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      semantics.dispose();
    }
  });
}

void main() {
  _testAccessible(
    'RGB adjustments expose channel names and commit only that color',
    (tester) async {
      LedSettings? changed;
      await _light(tester, changed: (value) => changed = value);
      await tester.ensureVisible(find.byKey(const ValueKey('quick-21')));
      await tester.tap(find.byKey(const ValueKey('quick-21')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('primary-color')));
      await tester.tap(find.byKey(const ValueKey('primary-color')));
      await tester.pumpAndSettle();

      final sliders = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Slider),
      );
      for (final (index, channel) in ['Red', 'Green', 'Blue'].indexed) {
        final slider = sliders.at(index);
        await tester.ensureVisible(slider);
        final node = tester.getSemantics(slider);
        expect(node.label, contains(channel));
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.increase),
          isTrue,
        );
        _adjust(tester, slider, SemanticsAction.increase);
        await tester.pump();
      }
      await tester.tap(find.text('Use color'));
      await tester.pumpAndSettle();
      expect(changed?.color1, 0x66DAF5);
      expect(changed?.color2, 0xBCABFF);
      expect(changed?.brightness, 70);
    },
  );

  _testAccessible(
    'gallery announces the selected effect and selection updates it',
    (tester) async {
      LedSettings? changed;
      await _light(tester, changed: (value) => changed = value);
      await tester.ensureVisible(find.text('Choose an effect'));
      await tester.tap(find.text('Choose an effect'));
      await tester.pumpAndSettle();
      final selected = find.byKey(const ValueKey('effect-0'));
      final ripple = find.byKey(const ValueKey('effect-2'));
      expect(tester.getSemantics(selected).label, contains('Spectrum Bars'));
      expect(
        tester.getSemantics(selected).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(ripple).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      await tester.ensureVisible(ripple);
      _adjust(tester, ripple, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(changed?.effect, 2);
      await tester.ensureVisible(find.text('Choose an effect'));
      await tester.tap(find.text('Choose an effect'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(ripple);
      expect(tester.getSemantics(ripple).label, contains('Ripple'));
      expect(
        tester.getSemantics(ripple).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(selected).flagsCollection.isSelected,
        Tristate.isFalse,
      );
    },
  );

  _testAccessible('gallery selection is reachable using Tab and Enter', (
    tester,
  ) async {
    LedSettings? changed;
    await _light(tester, changed: (value) => changed = value);
    await tester.ensureVisible(find.text('Choose an effect'));
    await tester.tap(find.text('Choose an effect'));
    await tester.pumpAndSettle();
    final ripple = find.byKey(const ValueKey('effect-2'));
    await _focusByTab(tester, ripple);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changed?.effect, 2);
    expect(find.byKey(const ValueKey('led-artwork')), findsOneWidget);
  });

  _testAccessible(
    'named light sliders support semantic and keyboard adjustments',
    (tester) async {
      LedSettings? changed;
      await _light(tester, changed: (value) => changed = value);
      final brightness = find.byKey(const ValueKey('brightness'));
      await tester.ensureVisible(brightness);
      expect(tester.getSemantics(brightness).label, contains('Brightness'));
      expect(
        tester.getSemantics(brightness).getSemanticsData().value,
        '70 percent',
      );
      _adjust(tester, brightness, SemanticsAction.increase);
      await tester.pump();
      expect(changed?.brightness, 71);
      _adjust(tester, brightness, SemanticsAction.decrease);
      await tester.pump();
      expect(changed?.brightness, 70);
      await _focusByTab(tester, brightness);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(changed?.brightness, 71);

      await tester.ensureVisible(find.byKey(const ValueKey('quick-21')));
      await tester.tap(find.byKey(const ValueKey('quick-21')));
      await tester.pumpAndSettle();
      final speed = find.byKey(const ValueKey('speed'));
      await tester.ensureVisible(speed);
      expect(tester.getSemantics(speed).label, contains('Movement speed'));
      _adjust(tester, speed, SemanticsAction.decrease);
      await tester.pump();
      expect(changed?.speed, 49);
      await _focusByTab(tester, speed);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(changed?.speed, 50);
      expect(changed?.brightness, 71);
      expect(changed?.color1, 0x65D9F4);
      expect(changed?.color2, 0xBCABFF);
    },
  );

  _testAccessible(
    'tone pillars expose a focusable slider with bounded adjust actions',
    (tester) async {
      var levels = [11, -12, 0];
      await _mount(
        tester,
        SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => ToneControls(
              levels: levels,
              onChanged: (value) => setState(() => levels = value),
            ),
          ),
        ),
      );
      final bass = find.byKey(const ValueKey('tone-semantics-0'));
      final mid = find.byKey(const ValueKey('tone-semantics-1'));
      var node = tester.getSemantics(bass);
      expect(node.flagsCollection.isSlider, isTrue);
      expect(node.flagsCollection.isFocused, isNot(Tristate.none));
      _adjust(tester, bass, SemanticsAction.increase);
      await tester.pump();
      expect(levels, [12, -12, 0]);
      node = tester.getSemantics(bass);
      expect(node.value, '+12, level');
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isFalse,
      );
      expect(
        tester
            .getSemantics(mid)
            .getSemanticsData()
            .hasAction(SemanticsAction.decrease),
        isFalse,
      );
      _adjust(tester, bass, SemanticsAction.decrease);
      await tester.pump();
      expect(levels, [11, -12, 0]);

      // Traverse from outside using Tab, without a pointer establishing focus.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        tester.getSemantics(bass).flagsCollection.isFocused,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(levels, [10, -12, 0]);

      // Assistive technologies can request input focus independently of Tab.
      // Subsequent keyboard input must adjust the requested band, not the old one.
      expect(
        tester
            .getSemantics(mid)
            .getSemanticsData()
            .hasAction(SemanticsAction.focus),
        isTrue,
      );
      _adjust(tester, mid, SemanticsAction.focus);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(levels, [10, -11, 0]);
    },
  );

  for (final (width, scale) in [(600.0, 1.0), (320.0, 1.0), (320.0, 2.0)]) {
    _testAccessible(
      'light touch targets and names at $width px / ${scale}x text',
      (tester) async {
        await _light(tester, width: width, scale: scale);
        await _guidelines(tester);
        await tester.ensureVisible(find.byKey(const ValueKey('quick-21')));
        await _guidelines(tester);
        await tester.tap(find.byKey(const ValueKey('quick-21')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('primary-color')));
        await _guidelines(tester);
        await tester.tap(find.byKey(const ValueKey('primary-color')));
        await tester.pumpAndSettle();
        await _guidelines(tester);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(TextButton, 'Light'));
        await tester.tap(find.widgetWithText(TextButton, 'Light'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Choose an effect'));
        await tester.tap(find.text('Choose an effect'));
        await tester.pumpAndSettle();
        // Visit every gallery item, including below the fold, so guideline checks
        // cannot silently skip a small or unnamed target further down the page.
        for (var effect = 0; effect < 22; effect++) {
          final tile = find.byKey(ValueKey('effect-$effect'));
          await tester.ensureVisible(tile);
          await _guidelines(tester);
        }
        expect(tester.takeException(), isNull);
      },
    );

    _testAccessible(
      'tone step targets and names at $width px / ${scale}x text',
      (tester) async {
        var levels = [0, 0, 0];
        await _mount(
          tester,
          SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => ToneControls(
                levels: levels,
                onChanged: (value) => setState(() => levels = value),
              ),
            ),
          ),
          width: width,
          scale: scale,
        );
        for (final band in ['Bass', 'Mid', 'Treble']) {
          final increase = find.byTooltip('Increase $band');
          await tester.ensureVisible(increase);
          await _guidelines(tester);
          await tester.tap(increase);
          await tester.pump();
        }
        expect(levels, [1, 1, 1]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
