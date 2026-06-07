import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// App theme built from [AppColors] tokens (CLAUDE.md §4.2). Editorial display
/// type (Fraunces) + clean body type (Inter). Dark mode is first-class.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final ink = dark ? AppColors.inkDark : AppColors.ink;
    final paper = dark ? AppColors.paperDark : AppColors.paper;
    final surface = dark ? AppColors.surfaceDark : AppColors.surface;
    final display = GoogleFonts.fraunces(); // editorial headers
    final body = GoogleFonts.inter(); // UI/body

    final text = TextTheme(
      displaySmall: display.copyWith(
        fontSize: 30,
        height: 1.1,
        color: ink,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: display.copyWith(fontSize: 22, height: 1.15, color: ink),
      titleMedium: body.copyWith(
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
      bodySmall: body.copyWith(
        fontSize: 13,
        color: dark ? AppColors.mist : AppColors.graphite,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: b,
        surface: surface,
      ),
      textTheme: text,
      dividerColor: dark ? const Color(0xFF2A2A2A) : AppColors.mist,
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
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }
}
