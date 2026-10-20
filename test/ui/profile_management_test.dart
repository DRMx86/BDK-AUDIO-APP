import 'dart:async';
import 'package:bdk_audio/app.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/sound/widgets/tone_controls.dart';
import 'package:bdk_audio/persistence/profile_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tap(WidgetTester tester, String label) async {
  if (find.text(label).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(label),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(find.text(label).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'rename and delete are available without applying a saved preset',
    (tester) async {
      var data = ProfileData(
        profiles: [SoundProfile('mine', 'Evening', EqGains(2, -1, 3))],
      );
      final store = ProfileStore.fromCallbacks(
        read: () async => data.encode(),
        write: (value) async {
          data = ProfileData.decode(value);
        },
      );
      await tester.pumpWidget(
        BdkApp(
          initialDemoMode: true,
          previewOnly: true,
          initialProfiles: data,
          store: store,
        ),
      );
      await tap(tester, 'Saved presets');
      await tester.tap(find.byTooltip('Manage preset Evening'));
      await tester.pumpAndSettle();
      await tap(tester, 'Rename');
      await tester.enterText(find.byType(TextField), 'Night');
      await tap(tester, 'Save');
      expect(data.profiles.single.name, 'Night');
      await tester.tap(find.byTooltip('Manage preset Night'));
      await tester.pumpAndSettle();
      await tap(tester, 'Delete');
      await tap(tester, 'Delete preset');
      expect(data.profiles, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Balanced'), findsWidgets);
    },
  );
  testWidgets('a failed profile deletion keeps the saved data and card', (
    tester,
  ) async {
    final data = ProfileData(
      profiles: [SoundProfile('mine', 'Evening', EqGains(2, -1, 3))],
    );
    final store = ProfileStore.fromCallbacks(
      read: () async => data.encode(),
      write: (_) async => throw StateError('disk full'),
    );
    await tester.pumpWidget(
      BdkApp(
        initialDemoMode: true,
        previewOnly: true,
        initialProfiles: data,
        store: store,
      ),
    );
    await tap(tester, 'Saved presets');
    await tester.tap(find.byTooltip('Manage preset Evening'));
    await tester.pumpAndSettle();
    await tap(tester, 'Delete');
    await tap(tester, 'Delete preset');
    expect(find.text('Evening'), findsOneWidget);
  });
  testWidgets(
    'replace captures current gains and deleting it keeps the sound',
    (tester) async {
      var data = ProfileData(
        profiles: [SoundProfile('mine', 'Evening', EqGains(2, -1, 3))],
      );
      final store = ProfileStore.fromCallbacks(
        read: () async => data.encode(),
        write: (value) async => data = ProfileData.decode(value),
      );
      await tester.pumpWidget(
        BdkApp(
          initialDemoMode: true,
          previewOnly: true,
          initialProfiles: data,
          store: store,
        ),
      );
      await tap(tester, 'Equalizer');
      await tester.ensureVisible(find.byTooltip('Increase Bass'));
      await tester.tap(find.byTooltip('Increase Bass'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, 'Saved presets');
      await tester.tap(find.byTooltip('Manage preset Evening'));
      await tester.pumpAndSettle();
      await tap(tester, 'Use current sound');
      await tap(tester, 'Replace preset');
      expect(data.profiles.single.id, 'mine');
      expect(data.profiles.single.gains.values, [1, 0, 0]);
      await tap(tester, 'Evening');
      await tap(tester, 'Saved presets');
      await tester.tap(find.byTooltip('Manage preset Evening'));
      await tester.pumpAndSettle();
      await tap(tester, 'Delete');
      await tap(tester, 'Delete preset');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, 'Equalizer');
      expect(tester.widget<ToneControls>(find.byType(ToneControls)).levels, [
        1,
        0,
        0,
      ]);
      expect(data.profiles, isEmpty);
    },
  );
  testWidgets('saved preset management fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      BdkApp(
        initialDemoMode: true,
        previewOnly: true,
        initialProfiles: ProfileData(
          profiles: [SoundProfile('mine', 'Evening sound', EqGains(2, -1, 3))],
        ),
      ),
    );
    await tap(tester, 'Saved presets');
    await tester.tap(find.byTooltip('Manage preset Evening sound'));
    await tester.pumpAndSettle();
    await tap(tester, 'Rename');
    await tester.enterText(find.byType(TextField), 'Night sound');
    await tap(tester, 'Save');
    expect(find.text('Night sound'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('queued replacement saves the sound at confirmation', (
    tester,
  ) async {
    var data = ProfileData(
      profiles: [
        SoundProfile('mine', 'Evening', EqGains(2, -1, 3)),
        SoundProfile('other', 'Other', EqGains(1, 1, 1)),
      ],
    );
    final release = Completer<void>();
    var writes = 0;
    final store = ProfileStore.fromCallbacks(
      read: () async => data.encode(),
      write: (raw) async {
        if (++writes == 1) await release.future;
        data = ProfileData.decode(raw);
      },
    );
    await tester.pumpWidget(
      BdkApp(
        initialDemoMode: true,
        previewOnly: true,
        initialProfiles: data,
        store: store,
      ),
    );
    await tap(tester, 'Saved presets');
    await tester.tap(find.byTooltip('Manage preset Other'));
    await tester.pumpAndSettle();
    await tap(tester, 'Rename');
    await tester.enterText(find.byType(TextField), 'Other renamed');
    await tap(tester, 'Save');
    expect(writes, 1);
    await tester.tap(find.byTooltip('Manage preset Evening'));
    await tester.pumpAndSettle();
    await tap(tester, 'Use current sound');
    await tap(tester, 'Replace preset');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, 'Deep Bass');
    release.complete();
    await tester.pumpAndSettle();
    expect(data.profiles.first.gains.values, [0, 0, 0]);
  });
  testWidgets(
    'replacement finishing rechecks selected identity against gains',
    (tester) async {
      var data = ProfileData(
        profiles: [SoundProfile('mine', 'Evening', EqGains(2, -1, 3))],
      );
      final release = Completer<void>();
      final store = ProfileStore.fromCallbacks(
        read: () async => data.encode(),
        write: (raw) async {
          await release.future;
          data = ProfileData.decode(raw);
        },
      );
      await tester.pumpWidget(
        BdkApp(
          initialDemoMode: true,
          previewOnly: true,
          initialProfiles: data,
          store: store,
        ),
      );
      await tap(tester, 'Saved presets');
      await tester.tap(find.byTooltip('Manage preset Evening'));
      await tester.pumpAndSettle();
      await tap(tester, 'Use current sound');
      await tap(tester, 'Replace preset');
      await tap(tester, 'Evening');
      await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('Evening'), findsOneWidget);
      release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Custom sound'), findsOneWidget);
      await tap(tester, 'Equalizer');
      expect(tester.widget<ToneControls>(find.byType(ToneControls)).levels, [
        2,
        -1,
        3,
      ]);
      expect(data.profiles.single.gains.values, [0, 0, 0]);
    },
  );
  testWidgets('preset name controller survives a long dialog exit animation', (
    tester,
  ) async {
    timeDilation = 10;
    addTearDown(() => timeDilation = 1);
    await tester.pumpWidget(
      const BdkApp(initialDemoMode: true, previewOnly: true),
    );
    await tap(tester, 'Equalizer');
    await tap(tester, 'Save preset');
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    await tester.enterText(find.byType(TextField), 'Slow close');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsOneWidget);
    void listener() {}
    expect(() => controller.addListener(listener), returnsNormally);
    controller.removeListener(listener);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    timeDilation = 1;
  });
  testWidgets(
    'new preset finishing after route exit keeps the newer sound selected',
    (tester) async {
      var data = const ProfileData();
      final release = Completer<void>();
      final store = ProfileStore.fromCallbacks(
        read: () async => data.encode(),
        write: (raw) async {
          await release.future;
          data = ProfileData.decode(raw);
        },
      );
      await tester.pumpWidget(
        BdkApp(initialDemoMode: true, previewOnly: true, store: store),
      );
      await tap(tester, 'Equalizer');
      await tap(tester, 'Save preset');
      await tester.enterText(find.byType(TextField), 'Queued save');
      await tap(tester, 'Save');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, 'Deep Bass');
      await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
      await tester.pumpAndSettle();
      release.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Queued save'), findsNothing);
      expect(find.text('Deep Bass'), findsWidgets);
      expect(data.profiles.single.gains.values, [0, 0, 0]);
    },
  );
  testWidgets('managed preset cards keep room for names on a regular phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      BdkApp(
        initialDemoMode: true,
        previewOnly: true,
        initialProfiles: ProfileData(
          profiles: [SoundProfile('mine', 'Evening sound', EqGains(2, -1, 3))],
        ),
      ),
    );
    await tap(tester, 'Saved presets');
    final card = find.ancestor(
      of: find.text('Evening sound'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(card.first).width, greaterThan(300));
  });
}
