import 'package:flutter/material.dart';

import 'wtm_colors.dart';

/// Bundled WTM font families (pubspec `fonts:` — UI_IMPLEMENTATION.md §0.6).
/// No runtime Google Fonts fetch.
abstract final class WtmFonts {
  static const serif = 'CormorantGaramond'; // 400/500/600 + italics
  static const sans = 'Outfit'; // 300/400/500/600
}

/// Wear The Mood type roles (UI_IMPLEMENTATION.md §1.2), extracted from the
/// board. Letter spacing is the CSS em-tracking × font size (e.g. eyebrow
/// `.30em` × 9 → 2.7). UPPERCASE transforms are applied by widgets/callers,
/// not by styles. Adjust within a role via `copyWith` (H2 runs 17–20 on the
/// board).
abstract final class WtmType {
  /// Display — Cormorant Garamond 500 · 28. Home greeting; emphasize a word
  /// with [goldItalic].
  static const display = TextStyle(
    fontFamily: WtmFonts.serif,
    fontSize: 28,
    fontWeight: FontWeight.w500,
    height: 1.12,
    color: WtmColors.text,
  );

  /// H1 screen title — Cormorant Garamond 500 · 22.
  static const h1 = TextStyle(
    fontFamily: WtmFonts.serif,
    fontSize: 22,
    fontWeight: FontWeight.w500,
    height: 1.12,
    color: WtmColors.text,
  );

  /// H2 card title — Cormorant Garamond 500 · 17–20 (default 18).
  static const h2 = TextStyle(
    fontFamily: WtmFonts.serif,
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.12,
    color: WtmColors.text,
  );

  /// Body — Outfit 300 · 12.5 · line-height 1.5.
  static const body = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 12.5,
    fontWeight: FontWeight.w300,
    height: 1.5,
    color: WtmColors.text,
  );

  /// Subtitle — Outfit 300 · 11.5 · muted (board `.sub`).
  static const sub = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 11.5,
    fontWeight: FontWeight.w300,
    height: 1.5,
    color: WtmColors.muted,
  );

  /// Label — Outfit 400 · 12.5 (row titles; board `.02em` tracking).
  static const label = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
    color: WtmColors.text,
  );

  /// Label (medium) — Outfit 500 · 12.5 (emphasized rows, mode-card titles).
  static const labelMedium = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.25,
    color: WtmColors.text,
  );

  /// Gradient-CTA label — Outfit 600 · 12.5 · `.05em` (color set by button).
  static const ctaLabel = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.625,
    color: WtmColors.ctaText,
  );

  /// Ghost-button label — Outfit 400 · 12 · `.05em`.
  static const ghostLabel = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.6,
    color: WtmColors.text,
  );

  /// Chip label — Outfit 400 · 10.5 · `.06em` (on-state recolors to gold).
  static const chip = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 10.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.63,
    color: WtmColors.muted,
  );

  /// Gold pill label — Outfit 500 · 10 · `.12em` · UPPERCASE (by widget).
  static const pill = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.2,
    color: WtmColors.gold,
  );

  /// Eyebrow — Outfit 500 · 9 · `.30em` · UPPERCASE (by widget) · goldDim.
  static const eyebrow = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 9,
    fontWeight: FontWeight.w500,
    letterSpacing: 2.7,
    color: WtmColors.goldDim,
  );

  /// Micro metadata — Outfit 300 · 10 · `.04em` · faint.
  static const micro = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 10,
    fontWeight: FontWeight.w300,
    letterSpacing: 0.4,
    color: WtmColors.faint,
  );

  /// The board's italic+gold emphasis (e.g. the greeting's highlighted word) —
  /// apply to any serif role: `WtmType.goldItalic(WtmType.display)`.
  static TextStyle goldItalic(TextStyle base) =>
      base.copyWith(fontStyle: FontStyle.italic, color: WtmColors.gold);
}
