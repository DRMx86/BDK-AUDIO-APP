import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ToneControlStyle { pillars, wells, steps }

/// Three fixed firmware bands. Values are wire levels, not applied decibels.
///
/// The owner keeps confirmed/pending device state and coalesces transport writes.
/// This widget emits a fresh, bounded list and owns no Bluetooth state.
class ToneControls extends StatelessWidget {
  const ToneControls({
    super.key,
    required this.levels,
    required this.onChanged,
    this.style = ToneControlStyle.pillars,
  }) : assert(levels.length == 3);
  final List<int> levels;
  final ValueChanged<List<int>> onChanged;
  final ToneControlStyle style;
  @override
  Widget build(BuildContext context) {
    final bounded = levels.map((value) => value.clamp(-12, 12)).toList();
    void change(int index, int value) {
      final next = List<int>.of(bounded);
      next[index] = value.clamp(-12, 12);
      if (next[index] != bounded[index]) onChanged(next);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 330 ||
            MediaQuery.textScalerOf(context).scale(16) > 22;
        final bands = List.generate(
          3,
          (index) => _ToneBand(
            key: ValueKey('tone-band-$index'),
            index: index,
            name: const ['Bass', 'Mid', 'Treble'][index],
            frequency: const ['150 Hz', '1 kHz', '6 kHz'][index],
            level: bounded[index],
            style: style,
            compact: stacked,
            onChanged: (value) => change(index, value),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stacked)
              ...bands.expand((band) => [band, const SizedBox(height: 12)])
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < bands.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: bands[i]),
                  ],
                ],
              ),
            const SizedBox(height: 12),
            Text(
              'Level −12 to +12 · 0 is neutral',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ToneBand extends StatefulWidget {
  const _ToneBand({
    super.key,
    required this.index,
    required this.name,
    required this.frequency,
    required this.level,
    required this.style,
    required this.compact,
    required this.onChanged,
  });
  final int index;
  final String name;
  final String frequency;
  final int level;
  final ToneControlStyle style;
  final bool compact;
  final ValueChanged<int> onChanged;

  @override
  State<_ToneBand> createState() => _ToneBandState();
}

class _ToneBandState extends State<_ToneBand> {
  final _focusNode = FocusNode();
  double _dragDistance = 0;
  int _dragStart = 0;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final int next;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowRight) {
      next = widget.level + 1;
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft) {
      next = widget.level - 1;
    } else if (key == LogicalKeyboardKey.home) {
      next = -12;
    } else if (key == LogicalKeyboardKey.end) {
      next = 12;
    } else if (key == LogicalKeyboardKey.pageUp) {
      next = widget.level + 3;
    } else if (key == LogicalKeyboardKey.pageDown) {
      next = widget.level - 3;
    } else {
      return KeyEventResult.ignored;
    }
    widget.onChanged(next);
    return KeyEventResult.handled;
  }

  String _signed(int value) => value > 0 ? '+$value' : '$value';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final control = Semantics(
      key: ValueKey('tone-semantics-${widget.index}'),
      slider: true,
      focusable: true,
      focused: _focused,
      onFocus: _focusNode.requestFocus,
      label: '${widget.name}, ${widget.frequency}',
      value: '${_signed(widget.level)}, level',
      increasedValue: '${_signed((widget.level + 1).clamp(-12, 12))}, level',
      decreasedValue: '${_signed((widget.level - 1).clamp(-12, 12))}, level',
      onIncrease: widget.level < 12
          ? () => widget.onChanged(widget.level + 1)
          : null,
      onDecrease: widget.level > -12
          ? () => widget.onChanged(widget.level - 1)
          : null,
      hint: 'Drag up or down. Arrow keys adjust one level.',
      child: ExcludeSemantics(
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _key,
          onFocusChange: (value) => setState(() => _focused = value),
          child: GestureDetector(
            key: ValueKey('tone-control-${widget.index}'),
            behavior: HitTestBehavior.opaque,
            onTap: _focusNode.requestFocus,
            onVerticalDragStart: (_) {
              _focusNode.requestFocus();
              _dragDistance = 0;
              _dragStart = widget.level;
            },
            onVerticalDragUpdate: (details) {
              _dragDistance += details.delta.dy;
              widget.onChanged(_dragStart - (_dragDistance / 6).round());
            },
            child: SizedBox(
              height: 158,
              width: 120,
              child: CustomPaint(
                painter: _TonePainter(
                  level: widget.level,
                  style: widget.style,
                  colors: colors,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final name = Text(
      widget.name,
      style: text.titleMedium,
      textAlign: widget.compact ? TextAlign.start : TextAlign.center,
    );
    final frequency = Text(
      widget.frequency,
      style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
    );
    final value = Text(
      _signed(widget.level),
      style: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: colors.primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final buttons = Row(
      mainAxisAlignment: widget.compact
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Decrease ${widget.name}',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: widget.level > -12
              ? () => widget.onChanged(widget.level - 1)
              : null,
          icon: const Icon(Icons.remove),
        ),
        IconButton(
          tooltip: 'Increase ${widget.name}',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: widget.level < 12
              ? () => widget.onChanged(widget.level + 1)
              : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _focused ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: 16,
          horizontal: widget.compact ? 12 : 2,
        ),
        child: widget.compact
            ? Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        name,
                        const SizedBox(height: 4),
                        frequency,
                        const SizedBox(height: 12),
                        value,
                        const SizedBox(height: 8),
                        buttons,
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 112, child: control),
                ],
              )
            : Column(
                children: [
                  name,
                  const SizedBox(height: 4),
                  frequency,
                  const SizedBox(height: 12),
                  control,
                  value,
                  const SizedBox(height: 8),
                  buttons,
                ],
              ),
      ),
    );
  }
}

class _TonePainter extends CustomPainter {
  const _TonePainter({
    required this.level,
    required this.style,
    required this.colors,
  });
  final int level;
  final ToneControlStyle style;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final background = Paint()..color = colors.surfaceContainerHighest;
    final accent = Paint()..color = colors.primary;
    final line = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    if (style == ToneControlStyle.pillars) {
      final width = math.min(size.width * .43, 46.0);
      final rect = Rect.fromCenter(center: center, width: width, height: 138);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(16)),
        background,
      );
      final y = center.dy - level / 12 * 60;
      final fill = Rect.fromLTRB(
        rect.left,
        math.min(center.dy, y),
        rect.right,
        math.max(center.dy, y),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(fill, const Radius.circular(7)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.primary.withValues(alpha: .75),
              colors.primary.withValues(alpha: .22),
            ],
          ).createShader(rect),
      );
      for (var step = -12; step <= 12; step += 3) {
        final tickY = center.dy - step / 12 * 60;
        canvas.drawLine(
          Offset(rect.left + 7, tickY),
          Offset(rect.right - 7, tickY),
          line,
        );
      }
      canvas.drawLine(
        Offset(rect.left - 9, center.dy),
        Offset(rect.right + 9, center.dy),
        Paint()
          ..color = colors.onSurfaceVariant.withValues(alpha: .6)
          ..strokeWidth = 1,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(center.dx, y),
            width: width + 10,
            height: 8,
          ),
          const Radius.circular(4),
        ),
        accent,
      );
      canvas.drawLine(
        Offset(center.dx - 8, y),
        Offset(center.dx + 8, y),
        Paint()
          ..color = colors.onPrimary
          ..strokeWidth = 2,
      );
    } else if (style == ToneControlStyle.wells) {
      final radius = math.min(size.width / 2 - 11, 47.0);
      final ring = Rect.fromCircle(center: center, radius: radius);
      final track = Paint()
        ..color = colors.outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(center, radius - 11, background);
      canvas.drawArc(ring, math.pi * .75, math.pi * 1.5, false, track);
      final angle = -math.pi / 2 + level / 12 * math.pi * .75;
      if (level != 0) {
        canvas.drawArc(
          ring,
          -math.pi / 2,
          level / 12 * math.pi * .75,
          false,
          Paint()
            ..color = colors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        6,
        Paint()..color = colors.onSurface,
      );
      canvas.drawLine(
        Offset(center.dx, center.dy - radius - 12),
        Offset(center.dx, center.dy - radius - 5),
        line,
      );
      canvas.drawCircle(center, 4, accent);
    } else {
      // Twelve steps in each direction, read around a fixed neutral seam.
      final segmentWidth = math.min(size.width * .66, 70.0);
      for (var step = -12; step <= 12; step++) {
        final y = center.dy - step * 5.5;
        final active = level > 0
            ? step > 0 && step <= level
            : step < 0 && step >= level;
        final width = step == 0 ? segmentWidth + 12 : segmentWidth;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(center.dx, y),
              width: width,
              height: step == 0 ? 2 : 3,
            ),
            const Radius.circular(2),
          ),
          Paint()
            ..color = step == 0
                ? colors.onSurfaceVariant
                : active
                ? colors.primary
                : colors.outlineVariant,
        );
      }
      final y = center.dy - level * 5.5;
      canvas.drawCircle(Offset(center.dx + segmentWidth / 2 + 8, y), 4, accent);
    }
  }

  @override
  bool shouldRepaint(_TonePainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.style != style ||
      oldDelegate.colors != colors;
}
