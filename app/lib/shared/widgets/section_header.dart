import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A consistent section heading: bold title, optional muted subtitle, and an
/// optional trailing text action ("See all"). Used across Home, Closet, Profile
/// (CLAUDE.md §4 — consistent hierarchy + spacing).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.onDark = false,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final titleColor = onDark ? Colors.white : null;
    final subColor = onDark
        ? Colors.white.withValues(alpha: 0.7)
        : AppColors.graphite;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleLarge?.copyWith(color: titleColor)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: text.bodySmall?.copyWith(color: subColor),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}
