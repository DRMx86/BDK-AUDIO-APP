// Isolated hardware-free profiling entry point; never imports a BLE transport.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:bdk_audio/features/light/meter_preview.dart';
import 'package:bdk_audio/theme.dart';
import 'package:bdk_led_engine/bdk_led_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'preview_frame_stats.dart';
import 'profile_run.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const reportPath = String.fromEnvironment('BDK_PROFILE_REPORT_DIR');
  final directory = reportPath.isNotEmpty
      ? await Directory(reportPath).create(recursive: true)
      : Platform.isAndroid
      ? await getExternalStorageDirectory()
      : await getTemporaryDirectory();
  if (directory == null) throw StateError('No app-scoped report directory.');
  // Invalidate the current result before native renderer construction can fail.
  final run = await ProfileRun.begin(
    directory,
    runId:
        '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}',
    processId: pid,
  );
  if (!const bool.fromEnvironment('BDK_NATIVE_QA') || !kProfileMode) {
    await run.fail('Use the isolated native QA package in profile mode.');
    throw StateError('Use the isolated native QA package in profile mode.');
  }
  runApp(_ProfileApp(run: run));
}

class _Scenario {
  const _Scenario(this.name, this.effect, {this.hz = 0});
  final String name;
  final int effect, hz;
}

class _MeasuredRenderer implements LightFrameRenderer {
  _MeasuredRenderer(this.workload);
  final ProfileWorkload workload;
  final engine = NativeLedEngine();
  int renders = 0, micros = 0;
  @override
  void configure(List<int> payload) {
    try {
      engine.configure(payload);
    } catch (_) {
      workload.renderFailed = true;
      rethrow;
    }
  }

  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) {
    final watch = Stopwatch()..start();
    try {
      final frame = engine.render(
        demo: demo,
        audio: audio,
        beat: beat,
        audioActive: audioActive,
      );
      micros += watch.elapsedMicroseconds;
      renders++;
      workload.rendered(
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
      );
      return frame;
    } catch (_) {
      workload.renderFailed = true;
      rethrow;
    }
  }

  @override
  void dispose() => engine.dispose();
}

class _ProfileApp extends StatefulWidget {
  const _ProfileApp({required this.run});
  final ProfileRun run;
  @override
  State<_ProfileApp> createState() => _ProfileAppState();
}

class _ProfileAppState extends State<_ProfileApp> with WidgetsBindingObserver {
  static const scenarios = [
    _Scenario('Spectrum demo', 0),
    _Scenario('Fire demo', 3),
    _Scenario('Plasma demo', 4),
    _Scenario('Kaleidoscope demo', 12),
    _Scenario('Bass Reactor demo', 14),
    _Scenario('Ambient demo', 21),
    _Scenario('Fixture input 30 Hz', 0, hz: 30),
    _Scenario('Fixture input 60 Hz', 0, hz: 60),
    _Scenario('Fixture input 100 Hz', 0, hz: 100),
  ];
  final stats = PreviewFrameStats();
  final workload = ProfileWorkload();
  final processor = MeterPreviewProcessor();
  final windows = <Map<String, Object?>>[];
  _MeasuredRenderer? _renderer;
  _MeasuredRenderer get renderer => _renderer!;
  Timer? input;
  MeterLevels? meter;
  PreviewAudioSample sample = PreviewAudioSample.silent;
  _Scenario scenario = scenarios.first;
  String status = 'Preparing renderer';
  bool finished = false;
  int fixtureTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _timings(List<ui.FrameTiming> values) {
    for (final frame in values) {
      stats.add(frame);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) workload.backgrounded = true;
  }

  @override
  void didChangeAccessibilityFeatures() => workload.observeReducedMotion(
    WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations,
  );
  @override
  void dispose() {
    input?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<int> _stamp() {
    final result = Completer<int>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      result.complete(
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
      );
    });
    SchedulerBinding.instance.scheduleFrame();
    return result.future.timeout(const Duration(seconds: 3));
  }

  void _fixture() {
    final now = DateTime.now(), t = fixtureTick++ / scenario.hz;
    int band(double phase) => (50 + 45 * math.sin(t * 6 + phase)).round();
    final next = MeterLevels(band(0), band(1.2), band(2.4), now);
    final nextSample = processor.update(next, now: now);
    if (mounted) {
      setState(() {
        meter = next;
        sample = nextSample;
      });
    }
  }

  Future<void> _run() async {
    try {
      _renderer = _MeasuredRenderer(workload);
      if (mounted) setState(() {});
      await _measure();
    } catch (error) {
      await widget.run.fail('$error');
      if (mounted) {
        setState(() {
          status = 'Failed · report saved';
          finished = true;
        });
      }
    } finally {
      input?.cancel();
      if (!widget.run.ended) {
        await widget.run.fail('Run interrupted before completion.');
      }
    }
  }

  Future<void> _measure() async {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final view = dispatcher.views.first, refreshHz = view.display.refreshRate;
    workload.observeReducedMotion(
      dispatcher.accessibilityFeatures.disableAnimations,
    );
    for (final next in scenarios) {
      if (!mounted) return;
      input?.cancel();
      processor.reset();
      fixtureTick = 0;
      setState(() {
        scenario = next;
        meter = null;
        sample = PreviewAudioSample.silent;
        status = 'Warming up';
      });
      if (next.hz > 0) {
        input = Timer.periodic(
          Duration(microseconds: (1000000 / next.hz).round()),
          (_) => _fixture(),
        );
      }
      await widget.run.progress({'scenario': next.name, 'state': 'warmup'});
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => status = 'Measuring');
      final start = await _stamp(),
          calls = renderer.renders,
          micros = renderer.micros,
          ticks = fixtureTick;
      await Future<void>.delayed(const Duration(seconds: 6));
      if (!mounted) return;
      final end = await _stamp();
      windows.add({
        'name': next.name,
        'start': start,
        'end': end,
        'renderCalls': renderer.renders - calls,
        'renderMicros': renderer.micros - micros,
        'fixtureTicks': fixtureTick - ticks,
        'fixtureHzRequested': next.hz,
      });
    }
    input?.cancel();
    if (!mounted) return;
    setState(() => status = 'Collecting delayed engine timings');
    await widget.run.progress({'state': 'draining'});
    final boundary = windows.last['end']! as int;
    final drain = Stopwatch()..start();
    while (!stats.hasTimingAtOrAfter(boundary) &&
        drain.elapsedMilliseconds < 5000) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    final timingWatermark = stats.hasTimingAtOrAfter(boundary);
    final results = [
      for (final window in windows)
        {
          'name': window['name'],
          'renderCalls': window['renderCalls'],
          'renderMicros': window['renderMicros'],
          'fixtureTicks': window['fixtureTicks'],
          'fixtureHzRequested': window['fixtureHzRequested'],
          'activityConclusive': workload.conclusive(
            start: window['start']! as int,
            end: window['end']! as int,
          ),
          ...stats.summarize(
            start: window['start']! as int,
            end: window['end']! as int,
            refreshHz: refreshHz,
          ),
        },
    ];
    await widget.run.complete({
      'schema': 2,
      'mode': 'profile',
      'input': 'synthetic or demo, no Bluetooth',
      'platform': Platform.operatingSystem,
      'refreshHz': refreshHz,
      'physicalWidth': view.physicalSize.width,
      'physicalHeight': view.physicalSize.height,
      'devicePixelRatio': view.devicePixelRatio,
      'backgrounded': workload.backgrounded,
      'reducedMotion': workload.reducedMotion,
      'rendererFailed': workload.renderFailed,
      'timingWatermark': timingWatermark,
      'conclusiveRun':
          timingWatermark &&
          results.every(
            (result) =>
                result['conclusive'] == true &&
                result['activityConclusive'] == true,
          ),
      'scenarios': results,
    });
    setState(() {
      status = 'Complete · report saved';
      finished = true;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: bdkTheme(Brightness.dark),
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: const Text('Native preview benchmark')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${scenario.name} · $status\nSynthetic input · no Bluetooth',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: finished || _renderer == null
                ? Center(child: Text(status))
                : FixedProfileWorkload(
                    child: LightScreen(
                      settings: LedSettings(
                        effect: scenario.effect,
                        brightness: 70,
                        speed: 50,
                        color1: 0x65d9f4,
                        color2: 0xbcabff,
                        gradient: 1,
                      ),
                      onChanged: (_) {},
                      rendererFactory: () => renderer,
                      connected: scenario.hz > 0,
                      meter: meter,
                      previewAudio: scenario.hz > 0 ? sample.values : null,
                      previewBeat: sample.beat,
                      previewAudioActive: sample.audioActive,
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
