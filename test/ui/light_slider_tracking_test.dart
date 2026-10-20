import 'dart:typed_data';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:bdk_audio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Frames implements LightFrameRenderer {
  @override
  void configure(List<int> payload) {}
  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) => Uint8List(1024);
  @override
  void dispose() {}
}

class _Thumb extends RoundSliderThumbShape {
  Offset? center;
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    this.center = parentBox.localToGlobal(center);
    super.paint(
      context,
      center,
      activationAnimation: activationAnimation,
      enableAnimation: enableAnimation,
      isDiscrete: isDiscrete,
      labelPainter: labelPainter,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      textDirection: textDirection,
      value: value,
      textScaleFactor: textScaleFactor,
      sizeWithOverflow: sizeWithOverflow,
    );
  }
}

void main() {
  testWidgets('brightness thumb tracks a held pointer on the next paint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final thumb = _Thumb();
    final theme = bdkTheme(Brightness.dark);
    var settings = const LedSettings(brightness: 70);
    final emitted = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          sliderTheme: theme.sliderTheme.copyWith(thumbShape: thumb),
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => LightScreen(
              settings: settings,
              rendererFactory: _Frames.new,
              onChanged: (value) {
                emitted.add(value.brightness);
                update(() => settings = value);
              },
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump();
    final slider = find.byKey(const ValueKey('brightness'));
    await tester.ensureVisible(slider);
    await tester.pump(const Duration(milliseconds: 200));
    expect(thumb.center, isNotNull);
    expect(
      tester.getRect(slider).contains(thumb.center!),
      isTrue,
      reason: 'The recorded thumb must use actual screen coordinates.',
    );
    final gesture = await tester.startGesture(thumb.center!);
    await tester.pump(const Duration(milliseconds: 150));
    final target = thumb.center! - const Offset(70, 0);
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 8));
    expect(emitted, isNotEmpty);
    expect(
      emitted.last,
      lessThan(60),
      reason: 'The real drag must reach the control.',
    );
    expect(
      (thumb.center!.dx - target.dx).abs(),
      lessThanOrEqualTo(2),
      reason:
          'Measure actual painted thumb position while the pointer '
          'is still down, rather than after the easing animation settles.',
    );
    expect(emitted.last, inInclusiveRange(0, 100));
    expect(find.text('${emitted.last}%'), findsOneWidget);
    await gesture.up();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  });
}
