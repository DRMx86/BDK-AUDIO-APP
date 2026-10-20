import 'package:flutter/material.dart';

/// A visual summary of the three control levels, not a measured response plot.
class PresetShape extends StatelessWidget {
  const PresetShape({super.key, required this.levels, this.large = false})
    : assert(levels.length == 3);
  final List<int> levels;
  final bool large;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sound shape',
    value: 'Bass ${levels[0]}, mid ${levels[1]}, treble ${levels[2]}',
    child: ExcludeSemantics(
      child: SizedBox(
          width: double.infinity,
        height: large ? 56 : 30,
        child: CustomPaint(
          painter: _ShapePainter(
            levels,
            Theme.of(context).colorScheme.primary,
            large,
          ),
        ),
      ),
    ),
  );
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.levels, this.color, this.large);
  final List<int> levels;
  final Color color;
  final bool large;
  @override
  void paint(Canvas canvas, Size size) {
    final inset = large ? 8.0 : 3.0,
        w = size.width - inset * 2,
        mid = size.height / 2;
    double y(int v) => mid - v.clamp(-12, 12) / 12 * (mid - inset);
    final points = [
      Offset(inset, y(levels[0])),
      Offset(inset + w / 2, y(levels[1])),
      Offset(inset + w, y(levels[2])),
    ];
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 0; i < 2; i++) {
      final a = points[i], b = points[i + 1], dx = (b.dx - a.dx) * .5;
      path.cubicTo(a.dx + dx, a.dy, b.dx - dx, b.dy, b.dx, b.dy);
    }
    if (large) {
      final area = Path.from(path)
        ..lineTo(points.last.dx, size.height)
        ..lineTo(inset, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: .24), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: .2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = large ? 2.8 : 2.0
        ..strokeCap = StrokeCap.round,
    );
    if (large) {
      for (final p in points) {
        canvas.drawCircle(p, 2.4, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.color != color || old.large != large || !_same(old.levels, levels);
  bool _same(List<int> a, List<int> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
}
