import 'package:flutter/material.dart';

/// WTM corner radii (UI_IMPLEMENTATION.md §1.3).
abstract final class WtmRadius {
  static const card = 18.0;
  static const tile = 12.0;
  static const button = 15.0;
  static const chip = 999.0;
  static const sheetTop = 26.0;

  /// Arch portal (body-photo frame). The board's `.portal` runs
  /// `border-radius: 158px 158px 22px 22px` — 158 top arch, 22 bottom.
  static const archTop = 158.0;
  static const archBottom = 22.0;
  static const arch = BorderRadius.vertical(
    top: Radius.circular(archTop),
    bottom: Radius.circular(archBottom),
  );
}

/// WTM motion. The board defines the orb's 4.5s ease-in-out breathe; fast/base
/// follow the app-wide motion language (CLAUDE.md §4.1 — subtle, never bouncy).
abstract final class WtmMotion {
  static const fast = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 280);

  /// Full orb breathing loop (board `@keyframes breathe` — 4.5s ease-in-out).
  static const breathe = Duration(milliseconds: 4500);
  static const easing = Curves.easeOutCubic;
}

/// WTM spacing scale (§1.3): 4/6/8/10/12/14/16/18/22.
abstract final class WtmSpace {
  static const s4 = 4.0;
  static const s6 = 6.0;
  static const s8 = 8.0;
  static const s10 = 10.0;
  static const s12 = 12.0;
  static const s14 = 14.0;
  static const s16 = 16.0;
  static const s18 = 18.0;
  static const s22 = 22.0;

  /// Screen horizontal padding (§1.3).
  static const screenH = 18.0;
}
