import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/repositories/credits_repository.dart';
import '../../features/paywall/billing_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Credit top-up sheet (board §3.8, P6). There is no consumable credit-pack
/// purchase in the backend — AI credits come from the daily free quota + a
/// membership's monthly pool — so this reflects the REAL balance (server-
/// authoritative [creditsProvider]) and routes "get more" to the membership
/// paywall. Entry: Step-3 credits row, Result credits pill, Inbox · System.
Future<void> showTopUpSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showWtmSheet(
    context,
    title: l10n.wtmTopupTitle,
    subtitle: l10n.wtmTopupSubtitle,
    children: const [_TopUpBody()],
  );
}

class _TopUpBody extends ConsumerWidget {
  const _TopUpBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final creditsAsync = ref.watch(creditsProvider);
    final isPremium = ref.watch(isPremiumProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        creditsAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: WtmSpace.s10),
            child: LoadingShimmer(width: double.infinity, height: 64),
          ),
          error: (_, _) => Text(l10n.wtmTopupReset, style: WtmType.micro),
          data: (c) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Balance pill — coin + serif number (board credits row).
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: WtmColors.pillBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: WtmColors.pillBorder),
                ),
                child: Row(
                  children: [
                    EyebrowLabel(l10n.wtmTopupBalance),
                    const Spacer(),
                    const WtmIcon(WtmGlyph.coin,
                        size: 16, color: WtmColors.gold),
                    const SizedBox(width: WtmSpace.s6),
                    Text('${c.totalAvailable}',
                        style: WtmType.h2
                            .copyWith(fontSize: 19, color: WtmColors.gold)),
                  ],
                ),
              ),
              const SizedBox(height: WtmSpace.s10),
              Text(
                l10n.wtmTopupFreeLeft(c.dailyFreeRemaining),
                style: WtmType.micro,
              ),
              const SizedBox(height: WtmSpace.s6),
              Text(
                isPremium ? l10n.wtmTopupUnlimited : l10n.wtmTopupReset,
                style: WtmType.micro,
              ),
            ],
          ),
        ),
        if (!isPremium) ...[
          const SizedBox(height: WtmSpace.s14),
          GradientCta(
            label: l10n.wtmTopupGetMore,
            icon: const WtmIcon(WtmGlyph.sparkle,
                size: 15, color: WtmColors.ctaText),
            onPressed: () {
              // Close the sheet, then open the membership paywall.
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.push(AppRoute.wtmPaywall);
            },
          ),
        ],
        const SizedBox(height: WtmSpace.s10),
        GhostButton(
          label: l10n.commonClose,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
