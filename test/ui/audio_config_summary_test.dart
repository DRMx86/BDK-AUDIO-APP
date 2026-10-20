import 'package:bdk_audio/features/codec/audio_config_summary.dart';
import 'package:bdk_audio/features/codec/audio_config_summary_controller.dart';
import 'package:bdk_audio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../audio_config_summary_controller_test.dart' show summaryFixture;
import '../codec_test_support.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'audio summary stays compact and tappable at 280px and scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(280, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final adapter = FakeCodecAdapter()
          ..onSnapshot = (_) async => summaryFixture();
        final controller = AudioConfigSummaryController(
          adapter: adapter,
          now: () => DateTime.fromMillisecondsSinceEpoch(100000),
        );
        addTearDown(controller.dispose);
        controller.configure(deviceId: 'AA', active: true);
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: bdkTheme(Brightness.dark),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: AudioConfigSummary(
                    controller: controller,
                    onTap: () => taps++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final summary = find.byKey(const ValueKey('audio-config-summary'));
        expect(summary, findsOneWidget);
        expect(find.text('LDAC · 96 kHz · 32-bit · 990 kbps'), findsOneWidget);
        expect(tester.getSize(summary).height, greaterThanOrEqualTo(48));
        if (scale == 1) {
          expect(tester.getSize(summary).height, lessThanOrEqualTo(64));
        }
        expect(tester.takeException(), isNull);
        await tester.tap(summary);
        expect(taps, 1);
        expect(adapter.writes, isEmpty);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await tester.pump();
      },
    );
  }
}
