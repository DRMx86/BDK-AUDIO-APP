import 'package:bdk_audio/app.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../session_test.dart' as fixtures;

void main() {
  for (final galleryOff in [false, true]) {
    testWidgets('${galleryOff ? 'Gallery Off' : 'Power off'} retains Ambient '
        'and brightness after leaving the Light tab', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const BdkApp(initialDemoMode: true));
      Future<void> tab(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
      }

      await tab('Light');
      final brightness = find.byKey(const ValueKey('brightness'));
      tester.widget<Slider>(brightness).onChanged!(37);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('quick-21')));
      await tester.tap(find.byKey(const ValueKey('quick-21')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Light'));
      await tester.pumpAndSettle();
      if (galleryOff) {
        await tester.ensureVisible(find.text('Choose an effect'));
        await tester.tap(find.text('Choose an effect'));
        await tester.pumpAndSettle();
        final off = find.byKey(const ValueKey('effect-255'));
        await tester.ensureVisible(off);
        await tester.tap(off);
      } else {
        await tester.ensureVisible(find.byKey(const ValueKey('lights-power')));
        await tester.tap(find.byKey(const ValueKey('lights-power')));
      }
      await tester.pumpAndSettle();
      await tab('Sound');
      await tab('Light');
      final power = find.byKey(const ValueKey('lights-power'));
      await tester.ensureVisible(power);
      await tester.tap(power);
      await tester.pumpAndSettle();
      final settings = tester
          .widget<LightScreen>(find.byType(LightScreen))
          .settings;
      expect(settings.effect, 21);
      expect(settings.brightness, 37);
      expect(settings.color1, 0x74d9ff);
      expect(settings.color2, 0xbc9aff);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('off-screen status is remembered only for the same speaker', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transport = fixtures.FakeTransport();
    final first = fixtures.FakeLink('first');
    final second = fixtures.FakeLink('second');
    transport.links.addAll([first, second]);
    first.onWrite = (_) => first.status(fixtures.fullStatus);
    second.onWrite = (_) => second.status(
      List<int>.of(fixtures.fullStatus)
        ..[5] = 255
        ..[6] = 0,
    );
    final session = SpeakerSession(transport);
    addTearDown(() async {
      session.dispose();
      await transport.close();
    });
    await session.connect('first');
    await tester.pumpWidget(BdkApp(session: session, previewOnly: true));
    // Valid Ambient and then Off arrive while Sound is visible, before a frame.
    first.status([5, 21, 37, 50, 0x74, 0xd9, 255, 0xbc, 0x9a, 255, 1]);
    first.status([5, 255, 0, 50, 0x74, 0xd9, 255, 0xbc, 0x9a, 255, 1]);
    Future<void> tab(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> powerOn() async {
      final power = find.byKey(const ValueKey('lights-power'));
      await tester.ensureVisible(power);
      await tester.tap(power);
      await tester.pumpAndSettle();
    }

    await tab('Light');
    await powerOn();
    var settings = tester
        .widget<LightScreen>(find.byType(LightScreen))
        .settings;
    expect(settings.effect, 21);
    expect(settings.brightness, 37);
    await tab('Sound');
    first.onWrite = (_) => first.status(
      List<int>.of(fixtures.fullStatus)
        ..[5] = 255
        ..[6] = 0,
    );
    await tester.runAsync(session.disconnect);
    await tester.runAsync(() => session.connect('first'));
    await tester.pumpAndSettle();
    await tab('Light');
    await powerOn();
    settings = tester.widget<LightScreen>(find.byType(LightScreen)).settings;
    expect(
      settings.effect,
      21,
      reason: 'Same-speaker reconnect retains history.',
    );
    expect(settings.brightness, 37);
    await tab('Sound');
    await tester.runAsync(() => session.connect('second'));
    await tester.pumpAndSettle();
    await tab('Light');
    await powerOn();
    settings = tester.widget<LightScreen>(find.byType(LightScreen)).settings;
    expect(settings.effect, 0);
    expect(settings.brightness, 70);
    expect(first.writes, [
      [0xf0],
      [0xf0],
    ]);
    expect(second.writes, [
      [0xf0],
    ]);
    await tester.pumpWidget(const SizedBox());
  });
}
