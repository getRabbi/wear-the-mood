import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'billing_providers.dart';
import 'paywall_plans.dart';

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

  void _start(PaywallPlan plan) {
    ref
        .read(analyticsProvider)
        .track(AnalyticsEvents.trialStarted, properties: {'plan': plan.id});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).paywallComingSoon)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Already subscribed? Reflect it instead of selling again (server-verified).
    if (ref.watch(isPremiumProvider)) {
      return _ActiveState(onClose: () => Navigator.of(context).maybePop());
    }

    final plans = ref.watch(paywallPlansProvider);
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
            trialNote: l10n.paywallTrialNote(
              selected.trialDays,
              selected.price,
            ),
            cta: l10n.paywallCta,
            laterLabel: l10n.paywallMaybeLater,
            restoreLabel: l10n.paywallRestore,
            onStart: () => _start(selected),
            onLater: () => Navigator.of(context).maybePop(),
            onRestore: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.paywallComingSoon))),
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

/// Free vs Premium feature comparison (redesign spec).
class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final rows = <(String, bool)>[
      (l10n.premiumFeatureRealistic, false),
      (l10n.premiumFeatureHd, false),
      (l10n.premiumFeatureSaveShare, false),
      (l10n.premiumFeatureCredits, false),
      (l10n.premiumFeaturePriority, false),
      (l10n.premiumFeatureWardrobe, false),
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.premiumComparisonTitle, style: text.titleMedium),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  l10n.premiumCompareFree,
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  l10n.premiumComparePremium,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: AppSpace.lg),
          for (final (label, free) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: text.bodyMedium)),
                  SizedBox(
                    width: 56,
                    child: Icon(
                      free ? Icons.check_rounded : Icons.remove_rounded,
                      size: 18,
                      color: free ? AppColors.success : AppColors.graphite,
                    ),
                  ),
                  const SizedBox(
                    width: 64,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
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
                        Text(plan.price, style: text.titleMedium),
                        const SizedBox(width: AppSpace.sm),
                        if (plan.bestValue)
                          _Badge(label: l10n.paywallBestValue),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(period, style: text.bodySmall),
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
    required this.onStart,
    required this.onLater,
    required this.onRestore,
  });

  final String trialNote;
  final String cta;
  final String laterLabel;
  final String restoreLabel;
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
                  Text('·', style: text.bodySmall),
                  TextButton(onPressed: onRestore, child: Text(restoreLabel)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
