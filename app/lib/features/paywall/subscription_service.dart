import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/credits.dart';
import '../../data/repositories/credits_repository.dart';
import 'account_status.dart';
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

/// Outcome of a store purchase/restore: the [status] plus the entitlement
/// snapshot RevenueCat returned in its `CustomerInfo` (null when unknown or on a
/// non-success). Lets the service reflect premium IMMEDIATELY from the store,
/// without waiting on the backend webhook (§18). The backend stays authoritative
/// for tier + credit amounts — this snapshot carries no balance.
class StorePurchaseResult {
  const StorePurchaseResult(this.status, {this.entitlement});

  const StorePurchaseResult.status(SubscriptionResult status)
    : this(status);

  final SubscriptionResult status;
  final StoreEntitlement? entitlement;
}

/// Abstraction over the store SDK so the app + tests never touch RevenueCat
/// directly. The real implementation ([PurchasesRevenueCatClient]) wraps
/// `purchases_flutter`; tests inject a fake.
abstract class RevenueCatClient {
  Future<List<SubscriptionOffer>> offers();
  Future<StorePurchaseResult> purchase(String offerId);
  Future<StorePurchaseResult> restore();

  /// Identify the RevenueCat customer as the Supabase user (the webhook keys on
  /// this exact UUID, §18). Called on sign-in / account switch.
  Future<void> logIn(String userId);

  /// Clear the RevenueCat identity on sign-out so the next user never inherits
  /// the previous user's cached entitlement.
  Future<void> logOut();

  /// Buy a one-time consumable STORE PRODUCT (top-up) OUTSIDE the subscription
  /// Offering — so it never reads as a premium package.
  Future<StorePurchaseResult> purchaseTopUp(String productId);

  /// The current entitlement snapshot from RevenueCat's local cache, or null if
  /// unconfigured / unavailable. Used to reconcile on resume + restore.
  Future<StoreEntitlement?> customerInfo();

  /// Register the ONE CustomerInfo update listener; [onUpdate] fires with each
  /// entitlement snapshot RevenueCat pushes (renewals, cross-device, restore).
  /// Idempotent — binding again just replaces the callback, never stacks SDK
  /// listeners.
  void bindEntitlementListener(void Function(StoreEntitlement) onUpdate);
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

/// A thin, safe subscription layer. Premium is server-verified, but a completed
/// store purchase reflects IMMEDIATELY via the optimistic tier + local
/// entitlement snapshot (bridging the webhook gap, §18); RevenueCat only drives
/// purchase/restore/identity, and only once a public key is configured. The
/// backend stays authoritative for tier + credit amounts — the UI drives a
/// bounded [syncAfterPurchase]/[syncAfterTopUp] poll to reconcile.
class SubscriptionService {
  SubscriptionService(this._ref);

  final Ref _ref;

  bool _listenerBound = false;

  bool get isConfigured => _ref.read(revenueCatConfiguredProvider);

  /// Server-verified premium flag — the same value the AI Try-On gate uses.
  bool isPremiumUser() => _ref.read(isPremiumProvider);

  SubscriptionStatus getEntitlementStatus() =>
      _ref.read(subscriptionStatusProvider);

  /// Re-fetch the server entitlement + credits (e.g. after a purchase/restore or
  /// on resume). Both drive the visible tier, so refresh them together.
  Future<void> refreshSubscription() async {
    _ref.invalidate(entitlementProvider);
    _ref.invalidate(creditsProvider);
  }

  /// Bind the single RevenueCat CustomerInfo update listener (idempotent) so
  /// out-of-band entitlement changes (renewal, cross-device, restore) update the
  /// local snapshot + trigger a server refresh. Safe to call repeatedly.
  void _ensureListenerBound() {
    if (_listenerBound || !isConfigured) return;
    _listenerBound = true;
    _ref.read(revenueCatClientProvider).bindEntitlementListener((snapshot) {
      _ref.read(localStoreEntitlementProvider.notifier).set(snapshot);
      // A live store change usually means the server changed too — reconcile.
      _ref.invalidate(entitlementProvider);
      _ref.invalidate(creditsProvider);
    });
  }

  /// Drop any optimistic / local store entitlement (on sign-out or account
  /// switch) so the next user never inherits the previous user's visible plan.
  void clearLocalEntitlement() {
    _ref.read(optimisticTierProvider.notifier).clear();
    _ref.read(localStoreEntitlementProvider.notifier).clear();
  }

  /// Keep the RevenueCat customer id in lock-step with the Supabase session, so
  /// the webhook's `app_user_id` is always THIS user's UUID and no entitlement
  /// leaks across an account switch (§18). Non-null id → logIn; null → logOut.
  /// Clears the previous identity's optimistic/local state and refreshes server
  /// state. A no-op (and never throws) when RevenueCat has no key yet; failures
  /// are swallowed so a store hiccup can never break the auth flow.
  Future<void> syncIdentity(String? userId) async {
    if (!isConfigured) return;
    _ensureListenerBound();
    // Any cached optimistic/local plan belongs to the PREVIOUS identity.
    clearLocalEntitlement();
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
  /// credits on success so the new top-up shows; NEVER flips premium (the backend
  /// adds to the top-up bucket only, tier untouched).
  Future<SubscriptionResult> purchaseTopUp(String productId) async {
    if (!isConfigured) return SubscriptionResult.notConfigured;
    _ensureListenerBound();
    final result = await _ref
        .read(revenueCatClientProvider)
        .purchaseTopUp(productId);
    if (result.status == SubscriptionResult.success) {
      _ref.invalidate(creditsProvider);
    }
    return result.status;
  }

  /// Available packages from the store. Empty when unconfigured or on any error
  /// (so the paywall degrades to its informational state — never crashes).
  Future<List<SubscriptionOffer>> getOffers() async {
    if (!isConfigured) return const [];
    _ensureListenerBound();
    try {
      return await _ref.read(revenueCatClientProvider).offers();
    } catch (_) {
      return const [];
    }
  }

  /// Purchase a subscription package. On store success it OPTIMISTICALLY reflects
  /// the purchased tier (from the known [offerId] + the returned CustomerInfo) so
  /// the UI updates immediately, then kicks a server refresh. The caller drives
  /// the bounded [syncAfterPurchase] to reconcile with the webhook.
  Future<SubscriptionResult> purchase(String offerId) async {
    if (!isConfigured) return SubscriptionResult.notConfigured;
    _ensureListenerBound();
    final result = await _ref.read(revenueCatClientProvider).purchase(offerId);
    if (result.status == SubscriptionResult.success) {
      final tier = tierForProductId(offerId);
      if (tier != null && tier.isPaid) {
        _ref.read(optimisticTierProvider.notifier).set(tier);
      }
      if (result.entitlement != null) {
        _ref.read(localStoreEntitlementProvider.notifier).set(result.entitlement);
      }
      await refreshSubscription();
    }
    return result.status;
  }

  /// Restore prior purchases; reflects whatever CustomerInfo reports (a restore
  /// may or may not confer premium) and refreshes server state on success.
  Future<SubscriptionResult> restorePurchases() async {
    if (!isConfigured) return SubscriptionResult.notConfigured;
    _ensureListenerBound();
    final result = await _ref.read(revenueCatClientProvider).restore();
    if (result.status == SubscriptionResult.success) {
      final entitlement = result.entitlement;
      if (entitlement != null) {
        _ref.read(localStoreEntitlementProvider.notifier).set(entitlement);
        final tier = entitlement.tierHint;
        if (tier != null && tier.isPaid) {
          _ref.read(optimisticTierProvider.notifier).set(tier);
        }
      }
      await refreshSubscription();
    }
    return result.status;
  }

  /// Reconcile a subscription purchase with the backend: poll `/v1/credits`
  /// until the server tier reaches [expected] (or a bounded timeout), clearing
  /// the optimistic tier once the server catches up. Returns true if synced,
  /// false if still pending (caller shows "still syncing, updates automatically").
  Future<bool> syncAfterPurchase(
    AccountTier expected, {
    @visibleForTesting List<Duration>? backoffs,
  }) {
    return _pollCredits(
      (c) => AccountTier.fromTier(c.tier).index >= expected.index,
      onSynced: () => _ref.read(optimisticTierProvider.notifier).clear(),
      backoffs: backoffs ?? _syncBackoffs,
    );
  }

  /// Reconcile a top-up: poll until the server's total available credits rise
  /// above [baseline]. Returns false if still pending after the bounded window.
  Future<bool> syncAfterTopUp(
    int baseline, {
    @visibleForTesting List<Duration>? backoffs,
  }) {
    return _pollCredits(
      (c) => c.totalAvailable > baseline,
      backoffs: backoffs ?? _syncBackoffs,
    );
  }

  /// Bounded backend poll: an immediate attempt, then short backoff (~8.5s
  /// total by default), stopping the moment [satisfied] holds. Checks the
  /// condition via the repository directly (robust against provider
  /// auto-dispose) while also invalidating [creditsProvider] each round so any
  /// watching UI refreshes. Runs at most `backoffs.length + 1` attempts.
  Future<bool> _pollCredits(
    bool Function(Credits) satisfied, {
    required List<Duration> backoffs,
    void Function()? onSynced,
  }) async {
    final repo = _ref.read(creditsRepositoryProvider);
    for (var attempt = 0; ; attempt++) {
      _ref.invalidate(entitlementProvider);
      _ref.invalidate(creditsProvider);
      try {
        final credits = await repo.getCredits();
        if (satisfied(credits)) {
          onSynced?.call();
          return true;
        }
      } catch (_) {
        // Transient failure — keep trying within the time budget.
      }
      if (attempt >= backoffs.length) return false;
      await Future<void>.delayed(backoffs[attempt]);
    }
  }
}

/// Default post-purchase reconcile schedule: immediate attempt, then these
/// backoffs — ~8.5s total across 7 attempts, stopping early on success (§18).
const _syncBackoffs = [
  Duration(milliseconds: 500),
  Duration(milliseconds: 800),
  Duration(milliseconds: 1200),
  Duration(milliseconds: 1500),
  Duration(milliseconds: 2000),
  Duration(milliseconds: 2500),
];

final subscriptionServiceProvider = Provider<SubscriptionService>(
  (ref) => SubscriptionService(ref),
);

/// Store packages for the paywall (empty unless RevenueCat is configured).
final subscriptionOffersProvider =
    FutureProvider.autoDispose<List<SubscriptionOffer>>((ref) {
      return ref.watch(subscriptionServiceProvider).getOffers();
    });
