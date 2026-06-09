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
  });

  final String id;
  final String price;
  final bool annual;
  final int trialDays;
  final bool bestValue;
}

/// Available plans, annual first (pre-selected — annual converts better, §18).
final paywallPlansProvider = Provider<List<PaywallPlan>>((ref) {
  return const [
    PaywallPlan(
      id: 'annual',
      price: r'$59.99',
      annual: true,
      trialDays: 14,
      bestValue: true,
    ),
    PaywallPlan(id: 'monthly', price: r'$8.99', annual: false, trialDays: 14),
  ];
});
