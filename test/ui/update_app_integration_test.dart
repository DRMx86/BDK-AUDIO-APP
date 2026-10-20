import 'dart:async';
import 'package:bdk_audio/app.dart';
import 'package:bdk_audio/features/imports/bounded_file_picker.dart';
import 'package:bdk_audio/features/updates/firmware_update_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../ota_transfer_fixture.dart';
import '../ota_transfer_test_support.dart';

void main() {
  testWidgets(
    'receipt survives leaving update and verifies only after reconnect',
    (tester) async {
      // This test follows receipt ownership across routes. Pairing motion is
      // covered separately; reduced motion lets route transitions settle here.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final rig = OtaTestRig();
      await rig.connect();
      rig.respondTransfer();
      addTearDown(rig.close);
      final bytes = otaImageBytes();
      final picker = BoundedFilePicker(
        picker: (_) async => SelectedImportFile(
          name: 'Fixture.bin',
          length: bytes.length,
          openStream: () => Stream.value(bytes),
        ),
      );
      await tester.pumpWidget(
        BdkApp(session: rig.session, updateFilePicker: picker),
      );
      Future<void> tap(String label) async {
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
        final target = find.text(label).last;
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pump();
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (find.text('Reading file…').evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();
      }

      await tap('Speaker');
      await tap('Firmware update');
      await tap('Choose update file');
      await tap('Install update');
      await tap('Install update');
      expect(find.text('Transfer confirmed'), findsOneWidget);
      expect(find.text('Reported version matches'), findsNothing);
      await tap('Reconnect speaker');
      await tester.pumpAndSettle();
      expect(find.byType(FirmwareUpdateScreen), findsNothing);
      expect(find.text('Transfer confirmed'), findsNothing);
      await tester.runAsync(rig.session.disconnect);
      await tester.pumpAndSettle();
      await tester.runAsync(() => rig.reconnect());
      await tester.pumpAndSettle();
      await tap('Firmware update');
      expect(find.text('Transfer confirmed'), findsOneWidget);
      await tap('Check reported version');
      expect(find.text('Reported version matches'), findsOneWidget);
      expect(rig.link.writes.map((p) => p.first), [0xf0]);
      expect(tester.takeException(), isNull);
    },
  );
}
