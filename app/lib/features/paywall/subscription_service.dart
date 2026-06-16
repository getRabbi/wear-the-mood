import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env/app_env.dart';
import 'billing_providers.dart';

/// High-level subscription state for the paywall UI.
///
/// - [loading]   — entitlement is still being fetched.
/// - [premium]   — the server reports an active entitlement (source of truth, §18).
/// - [free]      — not premium, but RevenueCat is configured so purchase is possible.
/// - [notConfigured] — RevenueCat has no public key yet; purchases are unavailable
///   (the paywall stays informational and AI Try-On still works via credits).
/// - [error]     — entitlement lookup failed (treated as not-premium).
enum SubscriptionStatus { loading, premium, free, notConfigured, error }

/// Outcome of a purchase / restore attempt.
enum SubscriptionResult { success, cancelled, notConfigured, error }

/// Whether a real RevenueCat public key is wired in (env-driven, never hardcoded).
final revenueCatConfiguredProvider = Provider<bool>(
  (ref) => AppEnv.hasRevenueCatConfig,
);

/// Derived paywall status: premium (server) wins; otherwise free-vs-notConfigured
/// depends on whether RevenueCat can actually transact. Never asserts premium
/// from a client claim — it reads the server-verified [entitlementProvider].
final subscriptionStatusProvider = Provider<SubscriptionStatus>((ref) {
  final configured = ref.watch(revenueCatConfiguredProvider);
  return ref.watch(entitlementProvider).when(
    loading: () => SubscriptionStatus.loading,
    error: (_, _) =>
        configured ? SubscriptionStatus.free : SubscriptionStatus.notConfigured,
    data: (e) => e.active
        ? SubscriptionStatus.premium
        : (configured ? SubscriptionStatus.free : SubscriptionStatus.notConfigured),
  );
});

/// A thin, safe subscription layer. Premium is ALWAYS read from the
/// server-verified entitlement (never faked); RevenueCat only drives the
/// purchase/restore actions, and only once a public key is configured.
///
/// Wiring `purchases_flutter` is a deliberate follow-up (gated on the founder's
/// RevenueCat account + Play products): drop the key into the env, add the
/// dependency, then fill the marked TODOs below — no other call site changes.
class SubscriptionService {
  SubscriptionService(this._ref);

  final Ref _ref;

  bool get isConfigured => _ref.read(revenueCatConfiguredProvider);

  /// Server-verified premium flag — the same value the AI Try-On gate uses.
  bool isPremiumUser() => _ref.read(isPremiumProvider);

  SubscriptionStatus getEntitlementStatus() =>
      _ref.read(subscriptionStatusProvider);

  /// Re-fetch the server entitlement (e.g. after a purchase/restore or on resume).
  Future<void> refreshSubscription() async {
    _ref.invalidate(entitlementProvider);
  }

  /// Restore prior purchases. Safe no-op (returns [SubscriptionResult.notConfigured])
  /// until RevenueCat is wired.
  Future<SubscriptionResult> restorePurchases() async {
    if (!isConfigured) return SubscriptionResult.notConfigured;
    // TODO(revenuecat): await Purchases.restorePurchases();
    //   then `await refreshSubscription();` and map the entitlement.
    return SubscriptionResult.notConfigured;
  }

  /// Purchase a plan. Safe no-op until RevenueCat is wired.
  Future<SubscriptionResult> purchase(String planId) async {
    if (!isConfigured) return SubscriptionResult.notConfigured;
    // TODO(revenuecat): fetch the current offering, pick the package matching
    //   [planId], `await Purchases.purchasePackage(pkg)`, handle
    //   PurchasesErrorCode.purchaseCancelledError → cancelled, then
    //   `await refreshSubscription();`.
    return SubscriptionResult.notConfigured;
  }
}

final subscriptionServiceProvider = Provider<SubscriptionService>(
  (ref) => SubscriptionService(ref),
);
