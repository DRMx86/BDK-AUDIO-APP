import 'dart:convert';
import 'package:bdk_audio/app.dart';
import 'package:bdk_audio/features/imports/bounded_file_picker.dart';
import 'package:bdk_audio/persistence/profile_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('imports into the library only after successful persistence', (
    tester,
  ) async {
    String? raw;
    final store = ProfileStore.fromCallbacks(
      read: () async => raw,
      write: (value) async {
        raw = value;
      },
    );
    final picker = BoundedFilePicker(
      picker: (_) async => SelectedImportFile(
        name: 'Android presets.json',
        openStream: () => Stream.value(
          utf8.encode(
            jsonEncode({
              'version': 1,
              'format': 'bdk-android-prefs',
              'preferences': {
                'custom_1_name': 'Old evening',
                'custom_1_bass': 75,
              },
            }),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      BdkApp(
        initialDemoMode: true,
        previewOnly: true,
        store: store,
        presetFilePicker: picker,
      ),
    );
    Future<void> tap(String text) async {
      if (find.text(text).evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.text(text),
          150,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await tester.pump();
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
    }

    await tap('Saved presets');
    await tap('Import presets');
    await tap('Choose preset file');
    expect(find.text('Old evening'), findsOneWidget);
    expect(raw, isNull);
    await tap('Import 1 preset');
    expect(ProfileData.decode(raw!).profiles.single.name, 'Old evening');
    await tap('Done');
    expect(find.text('Old evening'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Balanced'), findsWidgets);
    expect(find.text('1 personal profiles'), findsOneWidget);
  });
}
