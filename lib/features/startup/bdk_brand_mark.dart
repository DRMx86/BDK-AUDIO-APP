import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Original B monogram with an eighth-note cue, shared with the SVG icon master.
/// This stays vector art when the startup letter expands beyond the viewport.
class BdkBrandMark extends StatelessWidget {
  const BdkBrandMark({
    super.key,
    this.size = 136,
    this.noteProgress = 1,
    this.noteOpacity = 1,
  });

  final double size;
  final double noteProgress;
  final double noteOpacity;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'BDK Audio musical B',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BdkBrandPainter(
          noteProgress: noteProgress,
          noteOpacity: noteOpacity,
        ),
      ),
    ),
  );
}

class _BdkBrandPainter extends CustomPainter {
  const _BdkBrandPainter({
    required this.noteProgress,
    required this.noteOpacity,
  });

  final double noteProgress;
  final double noteOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final letter = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(32, 13)
      ..lineTo(55, 13)
      ..cubicTo(74, 13, 86, 22, 86, 35)
      ..cubicTo(86, 43, 82, 48, 75, 51)
      ..cubicTo(84, 54, 90, 60, 90, 69)
      ..cubicTo(90, 81, 78, 87, 58, 87)
      ..lineTo(32, 87)
      ..cubicTo(28.7, 87, 26, 84.3, 26, 81)
      ..lineTo(26, 19)
      ..cubicTo(26, 15.7, 28.7, 13, 32, 13)
      ..close()
      ..moveTo(43, 29)
      ..lineTo(43, 44)
      ..lineTo(54, 44)
      ..cubicTo(63, 44, 69, 41.5, 69, 36.5)
      ..cubicTo(69, 31.5, 64, 29, 54, 29)
      ..close()
      ..moveTo(43, 59)
      ..lineTo(43, 72)
      ..lineTo(57, 72)
      ..cubicTo(67, 72, 73, 70, 73, 65.5)
      ..cubicTo(73, 61, 67, 59, 57, 59)
      ..close();
    canvas.drawPath(
      letter,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfff0feff), Color(0xffa4f2ff), Color(0xff33c9ed)],
          stops: [0, .45, 1],
        ).createShader(const Rect.fromLTWH(26, 13, 64, 74)),
    );
    final progress = noteProgress.clamp(0.0, 1.0);
    if (progress > 0 && noteOpacity > 0) {
      final notePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xff9daaff).withValues(alpha: noteOpacity),
            const Color(0xff62e2f7).withValues(alpha: noteOpacity),
          ],
        ).createShader(const Rect.fromLTWH(2, 25, 23, 44));
      // Oval head, tall stem and curved flag read as a musical note at icon size.
      canvas.save();
      canvas.translate(10, 62);
      canvas.rotate(-math.pi / 9);
      canvas.scale(progress, progress);
      canvas.drawOval(const Rect.fromLTWH(-8.5, -6, 17, 12), notePaint);
      canvas.restore();
      final stemAndFlag = Path()
        ..moveTo(17, 59)
        ..lineTo(17, 27)
        ..cubicTo(17, 34, 29, 32, 23, 43);
      notePaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final segment in stemAndFlag.computeMetrics()) {
        canvas.drawPath(
          segment.extractPath(0, segment.length * progress),
          notePaint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BdkBrandPainter oldDelegate) =>
      oldDelegate.noteProgress != noteProgress ||
      oldDelegate.noteOpacity != noteOpacity;
}
