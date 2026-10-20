import 'dart:async';

import 'package:bdk_audio/features/startup/bdk_startup_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _RasterReadyBinding();
  testWidgets('brand stays visible for two seconds before mounting ready app', (
    tester,
  ) async {
    var mountedApplications = 0;
    var loads = 0;
    await tester.pumpWidget(
      BdkStartupApp(
        loadApplication: () async {
          loads++;
          return _ReadyApp(onMount: () => mountedApplications++);
        },
      ),
    );
    await tester.pump();
    expect(loads, 1);
    expect(find.text('BDK AUDIO'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Starting up…'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.hasRunningAnimations, isTrue);
    expect(mountedApplications, 0);
    await tester.pump(const Duration(milliseconds: 1400));
    expect(mountedApplications, 0);
    expect(find.text('BDK AUDIO'), findsOneWidget);
    expect(find.text('Discovering actual speaker'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('B zoom reveals the mounted application before brand exits', (
    tester,
  ) async {
    var mountedApplications = 0;
    await tester.pumpWidget(
      BdkStartupApp(
        loadApplication: () async =>
            _ReadyApp(onMount: () => mountedApplications++),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();
    expect(mountedApplications, 1);
    expect(find.text('Discovering actual speaker'), findsOneWidget);
    expect(find.byKey(const ValueKey('bdk-brand-reveal')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    final zoom = tester.widget<Transform>(
      find.byKey(const ValueKey('bdk-brand-zoom')),
    );
    expect(zoom.transform.getMaxScaleOnAxis(), greaterThan(3));
    await tester.pump(const Duration(milliseconds: 350));
    // Flutter's interpolation simulation completes strictly after its nominal
    // duration; advance one rendered frame beyond the exact 700 ms boundary.
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Discovering actual speaker'), findsOneWidget);
    expect(find.byKey(const ValueKey('bdk-brand-reveal')), findsNothing);
    expect(mountedApplications, 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('closing during intro or pending loading cancels animation', (
    tester,
  ) async {
    final ready = Completer<Widget>();
    await tester.pumpWidget(BdkStartupApp(loadApplication: () => ready.future));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
    ready.complete(const MaterialApp(home: Text('Late ready')));
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Late ready'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('slow loading retains a stable brand then performs the reveal', (
    tester,
  ) async {
    final ready = Completer<Widget>();
    var loads = 0;
    var mountedApplications = 0;
    await tester.pumpWidget(
      BdkStartupApp(
        loadApplication: () {
          loads++;
          return ready.future;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('BDK AUDIO'), findsOneWidget);
    expect(find.text('Starting up…'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    expect(loads, 1);
    ready.complete(_ReadyApp(onMount: () => mountedApplications++));
    await tester.pump();
    await tester.pump();
    expect(mountedApplications, 1);
    expect(find.byKey(const ValueKey('bdk-brand-reveal')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(find.text('Discovering actual speaker'), findsOneWidget);
    expect(find.byKey(const ValueKey('bdk-brand-reveal')), findsNothing);
  });

  testWidgets('failed loading presents a real error and retries on request', (
    tester,
  ) async {
    var loads = 0;
    final retry = Completer<Widget>();
    await tester.pumpWidget(
      BdkStartupApp(
        loadApplication: () {
          loads++;
          return loads == 1
              ? Future.error(StateError('unavailable'))
              : retry.future;
        },
      ),
    );
    await tester.pump();
    expect(find.text('Unable to start'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(loads, 1);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(loads, 2);
    expect(find.text('Unable to start'), findsNothing);
    expect(find.text('Starting up…'), findsOneWidget);
    retry.complete(const MaterialApp(home: Text('Ready application')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(find.text('Ready application'), findsOneWidget);
  });

  testWidgets('reduced motion skips zoom and enters ready app promptly', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      BdkStartupApp(
        loadApplication: () async =>
            const MaterialApp(home: Text('Ready application')),
      ),
    );
    await tester.pump();
    expect(find.text('BDK AUDIO'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('Ready application'), findsOneWidget);
    expect(find.byKey(const ValueKey('bdk-brand-reveal')), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('slow startup and error remain usable at 280 px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 520);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final ready = Completer<Widget>();
    await tester.pumpWidget(BdkStartupApp(loadApplication: () => ready.future));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Starting up…'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    ready.completeError(StateError('unavailable'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Unable to start'), findsOneWidget);
    await tester.ensureVisible(find.text('Try again'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('running app does not replay intro after lifecycle resume', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      BdkStartupApp(
        loadApplication: () async {
          loads++;
          return const MaterialApp(home: Text('Ready application'));
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Ready application'), findsOneWidget);
    expect(find.text('BDK AUDIO'), findsNothing);
    expect(loads, 1);
  });
}

// Ordinary startup tests begin with a rendered engine frame. The separate
// first-raster suite holds this binding signal pending to exercise the gate.
class _RasterReadyBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  Future<void> get waitUntilFirstFrameRasterized => Future<void>.value();
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
      const MaterialApp(home: Text('Discovering actual speaker'));
}
