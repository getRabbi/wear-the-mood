import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/quiz.dart';

/// The shareable "Style DNA" card (FEATURES_COMMUNITY_PLUS · Style Quiz) — an
/// editorial result card: a serif headline, a palette strip, a short description
/// and keyword chips. Pure presentation; pass a [StyleResult].
class StyleDnaCard extends StatelessWidget {
  const StyleDnaCard({super.key, required this.result});

  final StyleResult result;

  static Color _parseHex(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return AppColors.graphite;
    return Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppShadow.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.palette.isNotEmpty)
            Row(
              children: [
                for (final hex in result.palette) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _parseHex(hex),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                ],
              ],
            ),
          const SizedBox(height: AppSpace.md),
          Text(
            'STYLE DNA',
            style: text.labelLarge?.copyWith(
              color: AppColors.lavender,
              letterSpacing: 1.5,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          // Serif display headline (Fraunces via the theme's displaySmall).
          Text(
            result.title,
            style: text.displaySmall?.copyWith(color: Colors.white),
          ),
          if (result.description.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              result.description,
              style: text.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ],
          if (result.keywords.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                for (final k in result.keywords)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '#$k',
                      style: text.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
