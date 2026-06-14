import 'package:flutter/material.dart';

/// Design tokens — the ONLY place raw values live (CLAUDE.md §4.1).
/// Never hardcode colors/sizes/radii/spacing/motion in widgets; reference these.
///
/// Aesthetic: "Modern Vibrant" — electric violet→pink, soft lilac, deep
/// aubergine. Bold, feminine, futuristic; gradients + glassy surfaces + springy
/// motion for a daily-habit feel.
abstract final class AppColors {
  // Brand
  static const accent = Color(0xFFF0436E); // electric coral-pink — signature
  static const violet = Color(0xFF7B2FF7); // electric violet — secondary
  static const accentSoft = Color(0xFFF3E7FE); // soft lilac tint

  // Light surfaces / text
  static const ink = Color(0xFF1E1326); // deep plum-black text
  static const graphite = Color(0xFF6B6076); // muted mauve-grey
  static const mist = Color(0xFFEBE4F2); // lilac-grey divider/placeholder
  static const paper = Color(0xFFFBF8FE); // lilac-white background
  static const surface = Color(0xFFFFFFFF);

  // Dark surfaces / text (deep aubergine)
  static const inkDark = Color(0xFFF2ECF8);
  static const paperDark = Color(0xFF140C1E);
  static const surfaceDark = Color(0xFF211733);

  // Status
  static const success = Color(0xFF2FBF8F);
  static const warn = Color(0xFFF0A92E);
  static const danger = Color(0xFFE5484D);
}

/// The signature violet→pink brand gradient (CTAs, banners, highlights).
abstract final class AppGradients {
  static const brand = LinearGradient(
    colors: [AppColors.violet, AppColors.accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class AppRadius {
  static const sm = 10.0;
  static const md = 18.0;
  static const lg = 26.0;
  static const pill = 999.0;
}

abstract final class AppShadow {
  /// Soft, violet-tinted elevation — modern, not heavy.
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// A glowing accent shadow for primary CTAs.
  static const accentGlow = <BoxShadow>[
    BoxShadow(color: Color(0x33F0436E), blurRadius: 22, offset: Offset(0, 10)),
  ];
}

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 460);
  static const easing = Curves.easeOutCubic;

  /// Springy emphasis for delightful, tactile interactions (gentle overshoot).
  static const spring = Cubic(0.2, 0.9, 0.2, 1.05);
}
