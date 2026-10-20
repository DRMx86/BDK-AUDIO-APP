import 'dart:ui' show SemanticsAction;

import 'package:bdk_audio/features/sound/widgets/tone_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    List<int> initial = const [0, 0, 0],
    ToneControlStyle style = ToneControlStyle.pillars,
    ValueChanged<List<int>>? changed,
    double width = 600,
    double scale = 1,
  }) async {
    var levels = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: StatefulBuilder(
                    builder: (context, setState) => ToneControls(
                      levels: levels,
                      style: style,
                      onChanged: (value) {
                        changed?.call(value);
                        setState(() => levels = value);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final style in ToneControlStyle.values) {
    testWidgets(
      '${style.name}: narrow cards keep labels beside the control to reduce scrolling',
      (tester) async {
        await mount(tester, width: 280, style: style);
        expect(
          tester.getSize(find.byKey(const ValueKey('tone-band-0'))).height,
          lessThan(220),
        );
      },
    );
    testWidgets(
      '${style.name}: changes only the selected level without mutating input',
      (tester) async {
        final input = [3, -2, 5];
        List<int>? received;
        await mount(
          tester,
          initial: input,
          style: style,
          changed: (v) => received = v,
        );
        await tester.tap(find.byTooltip('Increase Mid'));
        await tester.pump();
        expect(received, [3, -1, 5]);
        expect(input, [3, -2, 5]);
        expect(find.text('150 Hz'), findsOneWidget);
        expect(find.text('1 kHz'), findsOneWidget);
        expect(find.text('6 kHz'), findsOneWidget);
        expect(find.textContaining('dB'), findsNothing);
      },
    );

    testWidgets('${style.name}: keyboard steps, endpoints and clamping', (
      tester,
    ) async {
      List<int>? received;
      await mount(tester, style: style, changed: (v) => received = v);
      await tester.tap(find.byKey(const ValueKey('tone-control-0')));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(received, [12, 0, 0]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(received, [12, 0, 0]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(received, [11, 0, 0]);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(received, [-12, 0, 0]);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pump();
      expect(received, [-9, 0, 0]);
    });

    testWidgets(
      '${style.name}: drag is bounded and independent of other bands',
      (tester) async {
        List<int>? received;
        await mount(
          tester,
          initial: const [0, 2, -4],
          style: style,
          changed: (v) => received = v,
        );
        final control = find.byKey(const ValueKey('tone-control-0'));
        await tester.drag(control, const Offset(0, -300));
        await tester.pump();
        expect(received, [12, 2, -4]);
        await tester.drag(control, const Offset(0, 600));
        await tester.pump();
        expect(received, [-12, 2, -4]);
      },
    );

    testWidgets('${style.name}: 280 px and large text stays usable', (
      tester,
    ) async {
      await mount(tester, style: style, width: 280, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Increase Treble'));
      await tester.tap(find.byTooltip('Increase Treble'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final button = tester.getSize(find.byTooltip('Increase Treble'));
      expect(button.width, greaterThanOrEqualTo(48));
      expect(button.height, greaterThanOrEqualTo(48));
    });
  }

  testWidgets('screen reader can increment the named band', (tester) async {
    final semantics = tester.ensureSemantics();
    List<int>? received;
    await mount(tester, changed: (v) => received = v);
    final node = tester.getSemantics(
      find.byKey(const ValueKey('tone-semantics-1')),
    );
    expect(node.label, 'Mid, 1 kHz');
    expect(node.value, '0, level');
    tester
        .renderObject(find.byKey(const ValueKey('tone-semantics-1')))
        .owner!
        .semanticsOwner!
        .performAction(node.id, SemanticsAction.increase);
    await tester.pump();
    expect(received, [0, 1, 0]);
    semantics.dispose();
  });

  testWidgets('out of range incoming values cannot escape on editing', (
    tester,
  ) async {
    List<int>? received;
    await mount(
      tester,
      initial: const [99, -99, 2],
      changed: (v) => received = v,
    );
    await tester.tap(find.byTooltip('Increase Treble'));
    await tester.pump();
    expect(received, [12, -12, 3]);
  });
}
