import 'dart:async';

import 'package:bdk_audio/features/startup/bdk_startup_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = _RasterGateBinding();

  testWidgets('two-second visible hold begins only after first raster', (
    tester,
  ) async {
    binding.firstRaster = Completer<void>();
    var loads = 0;
    var mounts = 0;
    await tester.pumpWidget(
      BdkStartupApp(
        loadApplication: () async {
          loads++;
          return _ReadyApp(onMount: () => mounts++);
        },
      ),
    );
    await tester.pump();
    expect(loads, 1); // Initialization still runs in parallel with raster work.
    await tester.pump(const Duration(seconds: 3));
    expect(mounts, 0);
    expect(find.text('BDK AUDIO'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);

    binding.firstRaster.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1800));
    expect(mounts, 0);
    expect(find.text('BDK AUDIO'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(mounts, 1);
    expect(find.text('Actual discovery'), findsOneWidget);
    expect(find.byKey(const ValueKey('bdk-brand-reveal')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 716));
    await tester.pump();
    expect(find.byKey(const ValueKey('bdk-brand-reveal')), findsNothing);
    expect(mounts, 1);
  });

  testWidgets('reduced-motion dwell also starts at first raster', (
    tester,
  ) async {
    binding.firstRaster = Completer<void>();
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      BdkStartupApp(
        loadApplication: () async =>
            const MaterialApp(home: Text('Actual discovery')),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Actual discovery'), findsNothing);
    expect(find.text('BDK AUDIO'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    binding.firstRaster.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 149));
    expect(find.text('Actual discovery'), findsNothing);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(find.text('Actual discovery'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('disposing before first raster ignores its late completion', (
    tester,
  ) async {
    binding.firstRaster = Completer<void>();
    await tester.pumpWidget(
      BdkStartupApp(
        loadApplication: () async => const MaterialApp(home: Text('Late app')),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    binding.firstRaster.complete();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Late app'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error retry cannot mount the app before first raster', (
    tester,
  ) async {
    binding.firstRaster = Completer<void>();
    var loads = 0;
    await tester.pumpWidget(
      BdkStartupApp(
        loadApplication: () async {
          loads++;
          if (loads == 1) throw StateError('unavailable');
          return const MaterialApp(home: Text('Actual discovery'));
        },
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Unable to start'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(loads, 2);
    expect(find.text('Actual discovery'), findsNothing);
    binding.firstRaster.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 716));
    await tester.pump();
    expect(find.text('Actual discovery'), findsOneWidget);
    expect(find.byKey(const ValueKey('bdk-brand-reveal')), findsNothing);
  });
}

class _RasterGateBinding extends AutomatedTestWidgetsFlutterBinding {
  late Completer<void> firstRaster;

  @override
  Future<void> get waitUntilFirstFrameRasterized => firstRaster.future;
}

class _ReadyApp extends StatefulWidget {
  const _ReadyApp({required this.onMount});
  final VoidCallback onMount;

  @override
  State<_ReadyApp> createState() => _ReadyAppState();
}

class _ReadyAppState extends State<_ReadyApp> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Text('Actual discovery'));
}
