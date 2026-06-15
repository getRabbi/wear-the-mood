import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Deep navy-purple-black card for premium / AI surfaces (CLAUDE.md §4) — the
/// try-on hero, the premium upsell, the AI stylist. Content inside should use
/// light text. Optionally wears a neon gradient border for the most premium
/// moments.
class PremiumDarkCard extends StatelessWidget {
  const PremiumDarkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.onTap,
    this.gradientBorder = false,
    this.borderRadius,
    this.glow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool gradientBorder;
  final BorderRadius? borderRadius;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.card);
    final inner = BorderRadius.circular(
      (radius.topLeft.x - (gradientBorder ? 1.5 : 0)).clamp(0, 999),
    );

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppGradients.premiumDark,
        borderRadius: gradientBorder ? inner : radius,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (gradientBorder) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppGradients.neonBorder,
          borderRadius: radius,
        ),
        child: Padding(padding: const EdgeInsets.all(1.5), child: surface),
      );
    }

    final content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: glow ? AppShadow.premiumGlow : null,
      ),
      child: surface,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: content,
      ),
    );
  }
}
