import 'package:bdk_audio/features/sound/widgets/sound_options_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    int initial,
    ValueChanged<int> changed, {
    double width = 600,
    double scale = 1,
  }) async {
    var flags = initial;
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
                    builder: (context, setState) => SoundOptionsPanel(
                      controlFlags: flags,
                      onChanged: (value) {
                        changed(value);
                        setState(() => flags = value);
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

  testWidgets('bass boost changes only bit 0x01 preserving unknown flags', (
    tester,
  ) async {
    int? received;
    await mount(tester, 0x82, (v) => received = v);
    await tester.tap(find.byKey(const ValueKey('bass-boost')));
    await tester.pump();
    expect(received, 0x83);
    await tester.tap(find.byKey(const ValueKey('bass-boost')));
    await tester.pump();
    expect(received, 0x82);
  });

  testWidgets(
    'full-range changes bit 0x04 and keeps boost and remembered output swap',
    (tester) async {
      int? received;
      await mount(tester, 0x83, (v) => received = v);
      await tester.tap(find.byKey(const ValueKey('full-range')));
      await tester.pump();
      expect(received, 0x87);
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('output-swap')))
            .onChanged,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('bass-boost')));
      await tester.pump();
      expect(received, 0x86);
      await tester.tap(find.byKey(const ValueKey('full-range')));
      await tester.pump();
      expect(received, 0x82);
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('output-swap')))
            .onChanged,
        isNotNull,
      );
    },
  );

  testWidgets(
    'swap assigns high frequencies to left and low to right using bit 0x02',
    (tester) async {
      int? received;
      await mount(tester, 0, (v) => received = v);
      expect(find.text('Left · Low'), findsOneWidget);
      expect(find.text('Right · High'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('output-swap')));
      await tester.pump();
      expect(received, 0x02);
      expect(find.text('Left · High'), findsOneWidget);
      expect(find.text('Right · Low'), findsOneWidget);
    },
  );

  testWidgets(
    'full-range shows stereo routing and cannot toggle crossover output swap',
    (tester) async {
      int? received;
      await mount(tester, 0x04, (v) => received = v);
      expect(find.text('Left · Full range'), findsOneWidget);
      expect(find.text('Right · Full range'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('output-swap')));
      await tester.pump();
      expect(received, isNull);
      expect(find.textContaining('Equalizer stays active'), findsOneWidget);
      expect(find.textContaining('Bypass equalizer'), findsNothing);
    },
  );

  testWidgets('narrow and enlarged text options do not overflow', (
    tester,
  ) async {
    await mount(tester, 7, (_) {}, width: 280, scale: 2);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('output-swap')));
    expect(tester.takeException(), isNull);
  });
}
