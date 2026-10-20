import 'dart:async';
import 'package:bdk_audio/app.dart';
import 'package:bdk_audio/features/app_info/app_info_screen.dart';
import 'package:bdk_audio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(rootBundle.clear);
  testWidgets('notices remain readable when package metadata fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppInfoScreen(
            loadPackageInfo: () =>
                Future.error(PlatformException(code: 'unavailable')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Licenses and notices'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Licenses and notices'), 150);
    await tester.ensureVisible(find.text('Licenses and notices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Licenses and notices'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('BDK Audio'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Manrope'), 200);
    await tester.tap(find.text('Manrope'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Copyright 2018 The Manrope'), findsWidgets);
    expect(find.textContaining('SIL OPEN FONT LICENSE'), findsWidgets);
    await tester.scrollUntilVisible(
      find.textContaining('Copyright 2019 The Manrope'),
      400,
    );
    expect(find.textContaining('Copyright 2019 The Manrope'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native decoder notice is available from App info', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: bdkTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: AppInfoScreen(
              loadPackageInfo: () async => PackageInfo(
                appName: 'BDK Audio',
                packageName: 'com.bdkaudio.controller',
                version: '3.2.1',
                buildNumber: '67',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Licenses and notices'), 150);
    await tester.ensureVisible(find.text('Licenses and notices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Licenses and notices'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('miniaudio'), 250);
    await tester.tap(find.text('miniaudio'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('David Reid'), 200);
    expect(find.textContaining('David Reid'), findsWidgets);
    await tester.scrollUntilVisible(
      find.textContaining('MIT No Attribution'),
      200,
    );
    expect(find.textContaining('MIT No Attribution'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'metadata failure never substitutes a project or default version',
    (tester) async {
      final metadata = Completer<PackageInfo>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppInfoScreen(loadPackageInfo: () => metadata.future),
          ),
        ),
      );
      expect(find.text('Reading app version…'), findsOneWidget);
      metadata.completeError(PlatformException(code: 'unavailable'));
      await tester.pumpAndSettle();

      expect(find.text('App version unavailable'), findsOneWidget);
      expect(find.text('Reading app version…'), findsNothing);
      expect(find.textContaining(RegExp(r'Version \d')), findsNothing);
      expect(find.textContaining(RegExp(r'Build \d')), findsNothing);
      expect(find.text('WillyBilly'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Speaker App info shows the installed version and build', (
    tester,
  ) async {
    const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method != 'getAll') throw MissingPluginException();
      return {
        'appName': 'BDK Audio',
        'packageName': 'com.bdkaudio.controller',
        'version': '7.8.9',
        'buildNumber': '123',
        'buildSignature': '',
        'installerStore': null,
        'installTime': null,
        'updateTime': null,
      };
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(const BdkApp(initialDemoMode: true));
    await tester.tap(find.text('Speaker').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('App info'),
      160,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(find.text('App info'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('App info'));
    await tester.pumpAndSettle();

    expect(find.text('Version 7.8.9'), findsOneWidget);
    expect(find.text('Build 123'), findsOneWidget);
    expect(find.text('BDK Audio'), findsOneWidget);
    expect(find.textContaining('Bluetooth DSP controller'), findsOneWidget);
    expect(find.text('WillyBilly'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Version 7.8.9'), findsNothing);
    expect(find.text('App info'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing version fields are reported independently', (
    tester,
  ) async {
    for (final fields in [
      ('  ', '45', 'Version unavailable', 'Build 45'),
      ('2.3.4', '', 'Version 2.3.4', 'Build unavailable'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppInfoScreen(
              key: ValueKey(fields),
              loadPackageInfo: () async => PackageInfo(
                appName: 'BDK Audio',
                packageName: 'com.bdkaudio.controller',
                version: fields.$1,
                buildNumber: fields.$2,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(fields.$3), findsOneWidget);
      expect(find.text(fields.$4), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('App info supports large text in ${brightness.name} theme', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: bdkTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: AppInfoScreen(
                loadPackageInfo: () async => PackageInfo(
                  appName: 'BDK Audio',
                  packageName: 'com.bdkaudio.controller',
                  version: '3.2.1',
                  buildNumber: '67',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Version 3.2.1'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('WillyBilly'), 120);
      await tester.ensureVisible(find.text('WillyBilly'));
      await tester.pumpAndSettle();
      expect(find.text('WillyBilly').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
