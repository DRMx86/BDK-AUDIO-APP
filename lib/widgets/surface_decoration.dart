import 'package:flutter/material.dart';

/// Shared depth for purposeful surfaces, with a restrained cast shadow and edge.
BoxDecoration bdkSurfaceDecoration(
  BuildContext context, {
  double radius = 24,
  Color? color,
  bool emphasis = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  final dark = scheme.brightness == Brightness.dark;
  final base = color ?? scheme.surfaceContainer;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(
          (emphasis ? scheme.primary : Colors.white).withValues(
            alpha: dark ? .045 : .018,
          ),
          base,
        ),
        base,
      ],
    ),
    border: Border.all(
      color: scheme.outlineVariant.withValues(alpha: dark ? .6 : .8),
    ),
    boxShadow: [
      BoxShadow(
        color: (dark ? Colors.black : const Color(0xff364d72)).withValues(
          alpha: dark ? .30 : .09,
        ),
        blurRadius: emphasis ? 36 : 24,
        offset: Offset(0, emphasis ? 16 : 10),
        spreadRadius: -6,
      ),
    ],
  );
}
