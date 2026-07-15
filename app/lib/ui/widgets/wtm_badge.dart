import 'package:flutter/material.dart';

import '../../features/paywall/account_status.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';

/// Tier badge (board `.badge`, §4 `Badge.free / Badge.pro`) — a tiny gradient
/// capsule marking mode/plan tiers. UPPERCASE 8.5px, `.2em` tracking. Pro Max
/// is the strongest tier (violet premium gradient), distinct from Pro's gold.
class WtmBadge extends StatelessWidget {
  const WtmBadge.free({super.key})
      : _label = 'Free',
        _gradient = const LinearGradient(
          begin: Alignment(-0.996, -0.087), // 95°, like the CTA
          end: Alignment(0.996, 0.087),
          colors: [WtmColors.badgeFreeStart, WtmColors.badgeFreeEnd],
        ),
        _textColor = WtmColors.badgeFreeText;

  const WtmBadge.pro({super.key})
      : _label = 'Pro',
        _gradient = const LinearGradient(
          begin: Alignment(-0.996, -0.087),
          end: Alignment(0.996, 0.087),
          colors: [WtmColors.badgeProStart, WtmColors.badgeProEnd],
        ),
        _textColor = WtmColors.ctaText;

  const WtmBadge.proMax({super.key})
      : _label = 'Pro Max',
        _gradient = const LinearGradient(
          begin: Alignment(-0.996, -0.087),
          end: Alignment(0.996, 0.087),
          colors: [WtmColors.badgeProMaxStart, WtmColors.badgeProMaxEnd],
        ),
        _textColor = WtmColors.badgeProMaxText;

  /// The badge for a resolved [AccountTier] (backend-authoritative, §18).
  factory WtmBadge.tier(AccountTier tier, {Key? key}) => switch (tier) {
    AccountTier.free => WtmBadge.free(key: key),
    AccountTier.pro => WtmBadge.pro(key: key),
    AccountTier.proMax => WtmBadge.proMax(key: key),
  };

  final String _label;
  final LinearGradient _gradient;
  final Color _textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), // .badge
      decoration: BoxDecoration(
        gradient: _gradient,
        borderRadius: BorderRadius.circular(WtmRadius.chip),
      ),
      child: Text(
        _label.toUpperCase(),
        style: WtmType.micro.copyWith(
          fontSize: 8.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.7, // .2em × 8.5
          color: _textColor,
        ),
      ),
    );
  }
}
