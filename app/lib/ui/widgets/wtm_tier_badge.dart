import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../features/paywall/account_status.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import 'wtm_badge.dart';
import 'wtm_buttons.dart';
import 'wtm_icons.dart';

/// The one place account tier is rendered as a badge. Driven by the
/// backend-authoritative [accountStatusProvider] (never the shared premium
/// boolean), so Pro vs Pro Max is always correct. Shows a shimmer while the
/// first load is in flight so it never flashes a wrong "Free"; after a purchase
/// the optimistic bridge means it shows the new tier immediately.
class WtmTierBadge extends ConsumerWidget {
  const WtmTierBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(accountStatusProvider);
    if (status.loading) {
      return const LoadingShimmer(
        width: 46,
        height: 18,
        borderRadius: BorderRadius.all(Radius.circular(WtmRadius.chip)),
      );
    }
    return WtmBadge.tier(status.tier);
  }
}

/// Compact membership indicator for the Home header — the tier badge + total
/// available credits (e.g. `PRO ◎ 72`). Taps into the membership/paywall view.
/// Shows a slim skeleton while loading rather than a stale "Free".
class WtmMembershipPill extends ConsumerWidget {
  const WtmMembershipPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(accountStatusProvider);

    if (status.loading) {
      return const LoadingShimmer(
        width: 92,
        height: 28,
        borderRadius: BorderRadius.all(Radius.circular(WtmRadius.chip)),
      );
    }

    return Semantics(
      button: true,
      label:
          '${status.tier.label}. ${l10n.wtmMembershipCredits(status.totalAvailable)}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push(AppRoute.wtmPaywall),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: WtmColors.pillBg,
              borderRadius: BorderRadius.circular(WtmRadius.chip),
              border: Border.all(color: WtmColors.pillBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WtmBadge.tier(status.tier),
                const SizedBox(width: WtmSpace.s6),
                const WtmIcon(WtmGlyph.coin, size: 13, color: WtmColors.gold),
                const SizedBox(width: 3),
                Text(
                  '${status.totalAvailable}',
                  style: WtmType.labelMedium.copyWith(color: WtmColors.gold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Profile membership section (near the header): tier badge + status +
/// the real credit breakdown + an Upgrade (free) / Manage (paid) action. Never
/// exposes billing ids / RevenueCat ids / the Supabase UUID — only the tier and
/// server credit counts. The whole card opens the membership/paywall view.
class WtmMembershipCard extends ConsumerWidget {
  const WtmMembershipCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(accountStatusProvider);

    final statusLine = status.syncing
        ? l10n.wtmMembershipSyncing
        : (status.tier.isPaid
              ? l10n.wtmMembershipActive
              : l10n.wtmMembershipFreeStatus);

    final creditsLine = status.tier.isPaid
        ? [
            l10n.wtmMembershipMonthlyCredits(status.monthlyCredits),
            if (status.topupBalance > 0)
              l10n.wtmMembershipTopupCredits(status.topupBalance),
          ].join('  •  ')
        : l10n.wtmMembershipAvailableCredits(status.totalAvailable);

    return Semantics(
      button: true,
      label: l10n.wtmProfileMembership,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push(AppRoute.wtmPaywall),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: WtmGradients.assistFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: WtmColors.assistBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          status.loading
                              ? const LoadingShimmer(
                                  width: 46,
                                  height: 18,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(WtmRadius.chip),
                                  ),
                                )
                              : WtmBadge.tier(status.tier),
                          const SizedBox(width: WtmSpace.s8),
                          Flexible(
                            child: Text(
                              statusLine,
                              style: WtmType.micro,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: WtmSpace.s8),
                      Text(
                        creditsLine,
                        style: WtmType.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: WtmSpace.s10),
                GoldPill(
                  label: status.tier.isPaid
                      ? l10n.wtmMembershipManage
                      : l10n.wtmMembershipUpgrade,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
