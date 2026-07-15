import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/credits_repository.dart';

/// The account membership tier — the SINGLE thing that distinguishes Pro from
/// Pro Max. It is derived from the BACKEND ([creditsProvider] → `Credits.tier`),
/// never inferred from the shared `premium` entitlement boolean (§18 — the
/// server owns tier + credit amounts). Ordered free < pro < proMax so we can
/// take the max of the server value and an optimistic post-purchase hint.
enum AccountTier {
  free,
  pro,
  proMax;

  /// UPPERCASE badge label ("FREE" / "PRO" / "PRO MAX").
  String get label => switch (this) {
    AccountTier.free => 'FREE',
    AccountTier.pro => 'PRO',
    AccountTier.proMax => 'PRO MAX',
  };

  bool get isPaid => this != AccountTier.free;

  /// Map a backend tier string (`free` | `pro` | `pro_max`) to the enum.
  static AccountTier fromTier(String tier) => switch (tier) {
    'pro' => AccountTier.pro,
    'pro_max' => AccountTier.proMax,
    _ => AccountTier.free,
  };
}

/// The stronger of two tiers (used to bridge the webhook gap: an optimistic
/// hint never *downgrades* the server truth, only holds a higher tier until the
/// server catches up).
AccountTier _maxTier(AccountTier a, AccountTier b) =>
    a.index >= b.index ? a : b;

/// Infer the tier a store product id confers — used ONLY as a local bridge
/// (the id we just purchased, or an active RevenueCat entitlement's product).
/// The backend remains authoritative; this only avoids a "Free" flash while the
/// webhook settles. Returns null for non-subscription ids (e.g. `topup_40`), so
/// a top-up never reads as a tier. Play sends colon forms
/// (`pro_max_monthly:monthly`) — substring matching covers both. Pro Max is
/// checked first because `pro_max…` also contains `pro`.
AccountTier? tierForProductId(String? productId) {
  if (productId == null || productId.isEmpty) return null;
  final id = productId.toLowerCase();
  if (id.contains('pro_max') || id.contains('promax')) return AccountTier.proMax;
  if (id.contains('pro')) return AccountTier.pro;
  return null;
}

/// A local, SDK-agnostic snapshot of the RevenueCat `CustomerInfo` entitlement
/// (mapped in [revenue_cat_client]) — set right after a purchase from the
/// returned CustomerInfo and by the CustomerInfo update listener. It bridges the
/// gap before the server webhook lands; the backend stays the source of truth
/// for tier + credits, so this NEVER carries a credit balance.
class StoreEntitlement {
  const StoreEntitlement({required this.active, this.productId});

  /// No active store entitlement (post sign-out / non-member).
  static const none = StoreEntitlement(active: false);

  final bool active;
  final String? productId;

  /// The tier this store entitlement implies, if any (null when inactive).
  AccountTier? get tierHint => active ? tierForProductId(productId) : null;
}

/// Optimistic tier set the instant a subscription purchase succeeds at the
/// store, before the backend webhook has been reflected. Cleared once the server
/// catches up (or on sign-out). Never set for top-ups.
class OptimisticTierNotifier extends Notifier<AccountTier?> {
  @override
  AccountTier? build() => null;

  void set(AccountTier? tier) => state = tier;
  void clear() => state = null;
}

final optimisticTierProvider =
    NotifierProvider<OptimisticTierNotifier, AccountTier?>(
      OptimisticTierNotifier.new,
    );

/// The most recent local RevenueCat entitlement snapshot (from a purchase's
/// CustomerInfo or the update listener). Null until observed; reset on sign-out.
class LocalStoreEntitlementNotifier extends Notifier<StoreEntitlement?> {
  @override
  StoreEntitlement? build() => null;

  void set(StoreEntitlement? entitlement) => state = entitlement;
  void clear() => state = null;
}

final localStoreEntitlementProvider =
    NotifierProvider<LocalStoreEntitlementNotifier, StoreEntitlement?>(
      LocalStoreEntitlementNotifier.new,
    );

/// The visible account status — tier + credit buckets + whether we're still
/// loading (show a skeleton) or optimistically ahead of the server (show a
/// subtle "syncing" state). This is the ONE object Home, Profile, and the tier
/// badge read, so tier is resolved consistently everywhere.
class AccountStatus {
  const AccountStatus({
    required this.tier,
    required this.loading,
    required this.syncing,
    required this.totalAvailable,
    required this.topupBalance,
    required this.monthlyCredits,
    required this.dailyFreeRemaining,
    required this.hdAllowed,
  });

  /// The effective tier (server truth, or an optimistic hint while it settles).
  final AccountTier tier;

  /// No account data yet AND no optimistic hint — callers show a skeleton /
  /// neutral placeholder rather than a (wrong) "Free".
  final bool loading;

  /// A paid tier is showing optimistically while the backend catches up.
  final bool syncing;

  final int totalAvailable;
  final int topupBalance;
  final int monthlyCredits;
  final int dailyFreeRemaining;
  final bool hdAllowed;

  bool get premium => tier.isPaid;
}

/// Derived, backend-authoritative account status. Tier comes from
/// `creditsProvider.tier`; an [optimisticTierProvider] / active
/// [localStoreEntitlementProvider] can only hold a *higher* tier transiently
/// (never downgrade the server), so a just-purchased plan shows immediately and
/// then reconciles. Credit amounts are ALWAYS the server's (never local).
final accountStatusProvider = Provider<AccountStatus>((ref) {
  final creditsAsync = ref.watch(creditsProvider);
  final optimistic = ref.watch(optimisticTierProvider);
  final local = ref.watch(localStoreEntitlementProvider);

  final serverTier = creditsAsync.asData?.value.tier;
  final serverTierEnum = serverTier == null
      ? null
      : AccountTier.fromTier(serverTier);

  // Fold the optimistic hint and any active local store entitlement into one
  // "hint" tier (the stronger of the two).
  AccountTier? hint = optimistic;
  final localHint = local?.tierHint;
  if (localHint != null) {
    hint = hint == null ? localHint : _maxTier(hint, localHint);
  }

  final effective = switch ((serverTierEnum, hint)) {
    (final s?, final h?) => _maxTier(s, h),
    (final s?, null) => s,
    (null, final h?) => h,
    (null, null) => AccountTier.free,
  };

  final credits = creditsAsync.asData?.value;
  return AccountStatus(
    tier: effective,
    loading: creditsAsync.isLoading && credits == null && hint == null,
    syncing: hint != null &&
        hint.isPaid &&
        (serverTierEnum == null || serverTierEnum.index < hint.index),
    totalAvailable: credits?.totalAvailable ?? 0,
    topupBalance: credits?.topupBalance ?? 0,
    monthlyCredits: credits?.monthlyCredits ?? 0,
    dailyFreeRemaining: credits?.dailyFreeRemaining ?? 0,
    hdAllowed: credits?.hdAllowed ?? false,
  );
});
