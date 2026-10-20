import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Original speaker illustration with soft search light. Motion never signals readiness.
class SpeakerDiscoveryHero extends StatefulWidget {
  const SpeakerDiscoveryHero({
    super.key,
    this.active = false,
    this.found = false,
  });
  final bool active, found;

  @override
  State<SpeakerDiscoveryHero> createState() => _SpeakerDiscoveryHeroState();
}

class _SpeakerDiscoveryHeroState extends State<SpeakerDiscoveryHero>
    with SingleTickerProviderStateMixin {
  late final _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4800),
  );

  void _syncMotion() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_scan.isAnimating) _scan.repeat();
    } else {
      _scan.stop();
      _scan.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(SpeakerDiscoveryHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _scan,
          builder: (context, child) => CustomPaint(
            painter: _DiscoveryPainter(
              phase: _scan.value,
              active: widget.active,
              found: widget.found,
              accent: colors.primary,
              dark: colors.brightness == Brightness.dark,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _DiscoveryPainter extends CustomPainter {
  const _DiscoveryPainter({
    required this.phase,
    required this.active,
    required this.found,
    required this.accent,
    required this.dark,
  });
  final double phase;
  final bool active, found, dark;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .49);
    final radius = math.min(size.width * .49, size.height * .48);
    final halo = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: dark ? .12 : .08),
            accent.withValues(alpha: 0),
          ],
        ).createShader(halo),
    );
    for (var ring = 1; ring <= 4; ring++) {
      canvas.drawCircle(
        center,
        radius * (.25 + ring * .175),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = accent.withValues(alpha: .18 - ring * .028),
      );
    }
    if (active) {
      // Two diffuse waves fade in and out smoothly, without rotating geometry.
      for (var pulse = 0; pulse < 2; pulse++) {
        final progress = (phase + pulse * .5) % 1.0;
        final envelope = math.sin(math.pi * progress);
        final pulseRadius = radius * (.38 + progress * .57);
        final light = pulse == 0 ? accent : const Color(0xffa4a5ff);
        canvas.drawCircle(
          center,
          pulseRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 16
            ..color = light.withValues(alpha: envelope * (pulse == 0 ? .20 : .10))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        canvas.drawCircle(
          center,
          pulseRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = light.withValues(alpha: envelope * (pulse == 0 ? .13 : .06))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
      }
    }
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale((radius / 168).clamp(.65, 1.4).toDouble());
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 96), width: 148, height: 24),
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? .45 : .14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.rotate(-.07);
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-54, -88, 108, 178),
      const Radius.circular(24),
    );
    canvas.drawShadow(Path()..addRRect(body), Colors.black, 18, false);
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff46546a), Color(0xff222e40), Color(0xff111b2a)],
          stops: [0, .45, 1],
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(
      body.deflate(.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: .4),
            Colors.white.withValues(alpha: .02),
          ],
        ).createShader(body.outerRect),
    );
    final grille = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-44, -73, 88, 146),
      const Radius.circular(18),
    );
    canvas.drawRRect(grille, Paint()..color = const Color(0xff101a29));
    canvas.save();
    canvas.clipRRect(grille);
    for (var y = -69.0; y <= 72; y += 5) {
      for (var x = -40.0; x <= 42; x += 5) {
        canvas.drawCircle(
          Offset(x, y),
          .65,
          Paint()..color = const Color(0xff3b4859),
        );
      }
    }
    canvas.restore();
    _driver(canvas, const Offset(0, -37), 22);
    _driver(canvas, const Offset(0, 28), 32);
    final light = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-17, 79, 34, 3),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      light,
      Paint()
        ..color = accent.withValues(alpha: .4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(light, Paint()..color = accent);
    canvas.restore();
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = accent.withValues(alpha: found ? .8 : .4);
    final waveCenter = center + Offset(radius * .48, -radius * .35);
    for (final r in [8.0, 16.0, 24.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: waveCenter, radius: r),
        -.7,
        1.4,
        false,
        wavePaint,
      );
    }
  }

  void _driver(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xff0a111c));
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xff566376),
    );
    canvas.drawCircle(
      center,
      radius - 5,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xff26364a), Color(0xff0e1724)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius * .32,
      Paint()..color = const Color(0xff36465b),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 2),
      math.pi * 1.05,
      math.pi * .65,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: .6),
    );
  }

  @override
  bool shouldRepaint(_DiscoveryPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.active != active ||
      oldDelegate.found != found ||
      oldDelegate.accent != accent ||
      oldDelegate.dark != dark;
}
