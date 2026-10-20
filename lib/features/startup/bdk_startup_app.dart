import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'bdk_brand_mark.dart';

class BdkStartupApp extends StatefulWidget {
  const BdkStartupApp({super.key, required this.loadApplication});
  final Future<Widget> Function() loadApplication;

  @override
  State<BdkStartupApp> createState() => _BdkStartupAppState();
}

class _BdkStartupAppState extends State<BdkStartupApp>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _intro;
  late final AnimationController _reveal;
  Timer? _staticIntro;
  Widget? _readyApplication;
  Object? _loadError;
  int _loadGeneration = 0;
  bool _reducedMotion = false;
  bool _firstRasterComplete = false;
  bool _introComplete = false;
  bool _revealing = false;
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _intro =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2000),
        )..addStatusListener((status) {
          if (status != AnimationStatus.completed || !mounted) return;
          setState(() => _introComplete = true);
          _tryReveal();
        });
    _reveal =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 700),
        )..addStatusListener((status) {
          if (status != AnimationStatus.completed || !mounted) return;
          setState(() => _complete = true);
        });
    // Loading is real and starts alongside the intro. The returned app is only
    // mounted when the reveal starts, so discovery cannot expire invisibly.
    _load();
    _startAfterFirstRaster();
  }

  Future<void> _startAfterFirstRaster() async {
    // A CPU post-frame callback only means the frame was submitted. Cold-start
    // raster work can still hide most of the hold behind a platform surface.
    // Begin the visible dwell after the engine confirms its first raster.
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    if (!mounted) return;
    _firstRasterComplete = true;
    if (_introComplete) {
      _tryReveal();
    } else if (_reducedMotion) {
      _staticIntro = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _introComplete = true);
        _tryReveal();
      });
    } else {
      _intro.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ??
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
  }

  @override
  void didChangeAccessibilityFeatures() {
    final disabled = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (!disabled || !mounted || _complete) return;
    _staticIntro?.cancel();
    _intro.stop();
    _reveal.stop();
    setState(() {
      _reducedMotion = true;
      _introComplete = true;
    });
    _tryReveal();
  }

  void _load() {
    final generation = ++_loadGeneration;
    _loadError = null;
    Future<Widget>.sync(widget.loadApplication).then(
      (application) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() => _readyApplication = application);
        _tryReveal();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || generation != _loadGeneration) return;
        _staticIntro?.cancel();
        _intro.stop();
        setState(() {
          _loadError = error;
          _introComplete = true;
        });
      },
    );
  }

  void _tryReveal() {
    if (!mounted ||
        !_firstRasterComplete ||
        !_introComplete ||
        _readyApplication == null ||
        _complete) {
      return;
    }
    if (_reducedMotion) {
      setState(() => _complete = true);
      return;
    }
    if (_revealing) return;
    setState(() => _revealing = true);
    // Both the app and aperture paint in this frame at progress zero. Starting
    // in a post-frame callback would defer the ticker's time origin by a frame.
    _reveal.forward();
  }

  void _retry() {
    setState(_load);
  }

  @override
  void dispose() {
    ++_loadGeneration;
    _staticIntro?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _intro.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    textDirection: TextDirection.ltr,
    children: [
      if (_readyApplication != null && (_revealing || _complete))
        KeyedSubtree(
          key: const ValueKey('bdk-ready-application'),
          child: _readyApplication!,
        ),
      if (!_complete)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: Listenable.merge([_intro, _reveal]),
            builder: (context, child) => LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                final center = Offset(size.width / 2, size.height * .42);
                final progress = _reveal.value;
                // The upper B counter is the aperture's origin. The letter
                // scales around it; this is a zoom into the B, not a tile.
                final counter = center + const Offset(8.16, -18.36);
                final maxScale = math.max(12.0, size.longestSide / 136 * 3);
                final scale =
                    1 + (maxScale - 1) * Curves.easeInQuad.transform(progress);
                final apertureProgress = ((progress - .08) / .92).clamp(
                  0.0,
                  1.0,
                );
                final radius =
                    math.sqrt(
                      size.width * size.width + size.height * size.height,
                    ) *
                    Curves.easeInCubic.transform(apertureProgress);
                return ClipPath(
                  clipper: _CounterAperture(center: counter, radius: radius),
                  child: AbsorbPointer(
                    absorbing: _revealing,
                    child: ExcludeSemantics(
                      excluding: _revealing,
                      child: MaterialApp(
                        key: const ValueKey('bdk-brand-reveal'),
                        debugShowCheckedModeBanner: false,
                        theme: bdkTheme(Brightness.dark),
                        home: Scaffold(
                          backgroundColor: const Color(0xff080f1b),
                          body: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(0, -.2),
                                radius: .85,
                                colors: [
                                  Color(0xff163c48),
                                  Color(0xff0c202c),
                                  Color(0xff080f1b),
                                ],
                                stops: [0, .5, 1],
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  left: center.dx - 68,
                                  top: center.dy - 68,
                                  child: Transform.scale(
                                    key: const ValueKey('bdk-brand-zoom'),
                                    scale: scale,
                                    alignment: const Alignment(.12, -.27),
                                    child: Transform.translate(
                                      offset: Offset(
                                        0,
                                        _introComplete || _reducedMotion
                                            ? 0
                                            : 10 *
                                                  (1 -
                                                      Curves.easeOutCubic
                                                          .transform(
                                                            _intro.value,
                                                          )),
                                      ),
                                      child: BdkBrandMark(
                                        noteProgress:
                                            _introComplete || _reducedMotion
                                            ? 1
                                            : Curves.easeOutCubic.transform(
                                                (_intro.value / .7).clamp(
                                                  0.0,
                                                  1.0,
                                                ),
                                              ),
                                        noteOpacity: (1 - progress * 2).clamp(
                                          0.0,
                                          1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: center.dy + 92,
                                  left: 24,
                                  right: 24,
                                  bottom: 16,
                                  child: Opacity(
                                    opacity: (1 - progress * 3).clamp(0.0, 1.0),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'BDK AUDIO',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontFamily: 'SpaceGrotesk',
                                              fontSize: 24,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 2,
                                            ),
                                          ),
                                          if (_readyApplication == null) ...[
                                            const SizedBox(height: 12),
                                            Semantics(
                                              liveRegion: true,
                                              child: Text(
                                                _loadError != null
                                                    ? 'Unable to start'
                                                    : 'Starting up…',
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ],
                                          if (_loadError != null) ...[
                                            const SizedBox(height: 12),
                                            const Text(
                                              'Please try opening the app again.',
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 24),
                                            FilledButton(
                                              onPressed: _retry,
                                              child: const Text('Try again'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
    ],
  );
}

/// Subtract an opening from the brand surface so the app appears through B.
class _CounterAperture extends CustomClipper<Path> {
  const _CounterAperture({required this.center, required this.radius});
  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) {
    final path = Path()..addRect(Offset.zero & size);
    if (radius <= 0) return path;
    return Path.combine(
      PathOperation.difference,
      path,
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldReclip(covariant _CounterAperture oldClipper) =>
      oldClipper.center != center || oldClipper.radius != radius;
}
