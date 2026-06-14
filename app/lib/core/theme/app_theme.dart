import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// App theme built from [AppColors] tokens (CLAUDE.md §4.2) — "Modern Vibrant":
/// electric violet→pink on soft lilac (light) and deep aubergine (dark). Modern
/// geometric display type (Sora) + clean body (Inter). Dark mode is first-class.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final ink = dark ? AppColors.inkDark : AppColors.ink;
    final paper = dark ? AppColors.paperDark : AppColors.paper;
    final surface = dark ? AppColors.surfaceDark : AppColors.surface;
    final muted = dark ? AppColors.mist : AppColors.graphite;
    final fieldFill = dark ? const Color(0xFF2A1E3D) : AppColors.accentSoft;
    final border = dark ? const Color(0xFF34284A) : AppColors.mist;

    final display = GoogleFonts.sora(); // modern geometric headers
    final body = GoogleFonts.inter(); // UI/body

    final text = TextTheme(
      displaySmall: display.copyWith(
        fontSize: 30,
        height: 1.1,
        color: ink,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: display.copyWith(
        fontSize: 22,
        height: 1.15,
        color: ink,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: display.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyMedium: body.copyWith(fontSize: 15, height: 1.45, color: ink),
      labelLarge: body.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      bodySmall: body.copyWith(fontSize: 13, color: muted),
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.violet,
      brightness: b,
    ).copyWith(
      primary: AppColors.accent,
      secondary: AppColors.violet,
      surface: surface,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: paper,
      colorScheme: scheme,
      textTheme: text,
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleMedium?.copyWith(fontSize: 20),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? surface : Colors.white,
        selectedColor: AppColors.accentSoft,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        labelStyle: text.bodySmall?.copyWith(color: ink),
        secondaryLabelStyle: text.bodySmall?.copyWith(color: AppColors.accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: AppColors.accentSoft,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStatePropertyAll(
          text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}
