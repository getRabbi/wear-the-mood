import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A compact stat: a prominent value over a small muted label (§5.5 Profile).
/// Tappable when [onTap] is given (e.g. Followers/Following). Pure presentation —
/// it formats nothing and reads no providers; pass the already-resolved [value].
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.md);
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpace.sm,
        horizontal: AppSpace.xs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleLarge?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
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
