import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// App theme built from [AppColors] tokens (CLAUDE.md §4.2) — "Midnight Plum":
/// a luxury, futuristic AI fashion-tech look. Deep plum background, dark glass
/// surfaces, purple→pink gradients, Plus Jakarta Sans headings + Inter body.
///
/// The app is premium-dark everywhere, so both [light] and [dark] return the
/// same dark theme (and the root app pins `themeMode` to dark).
abstract final class AppTheme {
  static ThemeData light() => _build();
  static ThemeData dark() => _build();

  static ThemeData _build() {
    const ink = AppColors.ink; // white
    const paper = AppColors.paper; // #12091F
    const surface = AppColors.surface; // #241634
    const muted = AppColors.graphite; // #B9AFC8
    const fieldFill = Color(0xFF1E1430); // dark glass input
    const border = AppColors.glassBorder;

    final display = GoogleFonts.plusJakartaSans(); // premium headings
    final body = GoogleFonts.inter(); // UI/body

    final text = TextTheme(
      displayLarge: display.copyWith(
        fontSize: 34,
        height: 1.05,
        color: ink,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      displaySmall: display.copyWith(
        fontSize: 30,
        height: 1.08,
        color: ink,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineSmall: display.copyWith(
        fontSize: 23,
        height: 1.15,
        color: ink,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: display.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -0.2,
      ),
      titleMedium: display.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -0.1,
      ),
      bodyMedium: body.copyWith(fontSize: 15, height: 1.45, color: ink),
      labelLarge: body.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: ink,
      ),
      bodySmall: body.copyWith(fontSize: 13, height: 1.4, color: muted),
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.violet,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.accent,
      secondary: AppColors.violet,
      surface: surface,
      onSurface: ink,
      error: AppColors.danger,
      outline: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: paper,
      colorScheme: scheme,
      textTheme: text,
      dividerColor: border,
      iconTheme: const IconThemeData(color: ink),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 20),
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
          foregroundColor: AppColors.lavender,
          side: BorderSide(color: AppColors.lavender.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.lavender),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.glassFill,
        selectedColor: AppColors.accentSoft,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        labelStyle: text.bodySmall?.copyWith(color: ink),
        secondaryLabelStyle: text.bodySmall?.copyWith(color: AppColors.accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        hintStyle: text.bodyMedium?.copyWith(color: AppColors.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.graphite,
        indicatorColor: AppColors.accent,
        dividerColor: Colors.transparent,
      ),
    );
  }
}
