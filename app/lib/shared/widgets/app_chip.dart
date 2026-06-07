import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Pill chip for filters/tags. Selected uses the signature accent; unselected a
/// neutral surface that adapts to light/dark.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? AppColors.accent : scheme.surfaceContainerHighest;
    final fg = selected ? Colors.white : scheme.onSurface;
    final radius = BorderRadius.circular(AppRadius.pill);

    return Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: AppSpace.xs),
              ],
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
