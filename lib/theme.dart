import 'package:flutter/material.dart';

ThemeData bdkTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff65d9f4),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xff65d9f4) : const Color(0xff08728a),
        onPrimary: dark ? const Color(0xff07141c) : Colors.white,
        surface: dark ? const Color(0xff0b0e15) : const Color(0xfff5f7fb),
        surfaceContainer: dark ? const Color(0xff151a25) : Colors.white,
        surfaceContainerHighest: dark
            ? const Color(0xff1b2230)
            : const Color(0xffedf1f8),
        onSurface: dark ? const Color(0xfff6f8ff) : const Color(0xff162136),
        onSurfaceVariant: dark
            ? const Color(0xffa7b1c5)
            : const Color(0xff526078),
        outlineVariant: dark
            ? const Color(0xff2a3344)
            : const Color(0xffd9e1ed),
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: scheme.surface,
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontFamily: 'SpaceGrotesk',
        fontWeight: FontWeight.w600,
        letterSpacing: -1,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontFamily: 'SpaceGrotesk',
        fontWeight: FontWeight.w600,
        letterSpacing: -.7,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontFamily: 'SpaceGrotesk',
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 5,
      shadowColor: (dark ? Colors.black : const Color(0xff364d72)).withValues(
        alpha: dark ? .45 : .16,
      ),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: .12),
      height: 78,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}
