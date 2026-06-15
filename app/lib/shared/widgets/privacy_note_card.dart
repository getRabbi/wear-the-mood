import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A soft, reassuring privacy note (CLAUDE.md §10) — used near body/face capture
/// and personal-details forms so sensitive inputs never feel invasive.
class PrivacyNoteCard extends StatelessWidget {
  const PrivacyNoteCard({super.key, required this.message, this.icon = Icons.lock_outline_rounded});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.success),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.success,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
