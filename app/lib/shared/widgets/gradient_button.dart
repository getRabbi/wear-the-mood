import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'primary_button.dart';

/// The signature gradient CTA. A thin, semantic alias over [PrimaryButton] so
/// callers can use the design-system name (CLAUDE.md §4 component kit) while we
/// keep a single gradient-button implementation.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => PrimaryButton(
    label: label,
    onPressed: onPressed,
    isLoading: isLoading,
    icon: icon,
  );
}

/// Lower-emphasis pill action that pairs with [GradientButton] — a tonal lilac
/// fill with accent text/icon. Use for "secondary" CTAs (Upload clothing, Maybe
/// later, Restore purchase).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
    this.onDark = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  /// When placed on a dark/premium surface, use a translucent white fill.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = onDark ? Colors.white : AppColors.accent;
    final bg = onDark
        ? Colors.white.withValues(alpha: 0.16)
        : AppColors.accentSoft;
    final radius = BorderRadius.circular(AppRadius.pill);

    return Semantics(
      button: true,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: bg,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 50,
              width: expand ? double.infinity : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 19, color: fg),
                      const SizedBox(width: AppSpace.sm),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
