import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'billing_providers.dart';
import 'paywall_plans.dart';
import 'subscription_service.dart';

/// Contextual paywall (CLAUDE.md §16, §18). Dismissible, annual pre-selected,
/// long trial. Entitlements come from RevenueCat later; the CTA is a marked
/// placeholder for now. Should ship behind a feature flag once flags land (§16).
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvents.paywallViewed);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start(PaywallPlan plan) async {
    final l10n = AppLocalizations.of(context);
    ref
        .read(analyticsProvider)
        .track(AnalyticsEvents.trialStarted, properties: {'plan': plan.id});
    final result =
        await ref.read(subscriptionServiceProvider).purchase(plan.id);
    if (!mounted) return;
    switch (result) {
      case SubscriptionResult.success:
        await ref.read(subscriptionServiceProvider).refreshSubscription();
      case SubscriptionResult.notConfigured:
        // Honest: billing isn't connected yet — point to the working path.
        _snack(l10n.paywallSetupRequired);
      case SubscriptionResult.cancelled:
        break;
      case SubscriptionResult.error:
        _snack(l10n.paywallSetupRequired);
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final result =
        await ref.read(subscriptionServiceProvider).restorePurchases();
    if (!mounted) return;
    switch (result) {
      case SubscriptionResult.success:
        await ref.read(subscriptionServiceProvider).refreshSubscription();
      case SubscriptionResult.notConfigured:
        _snack(l10n.paywallSetupRequired);
      case SubscriptionResult.cancelled:
        break;
      case SubscriptionResult.error:
        _snack(l10n.paywallRestoreNothing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Already subscribed? Reflect it instead of selling again (server-verified).
    if (ref.watch(isPremiumProvider)) {
      return _ActiveState(onClose: () => Navigator.of(context).maybePop());
    }

    final configured = ref.watch(revenueCatConfiguredProvider);

    // When RevenueCat is configured, the plan cards come from live store
    // offerings; otherwise they're the informational placeholder plans (and the
    // CTA shows an honest setup state). On a configured-but-no-offerings/error
    // case, show a friendly "purchases unavailable" screen rather than fake plans.
    List<PaywallPlan> plans;
    if (configured) {
      final offers = ref.watch(subscriptionOffersProvider);
      if (offers.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final data = offers.asData?.value ?? const [];
      if (data.isEmpty) {
        return _UnavailableState(onClose: () => Navigator.of(context).maybePop());
      }
      plans = [
        for (final o in data)
          PaywallPlan(
            id: o.id,
            price: o.priceString,
            annual: o.isAnnual,
            trialDays: 0, // store handles any intro/trial; we don't assume one
            bestValue: o.isAnnual,
          ),
      ];
    } else {
      plans = ref.watch(paywallPlansProvider);
    }

    final selected = plans.firstWhere(
      (p) => p.id == _selectedId,
      orElse: () =>
          plans.firstWhere((p) => p.bestValue, orElse: () => plans.first),
    );

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Hero(
                    title: l10n.paywallTitle,
                    subtitle: l10n.paywallSubtitle,
                    onClose: () => Navigator.of(context).maybePop(),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _ComparisonTable(),
                        const SizedBox(height: AppSpace.lg),
                        for (final plan in plans) ...[
                          _PlanCard(
                            plan: plan,
                            selected: plan.id == selected.id,
                            onTap: () => setState(() => _selectedId = plan.id),
                          ),
                          const SizedBox(height: AppSpace.md),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _BottomBar(
            trialNote: selected.trialDays > 0
                ? l10n.paywallTrialNote(selected.trialDays, selected.price)
                : l10n.paywallPriceNote(selected.price),
            cta: l10n.paywallCta,
            laterLabel: l10n.paywallMaybeLater,
            restoreLabel: l10n.paywallRestore,
            // Restore only makes sense once the store SDK is configured.
            // Until then, surface an honest internal "setup pending" note.
            configured: ref.watch(revenueCatConfiguredProvider),
            setupNote: l10n.paywallSetupBadge,
            onStart: () => _start(selected),
            onLater: () => Navigator.of(context).maybePop(),
            onRestore: _restore,
          ),
        ],
      ),
    );
  }
}

class _ActiveState extends StatelessWidget {
  const _ActiveState({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: AppColors.accent,
                  size: 64,
                ),
                const SizedBox(height: AppSpace.lg),
                Text(
                  l10n.paywallActiveTitle,
                  style: text.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  l10n.paywallActiveBody,
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when RevenueCat is configured but no offerings load (misconfig /
/// store hiccup) — friendly, never a crash. AI Try-On still works via credits.
class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storefront_outlined,
                    color: AppColors.lavender, size: 64),
                const SizedBox(height: AppSpace.lg),
                Text(
                  l10n.paywallUnavailableTitle,
                  style: text.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  l10n.paywallUnavailableBody,
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppRadius.lg),
      ),
      child: Container(
        decoration: const BoxDecoration(gradient: AppGradients.brand),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.sm,
              AppSpace.lg,
              AppSpace.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                const Icon(Icons.auto_awesome, color: Colors.white, size: 44),
                const SizedBox(height: AppSpace.md),
                Text(
                  title,
                  style: text.displaySmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  subtitle,
                  style: text.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Free vs Pro vs Pro Max — the metered-credit comparison, so users grasp the
/// three tiers (and where HD lives) at a glance.
class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    // Each row: label + Free / Pro / Pro Max cell. A String shows a value;
    // true = ✓, false = ✗.
    final rows = <(String, Object?, Object?, Object?)>[
      // Lead with the metered AI credits — the headline difference.
      (
        l10n.premiumFeatureCredits,
        l10n.premiumCreditsFree,
        l10n.premiumCreditsPro,
        l10n.premiumCreditsProMax,
      ),
      // HD / Try-On Max is Pro Max only.
      (l10n.premiumFeatureHd, false, false, true),
      (
        l10n.premiumFeatureDrawers,
        l10n.premiumDrawersFree,
        l10n.premiumDrawersPremium,
        l10n.premiumDrawersPremium,
      ),
      (l10n.premiumFeaturePriority, false, false, true),
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(l10n.premiumComparisonTitle, style: text.titleMedium),
              ),
              Expanded(flex: 2, child: _HeaderCell(label: l10n.premiumCompareFree)),
              Expanded(flex: 2, child: _HeaderCell(label: l10n.premiumComparePro)),
              Expanded(
                flex: 2,
                child: _HeaderCell(label: l10n.premiumCompareProMax, highlight: true),
              ),
            ],
          ),
          const Divider(height: AppSpace.lg),
          for (final (label, free, pro, proMax) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
              child: Row(
                children: [
                  Expanded(flex: 4, child: Text(label, style: text.bodyMedium)),
                  Expanded(flex: 2, child: _CompareCell(value: free)),
                  Expanded(flex: 2, child: _CompareCell(value: pro)),
                  Expanded(flex: 2, child: _CompareCell(value: proMax, highlight: true)),
                ],
              ),
            ),
          const Divider(height: AppSpace.lg),
          Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 15, color: AppColors.success),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  l10n.paywallCreditsNote,
                  style: text.bodySmall?.copyWith(color: AppColors.graphite),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A tier header (Free / Pro / Pro Max); Pro Max is accented.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: text.bodySmall?.copyWith(
        color: highlight ? AppColors.accent : AppColors.graphite,
        fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
      ),
    );
  }
}

/// One comparison cell: a value string, else ✓ (true) / ✗ (false). The Pro Max
/// column is accented.
class _CompareCell extends StatelessWidget {
  const _CompareCell({required this.value, this.highlight = false});

  final Object? value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = value;
    if (v is String) {
      return Text(
        v,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall?.copyWith(
          color: highlight ? AppColors.accent : AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final yes = v == true;
    return Icon(
      yes ? Icons.check_circle_rounded : Icons.remove_rounded,
      size: yes ? 20 : 18,
      color: yes
          ? (highlight ? AppColors.accent : AppColors.success)
          : AppColors.graphite,
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final PaywallPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final period = plan.annual ? l10n.paywallPerYear : l10n.paywallPerMonth;

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easing,
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSoft
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected
                  ? AppColors.accent
                  : Theme.of(context).dividerColor,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.accent : AppColors.graphite,
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (plan.title != null) ...[
                          Text(plan.title!, style: text.titleMedium),
                          const SizedBox(width: AppSpace.sm),
                        ],
                        if (plan.bestValue) _Badge(label: l10n.paywallBestValue),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(plan.price, style: text.titleMedium),
                        const SizedBox(width: AppSpace.xs),
                        Text(period, style: text.bodySmall),
                      ],
                    ),
                    if (plan.subtitle != null) ...[
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        plan.subtitle!,
                        style: text.bodySmall?.copyWith(color: AppColors.graphite),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontSize: 11,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.trialNote,
    required this.cta,
    required this.laterLabel,
    required this.restoreLabel,
    required this.configured,
    required this.setupNote,
    required this.onStart,
    required this.onLater,
    required this.onRestore,
  });

  final String trialNote;
  final String cta;
  final String laterLabel;
  final String restoreLabel;

  /// Whether RevenueCat is configured — gates the Restore button + setup note.
  final bool configured;
  final String setupNote;
  final VoidCallback onStart;
  final VoidCallback onLater;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!configured) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.graphite),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        setupNote,
                        style: text.bodySmall?.copyWith(color: AppColors.graphite),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              Text(
                trialNote,
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpace.sm),
              PrimaryButton(
                label: cta,
                icon: Icons.auto_awesome,
                onPressed: onStart,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(onPressed: onLater, child: Text(laterLabel)),
                  // Restore is only shown once the store SDK is configured.
                  if (configured) ...[
                    Text('·', style: text.bodySmall),
                    TextButton(onPressed: onRestore, child: Text(restoreLabel)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
