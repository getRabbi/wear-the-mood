import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';

/// User-facing presentation for a giveaway [status] — the single source of truth
/// for its label + badge colour, so the browse card, the "mine" grid and the
/// detail header all read the same. Maps the backend statuses
/// (`available | reserved | claimed | closed`) to the four product states.
({String label, Color color}) giveawayStatusStyle(
  String status,
  AppLocalizations l10n,
) {
  switch (status) {
    case 'available':
      return (label: l10n.giveawayStatusAvailable, color: AppColors.success);
    case 'reserved':
      return (label: l10n.giveawayStatusPending, color: AppColors.warn);
    case 'claimed':
      return (label: l10n.giveawayStatusGiven, color: AppColors.graphite);
    case 'closed':
      return (label: l10n.giveawayStatusCancelled, color: AppColors.danger);
    default:
      return (label: status, color: AppColors.graphite);
  }
}

/// A small pill showing a giveaway's status in its state colour.
class GiveawayStatusBadge extends StatelessWidget {
  const GiveawayStatusBadge({super.key, required this.status, this.compact = false});

  final String status;

  /// Compact = the small overlay used on grid cards; else the roomier detail pill.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = giveawayStatusStyle(status, AppLocalizations.of(context));
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: style.color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
