import 'package:flutter/material.dart';

/// Design tokens — the ONLY place raw values live (CLAUDE.md §4.1).
/// Never hardcode colors/sizes/radii/spacing/motion in widgets; reference these.
abstract final class AppColors {
  static const ink = Color(0xFF1A1A1A);
  static const graphite = Color(0xFF6B6B6B);
  static const mist = Color(0xFFE7E4DF);
  static const paper = Color(0xFFFAF8F5);
  static const surface = Color(0xFFFFFFFF);
  static const inkDark = Color(0xFFF2F0EC);
  static const paperDark = Color(0xFF121212);
  static const surfaceDark = Color(0xFF1C1C1C);
  static const accent = Color(0xFFB44C2E); // terracotta — one signature color
  static const accentSoft = Color(0xFFF0D9CF);
  static const success = Color(0xFF3F7D52);
  static const warn = Color(0xFFC9A227);
  static const danger = Color(0xFFB23B3B);
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
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 22.0;
  static const pill = 999.0;
}

abstract final class AppShadow {
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 480);
  static const easing = Curves.easeOutCubic;
}
