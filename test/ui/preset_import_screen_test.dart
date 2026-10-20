import 'dart:async';
import 'dart:convert';
import 'package:bdk_audio/features/imports/bounded_file_picker.dart';
import 'package:bdk_audio/features/presets/preset_import.dart';
import 'package:bdk_audio/features/presets/preset_import_screen.dart';
import 'package:bdk_audio/persistence/profile_store.dart';
import 'package:bdk_audio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = SelectedImportFile(
    name: 'Old presets.xml',
    openStream: () => Stream.value(
      utf8.encode(
        '<map><int name="custom_1_bass" value="80"/><int name="custom_2_bass" value="20"/></map>',
      ),
    ),
  );
  Future<void> mount(
    WidgetTester tester, {
    Future<PresetMerge> Function(List<SoundProfile>)? commit,
    Future<SelectedImportFile?> Function(List<String>)? pick,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          appBar: AppBar(title: const Text('Import presets')),
          body: PresetImportScreen(
            picker: BoundedFilePicker(picker: pick ?? (_) async => file),
            decode: (f) async => PresetImport.parse(f.bytes),
            onImport:
                commit ??
                (values) async =>
                    PresetImport.merge(const ProfileData(), values),
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

  testWidgets('selection previews presets and commits only the chosen values', (
    tester,
  ) async {
    List<SoundProfile>? saved;
    await mount(
      tester,
      commit: (values) async {
        saved = values;
        return PresetImport.merge(const ProfileData(), values);
      },
    );
    await tap(tester, 'Choose preset file');
    expect(find.text('Custom 1'), findsOneWidget);
    expect(find.text('Custom 2'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pumpAndSettle();
    await tap(tester, 'Import 1 preset');
    expect(saved!.single.name, 'Custom 1');
    expect(find.text('Added 1 preset'), findsOneWidget);
  });
  testWidgets(
    'failed persistence keeps the preview and does not claim success',
    (tester) async {
      await mount(tester, commit: (_) async => throw StateError('disk full'));
      await tap(tester, 'Choose preset file');
      await tap(tester, 'Import 2 presets');
      expect(find.text('Added 2 presets'), findsNothing);
      expect(
        find.text('Your presets could not be saved. Try again.'),
        findsOneWidget,
      );
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
    },
  );
  testWidgets('late picker completion after leaving does not commit anything', (
    tester,
  ) async {
    final gate = Completer<SelectedImportFile?>();
    var saved = false;
    await mount(
      tester,
      pick: (_) => gate.future,
      commit: (values) async {
        saved = true;
        return PresetImport.merge(const ProfileData(), values);
      },
    );
    await tester.tap(find.text('Choose preset file'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete(file);
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('preview and actions fit narrow screens at twice text size', (
    tester,
  ) async {
    await mount(tester, width: 280, scale: 2);
    await tap(tester, 'Choose preset file');
    expect(tester.takeException(), isNull);
    await tap(tester, 'Import 2 presets');
    expect(find.text('Added 2 presets'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
