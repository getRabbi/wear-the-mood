import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'count_up_text.dart';

/// A compact stat: a prominent value over a small muted label (§5.5 Profile).
/// Tappable when [onTap] is given (e.g. Followers/Following). Pure presentation —
/// it formats nothing and reads no providers; pass the already-resolved [value].
/// Pass [countTo] (a numeric stat) to count the number up when it appears (§4).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
    this.countTo,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  /// When set, the value animates 0 → [countTo] on appear instead of showing
  /// the static [value] string (reduce-motion shows the final number).
  final int? countTo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.md);
    final valueStyle = text.titleLarge?.copyWith(color: AppColors.textPrimary);
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpace.sm,
        horizontal: AppSpace.xs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (countTo != null)
            CountUpText(
              value: countTo!,
              style: valueStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
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
