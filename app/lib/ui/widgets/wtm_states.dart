import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import 'wtm_buttons.dart';
import 'wtm_icons.dart';

/// Empty state (§0.4 — "invitation to act, never mood-only"): gold-ringed
/// glyph, serif title, sub, and a primary CTA into the action that fills the
/// screen.
class WtmEmptyState extends StatelessWidget {
  const WtmEmptyState({
    super.key,
    required this.glyph,
    required this.title,
    required this.message,
    this.ctaLabel,
    this.onCta,
  });

  final WtmGlyph glyph;
  final String title;
  final String message;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WtmSpace.s22,
        vertical: WtmSpace.s22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GlyphWell(glyph: glyph),
          const SizedBox(height: WtmSpace.s16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: WtmType.h2.copyWith(fontSize: 19),
          ),
          const SizedBox(height: WtmSpace.s6),
          Text(message, textAlign: TextAlign.center, style: WtmType.sub),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: WtmSpace.s16),
            GradientCta(label: ctaLabel!, onPressed: onCta),
          ],
        ],
      ),
    );
  }
}

/// Error state (§0.4 — what happened + retry).
class WtmErrorState extends StatelessWidget {
  const WtmErrorState({
    super.key,
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WtmSpace.s22,
        vertical: WtmSpace.s22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _GlyphWell(glyph: WtmGlyph.shield, color: WtmColors.danger),
          const SizedBox(height: WtmSpace.s16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: WtmType.h2.copyWith(fontSize: 19),
          ),
          const SizedBox(height: WtmSpace.s6),
          Text(message, textAlign: TextAlign.center, style: WtmType.sub),
          const SizedBox(height: WtmSpace.s16),
          GhostButton(label: retryLabel, onPressed: onRetry),
        ],
      ),
    );
  }
}

class _GlyphWell extends StatelessWidget {
  const _GlyphWell({required this.glyph, this.color = WtmColors.gold});

  final WtmGlyph glyph;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: WtmColors.riconBg,
        border: Border.all(color: WtmColors.riconBorder),
      ),
      alignment: Alignment.center,
      child: WtmIcon(glyph, size: 26, color: color),
    );
  }
}
