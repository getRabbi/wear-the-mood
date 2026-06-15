import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Frosted glassmorphism card (CLAUDE.md §4) — a translucent, blurred surface
/// meant to sit over imagery or gradients (hero overlays, floating chips).
/// Falls back gracefully on a plain background (still readable).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.md),
    this.onTap,
    this.borderRadius,
    this.blur = 14,
    this.tint = const Color(0x29FFFFFF),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final double blur;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.card);
    Widget content = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(onTap: onTap, borderRadius: radius, child: content),
    );
  }
}
