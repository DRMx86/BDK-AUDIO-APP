import 'package:bdk_audio/app.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/features/pairing/speaker_pairing_screen.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../session_test.dart' as fixtures;

void main() {
  testWidgets('motion preference changes retain connected Light state', (
    tester,
  ) async {
    final transport = fixtures.FakeTransport();
    final link = fixtures.FakeLink('speaker');
    transport.links.add(link);
    link.onWrite = (_) => link.status(fixtures.fullStatus);
    final session = SpeakerSession(transport);
    await session.connect('speaker');
    addTearDown(() async {
      session.dispose();
      await transport.close();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });
    await tester.pumpWidget(BdkApp(session: session));
    await tester.pump(const Duration(milliseconds: 320));
    await tester.tap(find.text('Light').last);
    await tester.pump();
    final lightState = tester.state(find.byType(LightScreen));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    expect(tester.state(find.byType(LightScreen)), same(lightState));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: false);
    await tester.pump();
    expect(tester.state(find.byType(LightScreen)), same(lightState));
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('connected-controls-reveal')),
          )
          .opacity,
      1,
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final reduced in [false, true]) {
    testWidgets(
      'connected controls reveal immediately, reduced motion $reduced',
      (tester) async {
        final transport = fixtures.FakeTransport();
        final link = fixtures.FakeLink('speaker');
        transport.links.add(link);
        link.onWrite = (_) => link.status(fixtures.fullStatus);
        final session = SpeakerSession(transport);
        addTearDown(() async {
          session.dispose();
          await transport.close();
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
        });
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        await tester.pumpWidget(BdkApp(session: session));
        expect(find.byType(SpeakerPairingScreen), findsOneWidget);
        await session.connect('speaker');
        await tester.pump();
        expect(find.byType(SpeakerPairingScreen), findsNothing);
        expect(find.text('Choose preset'), findsOneWidget);
        final reveal = find.byKey(const ValueKey('connected-controls-reveal'));
        if (reduced) {
          expect(reveal, findsOneWidget);
          expect(tester.widget<Opacity>(reveal).opacity, 1);
        } else {
          expect(reveal, findsOneWidget);
          final first = tester.widget<Opacity>(reveal).opacity;
          expect(first, lessThan(1));
          await tester.pump(const Duration(milliseconds: 140));
          expect(tester.widget<Opacity>(reveal).opacity, greaterThan(first));
          await tester.pump(const Duration(milliseconds: 180));
          expect(tester.widget<Opacity>(reveal).opacity, 1);
          // An ordinary status update must not replay the handoff animation.
          link.status(fixtures.fullStatus);
          await tester.pump();
          expect(tester.widget<Opacity>(reveal).opacity, 1);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
