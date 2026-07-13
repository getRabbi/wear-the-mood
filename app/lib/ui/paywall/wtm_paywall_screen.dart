import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/legal/legal_links.dart';
import '../../core/router/routes.dart';
import '../../features/paywall/account_status.dart';
import '../../features/paywall/billing_providers.dart';
import '../../features/paywall/store_config.dart';
import '../../features/paywall/subscription_service.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import '../widgets/wtm_purchase_success.dart';
import '../widgets/wtm_tier_badge.dart';

/// One paywall tier. [productId] null = the informational Free baseline; the
/// paid ids are the EXISTING RevenueCat product ids (§3.7 — reuse, never mint).
class _Tier {
  const _Tier({
    this.productId,
    required this.name,
    required this.benefits,
    this.badgePro = false,
    this.bestValue = false,
  });

  final String? productId;
  final String name;
  final List<String> benefits;
  final bool badgePro;
  final bool bestValue;

  bool get purchasable => productId != null;
}

/// WTM Paywall (board §3.7, P6) — "Atelier Membership" on the REAL subscription
/// layer. Premium is ALWAYS server-verified ([isPremiumProvider]); RevenueCat
/// only drives purchase/restore, and only once a public key is configured
/// ([revenueCatConfiguredProvider]). Store-compliant: Restore is visible when
/// transacting, price + renewal terms and Privacy/Terms links are shown.
class WtmPaywallScreen extends ConsumerStatefulWidget {
  const WtmPaywallScreen({super.key});

  @override
  ConsumerState<WtmPaywallScreen> createState() => _WtmPaywallScreenState();
}

class _WtmPaywallScreenState extends ConsumerState<WtmPaywallScreen> {
  // Centralized package mapping (features/paywall/store_config.dart) — the
  // same RevenueCat packages carry the Play products today and the App Store
  // products once the owner attaches them.
  static const _proId = StorePackages.proMonthly;
  static const _proMaxId = StorePackages.proMaxMonthly;

  String? _selectedId = _proMaxId; // best value, pre-selected (§18)
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsProvider).track(AnalyticsEvents.paywallViewed);
    });
  }

  /// The live store price for [id], if RevenueCat offerings are loaded; else the
  /// placeholder (§18 — pricing is remote, the UI just reflects it).
  String _price(String id, String fallback) {
    for (final o
        in ref.watch(subscriptionOffersProvider).asData?.value ??
            const <SubscriptionOffer>[]) {
      if (o.id == id) return o.priceString;
    }
    return fallback;
  }

  Future<void> _purchase(String planId) async {
    // Guard against duplicate submissions (double-tap / re-entry while busy).
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    ref
        .read(analyticsProvider)
        .track(AnalyticsEvents.trialStarted, properties: {'plan': planId});
    // The service reflects premium + the purchased tier optimistically on store
    // success (from CustomerInfo), so the UI is already updating before we sync.
    final result = await ref.read(subscriptionServiceProvider).purchase(planId);
    if (!mounted) return;
    switch (result) {
      case SubscriptionResult.success:
        ref
            .read(analyticsProvider)
            .track(
              AnalyticsEvents.subscriptionStarted,
              properties: {'plan': planId},
            );
        final tier = tierForProductId(planId) ?? AccountTier.pro;
        final kind = tier == AccountTier.proMax
            ? PurchaseSuccessKind.proMax
            : PurchaseSuccessKind.pro;
        // Confirm immediately; the dialog drives the bounded backend reconcile.
        final viewMembership = await showWtmPurchaseSuccess(
          context,
          kind: kind,
          runSync: () =>
              ref.read(subscriptionServiceProvider).syncAfterPurchase(tier),
        );
        if (!mounted) return;
        if (viewMembership) {
          // Land on Profile, where the persistent membership section lives.
          wtmPageBack(context);
          context.go(AppRoute.wtmProfile);
        } else {
          // Continue → leave the paywall; it would otherwise show the member
          // reflection now that premium is active.
          wtmPageBack(context);
        }
        return; // Screen is closing — don't reset _busy.
      case SubscriptionResult.notConfigured:
        wtmSnack(context, l10n.wtmPaywallSetup);
      case SubscriptionResult.cancelled:
        // Not a failure — a calm acknowledgement, button restored below.
        wtmSnack(context, l10n.wtmPurchaseCancelled);
      case SubscriptionResult.error:
        wtmSnack(context, l10n.wtmPaywallError);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final result = await ref
        .read(subscriptionServiceProvider)
        .restorePurchases();
    if (!mounted) return;
    switch (result) {
      case SubscriptionResult.success:
        await ref.read(subscriptionServiceProvider).refreshSubscription();
        if (mounted) wtmSnack(context, l10n.wtmPaywallRestored);
      case SubscriptionResult.notConfigured:
        wtmSnack(context, l10n.wtmPaywallSetup);
      case SubscriptionResult.cancelled:
        break;
      case SubscriptionResult.error:
        wtmSnack(context, l10n.wtmPaywallRestoreNothing);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Already a member? Reflect it (server-verified) instead of selling again.
    if (ref.watch(isPremiumProvider)) return _MemberView(busy: _busy);

    final configured = ref.watch(revenueCatConfiguredProvider);
    final tiers = [
      _Tier(
        name: l10n.wtmPaywallFree,
        benefits: [l10n.wtmPaywallFreeB1, l10n.wtmPaywallFreeB2],
      ),
      _Tier(
        productId: _proId,
        name: l10n.wtmPaywallPro,
        badgePro: true,
        benefits: [
          l10n.wtmPaywallProB1,
          l10n.wtmPaywallProB2,
          l10n.wtmPaywallProB3,
        ],
      ),
      _Tier(
        productId: _proMaxId,
        name: l10n.wtmPaywallProMax,
        badgePro: true,
        bestValue: true,
        benefits: [
          l10n.wtmPaywallMaxB1,
          l10n.wtmPaywallMaxB2,
          l10n.wtmPaywallMaxB3,
        ],
      ),
    ];

    return WtmPage(
      fullBleed: true,
      title: l10n.wtmPaywallTitle,
      eyebrow: l10n.wtmPaywallEyebrow,
      children: [
        Text.rich(
          TextSpan(
            text: '${l10n.wtmPaywallHead1} ',
            style: WtmType.display.copyWith(fontSize: 24),
            children: [
              TextSpan(
                text: l10n.wtmPaywallHeadEmph,
                style: WtmType.goldItalic(
                  WtmType.display.copyWith(fontSize: 24),
                ),
              ),
              TextSpan(text: ' ${l10n.wtmPaywallHead2}'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: WtmSpace.s16),
        for (final (i, tier) in tiers.indexed) ...[
          if (i > 0) const SizedBox(height: 9),
          _TierCard(
            tier: tier,
            price: tier.productId == _proId
                ? _price(_proId, r'$8.99')
                : tier.productId == _proMaxId
                ? _price(_proMaxId, r'$15.99')
                : null,
            perMonth: l10n.wtmPaywallPerMonth,
            selected: tier.purchasable && tier.productId == _selectedId,
            onTap: tier.purchasable
                ? () => setState(() => _selectedId = tier.productId)
                : null,
          ),
        ],
        const SizedBox(height: WtmSpace.s16),
        GradientCta(
          label: l10n.wtmPaywallContinue,
          icon: const WtmIcon(
            WtmGlyph.sparkle,
            size: 15,
            color: WtmColors.ctaText,
          ),
          onPressed: _busy || _selectedId == null
              ? null
              : () => _purchase(_selectedId!),
        ),
        // Restore is required by the stores — shown once billing can transact.
        if (configured) ...[
          const SizedBox(height: WtmSpace.s10),
          GhostButton(
            label: l10n.wtmPaywallRestore,
            onPressed: _busy ? null : _restore,
          ),
        ],
        const SizedBox(height: WtmSpace.s12),
        _Terms(l10n: l10n),
      ],
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.price,
    required this.perMonth,
    required this.selected,
    required this.onTap,
  });

  final _Tier tier;
  final String? price;
  final String perMonth;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: tier.name,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: WtmMotion.fast,
            curve: WtmMotion.easing,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: selected ? WtmColors.chipOnBg : null,
              gradient: selected ? null : WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? WtmColors.chipOnBorder : WtmColors.line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tier.bestValue) ...[
                  EyebrowLabel(l10n.wtmPaywallPopular),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        tier.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WtmType.h2,
                      ),
                    ),
                    const SizedBox(width: WtmSpace.s8),
                    if (tier.badgePro)
                      const WtmBadge.pro()
                    else
                      const WtmBadge.free(),
                    const Spacer(),
                    if (price != null)
                      Text(
                        '$price$perMonth',
                        style: WtmType.labelMedium.copyWith(
                          color: WtmColors.gold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s8),
                for (final b in tier.benefits)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const WtmIcon(
                          WtmGlyph.check,
                          size: 12,
                          color: WtmColors.gold,
                        ),
                        const SizedBox(width: WtmSpace.s8),
                        Expanded(
                          child: Text(
                            b,
                            style: WtmType.micro.copyWith(height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Store-required legal footer — renewal terms + Privacy / Terms links.
class _Terms extends StatelessWidget {
  const _Terms({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    Widget link(String label, String url) => Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Text(
            label,
            style: WtmType.micro.copyWith(color: WtmColors.gold),
          ),
        ),
      ),
    );
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: WtmSpace.s6,
        runSpacing: WtmSpace.s4,
        children: [
          Text(l10n.wtmPaywallTerms, style: WtmType.micro),
          link(l10n.wtmPaywallPrivacy, LegalLinks.privacy),
          Text('·', style: WtmType.micro),
          link(l10n.wtmPaywallTermsLink, LegalLinks.terms),
        ],
      ),
    );
  }
}

/// Active-member reflection (server-verified) — no second sell, just manage.
class _MemberView extends ConsumerWidget {
  const _MemberView({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return WtmPage(
      fullBleed: true,
      title: l10n.wtmPaywallTitle,
      eyebrow: l10n.wtmPaywallEyebrow,
      children: [
        const SizedBox(height: WtmSpace.s10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: WtmGradients.assistFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: WtmColors.assistBorder),
          ),
          child: Row(
            children: [
              const TheOrb(size: TheOrb.miniSize),
              const SizedBox(width: WtmSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EyebrowLabel(
                      l10n.wtmPaywallEyebrow,
                      color: WtmColors.assistEyebrow,
                    ),
                    const SizedBox(height: 4),
                    Text(l10n.wtmPaywallMemberTitle, style: WtmType.h2),
                    const SizedBox(height: 4),
                    Text(l10n.wtmPaywallMemberSub, style: WtmType.micro),
                  ],
                ),
              ),
              const SizedBox(width: WtmSpace.s8),
              // The live, server-verified tier (Pro / Pro Max) — trailing so it
              // never crowds the copy at narrow widths.
              const WtmTierBadge(),
            ],
          ),
        ),
        const SizedBox(height: WtmSpace.s16),
        GhostButton(
          label: l10n.wtmPaywallManage,
          icon: const WtmIcon(
            WtmGlyph.chevron,
            size: 15,
            color: WtmColors.text,
          ),
          onPressed: busy
              ? null
              : () => launchUrl(
                  // The store's own subscription manager for THIS platform
                  // (App Store on iOS, Play on Android) — never a web checkout.
                  Uri.parse(manageSubscriptionUrlFor(defaultTargetPlatform)),
                  mode: LaunchMode.externalApplication,
                ),
        ),
      ],
    );
  }
}
