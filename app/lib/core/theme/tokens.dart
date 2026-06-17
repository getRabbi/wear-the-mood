import 'package:flutter/material.dart';

/// Design tokens — the ONLY place raw values live (CLAUDE.md §4.1).
/// Never hardcode colors/sizes/radii/spacing/motion in widgets; reference these.
///
/// Aesthetic: "Midnight Plum + Soft Lavender + Neon Rose" — a luxury, futuristic
/// AI fashion-tech look. Deep plum backgrounds, dark glassmorphism surfaces,
/// purple→pink gradients, white text on muted-lavender secondaries.
///
/// NOTE: the light- and dark-named tokens both resolve to the dark palette so
/// the whole app reads as premium-dark regardless of which a widget references
/// or the device's system brightness.
abstract final class AppColors {
  // Brand
  static const accent = Color(0xFFF43F7F); // neon rose — primary pink
  static const violet = Color(0xFF8B35FF); // electric purple — secondary
  static const lavender = Color(0xFFC084FC); // accent lavender (highlights)
  static const neon = Color(0xFFFF49C6); // hot magenta edge

  /// Soft translucent lavender used for chips / pills / icon halos on dark.
  static const accentSoft = Color(0x29C084FC); // lavender @ ~16%

  /// Gradient partner for the signature gradient (alias of [violet]).
  static const accentPurple = violet;

  /// THE signature gradient — used ONLY for the hero CTA per screen + the center
  /// Try-On FAB (gradient discipline, §3). Mirrors [AppGradients.brand].
  static const signatureGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentPurple, accent],
  );

  // Surfaces (dark) — refined to a deep near-black with a subtle purple
  // undertone (not flat purple) for stronger contrast + less "AI-utility" glow.
  // *Dark variants alias the same ramp; the app stays premium-dark throughout.
  static const bg = Color(0xFF0E0B14); // page background
  static const paper = bg; // legacy alias for the page background
  static const surface = Color(0xFF17131F); // cards
  static const surfaceElevated = Color(0xFF211B2C); // raised cards / sheets
  static const paperAlt = Color(0xFF15111E); // secondary background
  static const paperDark = bg;
  static const surfaceDark = surface;

  /// Solid hairline border for cards/dividers on the dark ramp.
  static const border = Color(0xFF2A2335);

  /// Light, warm garment-tile background so clothing cutouts pop — fixes the
  /// dark-on-dark thumbnail problem (§2, §5.2). Pair with [textOnLight] labels.
  static const tileLight = Color(0xFFF3EFE9);
  static const textOnLight = Color(0xFF1A1620);

  // Text
  static const ink = Color(0xFFFFFFFF); // primary text (white)
  static const inkDark = Color(0xFFFFFFFF);
  static const graphite = Color(0xFFB9AFC8); // secondary text (muted lavender)
  static const muted = Color(0xFF81758F); // tertiary / disabled text

  /// Canonical text-role names — alias the brand text colors above so the kit
  /// has one source of truth (textPrimary/Secondary/Tertiary).
  static const textPrimary = ink;
  static const textSecondary = graphite;
  static const textTertiary = muted;

  // Lines / placeholders
  static const mist = Color(0xFF2C2142); // shimmer / placeholder block, dividers
  static const glassBorder = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)
  static const glassFill = Color(0x14FFFFFF); // rgba(255,255,255,0.08)

  // Premium / AI dark cards (deep purple-black gradient ends).
  static const premiumInk = Color(0xFF160B26);
  static const premiumInk2 = Color(0xFF2A1A47);

  /// Dark scrim for text/badges layered over imagery.
  static const scrim = Color(0xCC0E0717);

  // Status
  static const success = Color(0xFF4ADE80);
  static const warn = Color(0xFFF0A92E);
  static const danger = Color(0xFFFF5C7A);
}

/// Gradients for CTAs, premium surfaces and glassy overlays (CLAUDE.md §4).
abstract final class AppGradients {
  /// Signature purple→pink — primary CTAs, the center nav button, highlights.
  static const brand = LinearGradient(
    colors: [AppColors.violet, AppColors.accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Deep purple-black for premium / AI dark cards.
  static const premiumDark = LinearGradient(
    colors: [AppColors.premiumInk, AppColors.premiumInk2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Neon edge gradient for AI/premium gradient borders.
  static const neonBorder = LinearGradient(
    colors: [AppColors.violet, AppColors.accent, AppColors.neon],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Subtle translucent white wash for glassmorphism cards over dark/imagery.
  static const glass = LinearGradient(
    colors: [Color(0x16FFFFFF), Color(0x08FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Strong dark image scrim (transparent → near-black) for text over photos.
  static const imageScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xF20E0717)],
    stops: [0.35, 1.0],
  );
}

abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// Standard screen horizontal padding (spec: 20px).
  static const screenH = 20.0;
}

abstract final class AppRadius {
  static const sm = 10.0;
  static const md = 18.0;
  static const card = 24.0; // standard card radius (spec)
  static const lg = 26.0;
  static const xl = 28.0; // large cards / buttons (spec)
  static const pill = 999.0;
}

abstract final class AppShadow {
  /// Very light elevation for resting cards on the plum background.
  static const soft = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  /// Card elevation — deeper on dark.
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x4D000000), blurRadius: 26, offset: Offset(0, 10)),
  ];

  /// A glowing pink shadow for primary CTAs.
  static const accentGlow = <BoxShadow>[
    BoxShadow(color: Color(0x59F43F7F), blurRadius: 24, offset: Offset(0, 10)),
  ];

  /// Violet glow — the floating nav center button.
  static const violetGlow = <BoxShadow>[
    BoxShadow(color: Color(0x5C8B35FF), blurRadius: 26, offset: Offset(0, 10)),
  ];

  /// Deep glow under premium / AI dark cards.
  static const premiumGlow = <BoxShadow>[
    BoxShadow(color: Color(0x668B35FF), blurRadius: 34, offset: Offset(0, 16)),
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
