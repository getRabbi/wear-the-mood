import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/repositories/credits_repository.dart';
import '../../features/paywall/billing_providers.dart';
import '../../features/paywall/store_config.dart';
import '../../features/paywall/subscription_service.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Credit top-up sheet (board §3.8, P6). Reflects the REAL balance (server-
/// authoritative [creditsProvider]) and, when RevenueCat can transact, sells the
/// one-time 40-credit consumable (`topup_40`, purchased OUTSIDE the subscription
/// offering — it never grants premium; the backend adds it to the top-up bucket).
/// Also offers the membership paywall for unlimited. Entry: Step-3 credits row,
/// Result credits pill, Inbox · System.
Future<void> showTopUpSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showWtmSheet(
    context,
    title: l10n.wtmTopupTitle,
    subtitle: l10n.wtmTopupSubtitle,
    children: const [_TopUpBody()],
  );
}

class _TopUpBody extends ConsumerStatefulWidget {
  const _TopUpBody();

  @override
  ConsumerState<_TopUpBody> createState() => _TopUpBodyState();
}

class _TopUpBodyState extends ConsumerState<_TopUpBody> {
  bool _busy = false;

  Future<void> _buyTopUp() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final result = await ref
        .read(subscriptionServiceProvider)
        .purchaseTopUp(StorePackages.topUp40);
    if (!mounted) return;
    switch (result) {
      case SubscriptionResult.success:
        // Balance is server-authoritative — refresh it so the new credits show.
        ref.invalidate(creditsProvider);
        wtmSnack(context, l10n.wtmTopupSuccess);
      case SubscriptionResult.notConfigured:
        wtmSnack(context, l10n.wtmPaywallSetup);
      case SubscriptionResult.cancelled:
        break;
      case SubscriptionResult.error:
        wtmSnack(context, l10n.wtmPaywallError);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final creditsAsync = ref.watch(creditsProvider);
    final isPremium = ref.watch(isPremiumProvider);
    final canTransact = ref.watch(revenueCatConfiguredProvider);

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
        // One-time 40-credit pack — shown only when billing can actually
        // transact (a public RevenueCat key is wired for this platform).
        if (canTransact) ...[
          const SizedBox(height: WtmSpace.s14),
          GradientCta(
            label: _busy ? l10n.commonPleaseWait : l10n.wtmTopupBuyPack,
            icon: const WtmIcon(WtmGlyph.coin,
                size: 15, color: WtmColors.ctaText),
            onPressed: _busy ? null : _buyTopUp,
          ),
        ],
        if (!isPremium) ...[
          const SizedBox(height: WtmSpace.s10),
          GhostButton(
            label: l10n.wtmTopupGetMore,
            icon: const WtmIcon(WtmGlyph.sparkle,
                size: 15, color: WtmColors.text),
            onPressed: _busy
                ? null
                : () {
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
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
