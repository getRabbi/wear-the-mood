import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A compact credits pill — a coin glyph + the remaining count, tappable to open
/// the credits sheet (§4 kit). Pure presentation: pass the resolved [count] and
/// an [onTap]; it reads no providers and changes no behavior.
class CreditPill extends StatelessWidget {
  const CreditPill({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    return Material(
      color: AppColors.accentSoft,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 15,
                color: AppColors.lavender,
              ),
              const SizedBox(width: 5),
              Text(
                '$count',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
