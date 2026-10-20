import 'dart:convert';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/imports/bounded_file_picker.dart';
import 'package:bdk_audio/features/updates/firmware_image.dart';
import 'package:bdk_audio/features/updates/firmware_update_screen.dart';
import 'package:bdk_audio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../ota_transfer_fixture.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool encrypted = false,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = encrypted
        ? base64Decode(otaEncryptedFixtureBase64)
        : otaImageBytes();
    final picker = BoundedFilePicker(
      picker: (_) async => SelectedImportFile(
        name: encrypted ? 'Local.enc' : 'Local.bin',
        length: bytes.length,
        openStream: () => Stream.value(bytes),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: bdkTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('Firmware update')),
          body: FirmwareUpdateScreen(
            picker: picker,
            speaker: const SpeakerState(),
            allowChanges: false,
            decode: (file, key) async => FirmwareImage.parse(
              file.bytes,
              encrypted: file.name.endsWith('.enc'),
              legacyAesKey: key,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> tap(WidgetTester tester, String text) async {
    if (find.text(text).evaluate().isEmpty) {
      await tester.scrollUntilVisible(find.text(text), 250);
    }
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'local image checks do not imply installed or authenticated firmware',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Choose update file');
      expect(find.text('File checks passed'), findsOneWidget);
      expect(find.text('2.4.0'), findsOneWidget);
      expect(find.text('Update installed'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Install update'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'encrypted import requires an explicit key and never invents a default',
    (tester) async {
      await mount(tester, encrypted: true);
      await tap(tester, 'Choose update file');
      expect(find.text('File checks passed'), findsNothing);
      await tap(tester, 'Unlock file');
      expect(
        find.text('Enter a 64-character hexadecimal key.'),
        findsOneWidget,
      );
      final key = List.generate(
        32,
        (i) => i.toRadixString(16).padLeft(2, '0'),
      ).join();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('firmware-aes-key')))
            .obscureText,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('firmware-aes-key')),
        key,
      );
      await tap(tester, 'Unlock file');
      expect(find.text('File checks passed'), findsOneWidget);
      expect(find.byKey(const ValueKey('firmware-aes-key')), findsNothing);
    },
  );
  testWidgets('local update preview fits a narrow phone at large text size', (
    tester,
  ) async {
    await mount(tester, width: 280, scale: 2);
    await tap(tester, 'Choose update file');
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Install update'), 250);
    expect(tester.takeException(), isNull);
  });
}
