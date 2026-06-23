import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A subscription option shown on the paywall.
///
/// Prices here are PLACEHOLDERS. Real pricing is remote-config / feature-flag
/// driven and entitlements are verified through RevenueCat + the backend
/// (CLAUDE.md §18); this only shapes the UI until that lands.
class PaywallPlan {
  const PaywallPlan({
    required this.id,
    required this.price,
    required this.annual,
    required this.trialDays,
    this.bestValue = false,
    this.title,
    this.subtitle,
  });

  final String id;
  final String price;
  final bool annual;
  final int trialDays;
  final bool bestValue;

  /// Tier name (e.g. "Pro", "Pro Max") + a one-line benefit, shown on the card
  /// when present. Offerings-driven cards may leave these null.
  final String? title;
  final String? subtitle;
}

/// Placeholder tiers shown until RevenueCat offerings load — Pro vs Pro Max, Pro
/// pre-selected as "Most popular" (§18). Real pricing/packages come from the store.
final paywallPlansProvider = Provider<List<PaywallPlan>>((ref) {
  return const [
    PaywallPlan(
      id: 'pro_monthly',
      title: 'Pro',
      subtitle: '75 AI credits / month',
      price: r'$8.99',
      annual: false,
      trialDays: 14,
      bestValue: true,
    ),
    PaywallPlan(
      id: 'pro_max_monthly',
      title: 'Pro Max',
      subtitle: '150 credits / month + HD Try-On Max',
      price: r'$15.99',
      annual: false,
      trialDays: 14,
    ),
  ];
});
