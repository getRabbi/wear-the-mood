import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'billing_providers.dart';
import 'revenue_cat_client.dart';
import 'store_config.dart';

/// A purchasable subscription package shown on the paywall (SDK-agnostic DTO so
/// the UI + tests never import the RevenueCat SDK).
class SubscriptionOffer {
  const SubscriptionOffer({
    required this.id,
    required this.title,
    required this.priceString,
    required this.isAnnual,
  });

  final String id; // RevenueCat package identifier
  final String title;
  final String priceString;
  final bool isAnnual;
}

/// Abstraction over the store SDK so the app + tests never touch RevenueCat
/// directly. The real implementation ([PurchasesRevenueCatClient]) wraps
/// `purchases_flutter`; tests inject a fake.
abstract class RevenueCatClient {
  Future<List<SubscriptionOffer>> offers();
  Future<SubscriptionResult> purchase(String offerId);
  Future<SubscriptionResult> restore();

  /// Identify the RevenueCat customer as the Supabase user (the webhook keys on
  /// this exact UUID, §18). Called on sign-in / account switch.
  Future<void> logIn(String userId);

  /// Clear the RevenueCat identity on sign-out so the next user never inherits
  /// the previous user's cached entitlement.
  Future<void> logOut();

  /// Buy a one-time consumable STORE PRODUCT (top-up) OUTSIDE the subscription
  /// Offering — so it never reads as a premium package.
  Future<SubscriptionResult> purchaseTopUp(String productId);
}

/// The store client. Overridden with a fake in tests.
final revenueCatClientProvider = Provider<RevenueCatClient>(
  (ref) => PurchasesRevenueCatClient(),
);

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

/// Whether THIS platform's RevenueCat public key is wired in (env-driven,
/// never hardcoded; iOS and Android each need their own — store_config.dart).
final revenueCatConfiguredProvider = Provider<bool>(
  (ref) => hasRevenueCatConfigFor(defaultTargetPlatform),
);

/// Derived paywall status: premium (server) wins; otherwise free-vs-notConfigured
/// depends on whether RevenueCat can actually transact. Never asserts premium
/// from a client claim — it reads the server-verified [entitlementProvider].
final subscriptionStatusProvider = Provider<SubscriptionStatus>((ref) {
  final configured = ref.watch(revenueCatConfiguredProvider);
  return ref
      .watch(entitlementProvider)
      .when(
        loading: () => SubscriptionStatus.loading,
        error: (_, _) => configured
            ? SubscriptionStatus.free
            : SubscriptionStatus.notConfigured,
        data: (e) => e.active
            ? SubscriptionStatus.premium
            : (configured
                  ? SubscriptionStatus.free
                  : SubscriptionStatus.notConfigured),
      );
});

/// A thin, safe subscription layer. Premium is ALWAYS read from the
/// server-verified entitlement (never faked); RevenueCat only drives the
/// purchase/restore actions, and only once a public key is configured. After a
/// successful purchase/restore we refresh the server entitlement (the webhook is
/// the source of truth, §18).
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

  /// Keep the RevenueCat customer id in lock-step with the Supabase session, so
  /// the webhook's `app_user_id` is always THIS user's UUID and no entitlement
  /// leaks across an account switch (§18). Non-null id → logIn; null → logOut.
  /// Always refreshes the server subscription state for the new identity. A
  /// no-op (and never throws) when RevenueCat has no key yet; failures are
  /// swallowed so a store hiccup can never break the auth flow.
  Future<void> syncIdentity(String? userId) async {
    if (!isConfigured) return;
    final client = _ref.read(revenueCatClientProvider);
    try {
      if (userId != null) {
        await client.logIn(userId);
      } else {
        await client.logOut();
      }
    } catch (_) {
      // Store identity is best-effort; premium stays server-verified regardless.
    }
    await refreshSubscription();
  }

  /// Purchase the one-time top-up consumable (outside the Offering). Refreshes
  /// server state on success so the new top-up credits show; never flips premium
  /// (the backend adds to the top-up bucket only, tier untouched).
  Future<SubscriptionResult> purchaseTopUp(String productId) async {
    if (!isConfigured) return SubscriptionResult.notConfigured;
    final result = await _ref
        .read(revenueCatClientProvider)
        .purchaseTopUp(productId);
    if (result == SubscriptionResult.success) await refreshSubscription();
    return result;
  }

  /// Available packages from the store. Empty when unconfigured or on any error
  /// (so the paywall degrades to its informational state — never crashes).
  Future<List<SubscriptionOffer>> getOffers() async {
    if (!isConfigured) return const [];
    try {
      return await _ref.read(revenueCatClientProvider).offers();
    } catch (_) {
      return const [];
    }
  }

  /// Purchase a package; refreshes the server entitlement on success.
  Future<SubscriptionResult> purchase(String offerId) async {
    if (!isConfigured) return SubscriptionResult.notConfigured;
    final result = await _ref.read(revenueCatClientProvider).purchase(offerId);
    if (result == SubscriptionResult.success) await refreshSubscription();
    return result;
  }

  /// Restore prior purchases; refreshes the server entitlement on success.
  Future<SubscriptionResult> restorePurchases() async {
    if (!isConfigured) return SubscriptionResult.notConfigured;
    final result = await _ref.read(revenueCatClientProvider).restore();
    if (result == SubscriptionResult.success) await refreshSubscription();
    return result;
  }
}

final subscriptionServiceProvider = Provider<SubscriptionService>(
  (ref) => SubscriptionService(ref),
);

/// Store packages for the paywall (empty unless RevenueCat is configured).
final subscriptionOffersProvider =
    FutureProvider.autoDispose<List<SubscriptionOffer>>((ref) {
      return ref.watch(subscriptionServiceProvider).getOffers();
    });
