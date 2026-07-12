import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';

/// The full giveaway disclaimer copy: the P2P safety text (FEATURES_COMMUNITY_PLUS
/// · Giveaway, §10), plus — on iOS only — the App Store-required
/// "Apple is not a sponsor" disclosure (guideline 5.3.4). One helper so create,
/// claim, and detail always show the same, complete text.
String giveawayDisclaimerText(AppLocalizations l10n) =>
    defaultTargetPlatform == TargetPlatform.iOS
    ? '${l10n.giveawayDisclaimer}\n\n${l10n.giveawayAppleDisclosure}'
    : l10n.giveawayDisclaimer;

/// The P2P safety disclaimer shown at create + claim (FEATURES_COMMUNITY_PLUS ·
/// Giveaway, §10): exchanges are between members, keep contact in-app, never
/// post an address/phone, meet safely. On iOS it also carries the Apple
/// non-sponsorship disclosure.
class GiveawayDisclaimer extends StatelessWidget {
  const GiveawayDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.warn.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warn.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 18, color: AppColors.warn),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              giveawayDisclaimerText(l10n),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
