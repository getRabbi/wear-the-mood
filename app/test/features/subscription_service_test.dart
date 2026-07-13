import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/credits.dart';
import 'package:app/data/models/entitlement.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/paywall/account_status.dart';
import 'package:app/features/paywall/billing_providers.dart';
import 'package:app/features/paywall/subscription_service.dart';

/// Fake store client — no live RevenueCat. Returns canned offers/results (with an
/// optional CustomerInfo entitlement snapshot) and records identity, top-up, and
/// listener-binding calls so tests can assert on them.
class _FakeRevenueCatClient implements RevenueCatClient {
  _FakeRevenueCatClient({
    this.offersResult = const [],
    this.purchaseResult = SubscriptionResult.success,
    this.restoreResult = SubscriptionResult.success,
    this.purchaseEntitlement,
    this.restoreEntitlement,
  });

  final List<SubscriptionOffer> offersResult;
  final SubscriptionResult purchaseResult;
  final SubscriptionResult restoreResult;
  final StoreEntitlement? purchaseEntitlement;
  final StoreEntitlement? restoreEntitlement;
  static const topUpResult = SubscriptionResult.success;

  int purchaseCalls = 0;
  final List<String> loggedInIds = [];
  int logOutCalls = 0;
  final List<String> topUpProductIds = [];
  int bindCalls = 0;
  void Function(StoreEntitlement)? listener;

  @override
  Future<List<SubscriptionOffer>> offers() async => offersResult;

  @override
  Future<StorePurchaseResult> purchase(String offerId) async {
    purchaseCalls++;
    return StorePurchaseResult(purchaseResult, entitlement: purchaseEntitlement);
  }

  @override
  Future<StorePurchaseResult> restore() async =>
      StorePurchaseResult(restoreResult, entitlement: restoreEntitlement);

  @override
  Future<void> logIn(String userId) async => loggedInIds.add(userId);

  @override
  Future<void> logOut() async => logOutCalls++;

  @override
  Future<StorePurchaseResult> purchaseTopUp(String productId) async {
    topUpProductIds.add(productId);
    return const StorePurchaseResult(topUpResult);
  }

  @override
  Future<StoreEntitlement?> customerInfo() async => purchaseEntitlement;

  @override
  void bindEntitlementListener(void Function(StoreEntitlement) onUpdate) {
    bindCalls++;
    listener = onUpdate;
  }
}

/// Fake credits repo returning a scripted sequence (last entry repeats) so a
/// bounded sync poll can be exercised deterministically.
class _FakeCreditsRepo implements CreditsRepository {
  _FakeCreditsRepo(this._responses);

  final List<Credits> _responses;
  int calls = 0;

  @override
  Future<Credits> getCredits() async {
    final credits = _responses[calls.clamp(0, _responses.length - 1)];
    calls++;
    return credits;
  }
}

Credits _credits({
  String tier = 'free',
  int total = 0,
  int monthly = 0,
  int topup = 0,
}) => Credits(
  balance: monthly,
  dailyFreeUsed: 0,
  dailyFreeLimit: 3,
  dailyFreeRemaining: 3,
  topupBalance: topup,
  totalAvailable: total,
  tier: tier,
  monthlyCredits: monthly,
  hdAllowed: tier == 'pro_max',
);

ProviderContainer _container({
  required bool configured,
  required bool active,
  RevenueCatClient? client,
  CreditsRepository? creditsRepo,
}) {
  final c = ProviderContainer(
    overrides: [
      revenueCatConfiguredProvider.overrideWithValue(configured),
      entitlementProvider.overrideWith((ref) async => Entitlement(active: active)),
      if (client != null) revenueCatClientProvider.overrideWithValue(client),
      if (creditsRepo != null)
        creditsRepositoryProvider.overrideWithValue(creditsRepo),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

const _fast = [Duration.zero, Duration.zero];

void main() {
  test('not configured + inactive -> notConfigured, never premium', () async {
    final c = _container(configured: false, active: false);
    await c.read(entitlementProvider.future);

    expect(c.read(subscriptionStatusProvider), SubscriptionStatus.notConfigured);
    final svc = c.read(subscriptionServiceProvider);
    expect(svc.isConfigured, isFalse);
    expect(svc.isPremiumUser(), isFalse);
    expect(await svc.purchase('annual'), SubscriptionResult.notConfigured);
    expect(await svc.restorePurchases(), SubscriptionResult.notConfigured);
  });

  test('configured + inactive -> free (purchase path available)', () async {
    final c = _container(configured: true, active: false);
    await c.read(entitlementProvider.future);
    expect(c.read(subscriptionStatusProvider), SubscriptionStatus.free);
    expect(c.read(subscriptionServiceProvider).isPremiumUser(), isFalse);
  });

  test('active entitlement -> premium even if RevenueCat unconfigured', () async {
    final c = _container(configured: false, active: true);
    await c.read(entitlementProvider.future);
    expect(c.read(subscriptionStatusProvider), SubscriptionStatus.premium);
    expect(c.read(subscriptionServiceProvider).isPremiumUser(), isTrue);
  });

  test('not configured: getOffers returns empty (no client call)', () async {
    final c = _container(configured: false, active: false);
    expect(await c.read(subscriptionServiceProvider).getOffers(), isEmpty);
  });

  test('configured: getOffers returns the store offers', () async {
    final client = _FakeRevenueCatClient(
      offersResult: const [
        SubscriptionOffer(
          id: 'annual',
          title: 'Annual',
          priceString: r'$59.99',
          isAnnual: true,
        ),
      ],
    );
    final c = _container(configured: true, active: false, client: client);
    final offers = await c.read(subscriptionServiceProvider).getOffers();
    expect(offers, hasLength(1));
    expect(offers.first.id, 'annual');
    expect(offers.first.isAnnual, isTrue);
  });

  test('configured: purchase success refreshes entitlement', () async {
    final client = _FakeRevenueCatClient();
    final c = _container(configured: true, active: false, client: client);
    await c.read(entitlementProvider.future);
    final result = await c.read(subscriptionServiceProvider).purchase('annual');
    expect(result, SubscriptionResult.success);
    expect(client.purchaseCalls, 1);
  });

  test('configured: purchase cancelled / error pass through', () async {
    final cancelled = _FakeRevenueCatClient(
      purchaseResult: SubscriptionResult.cancelled,
    );
    final c1 = _container(configured: true, active: false, client: cancelled);
    expect(
      await c1.read(subscriptionServiceProvider).purchase('x'),
      SubscriptionResult.cancelled,
    );

    final failed = _FakeRevenueCatClient(
      purchaseResult: SubscriptionResult.error,
    );
    final c2 = _container(configured: true, active: false, client: failed);
    expect(
      await c2.read(subscriptionServiceProvider).purchase('x'),
      SubscriptionResult.error,
    );
  });

  test('configured: restore success / failure pass through', () async {
    final ok = _FakeRevenueCatClient(restoreResult: SubscriptionResult.success);
    final c1 = _container(configured: true, active: false, client: ok);
    expect(
      await c1.read(subscriptionServiceProvider).restorePurchases(),
      SubscriptionResult.success,
    );

    final bad = _FakeRevenueCatClient(restoreResult: SubscriptionResult.error);
    final c2 = _container(configured: true, active: false, client: bad);
    expect(
      await c2.read(subscriptionServiceProvider).restorePurchases(),
      SubscriptionResult.error,
    );
  });

  test('restore reflects premium + tier from the restored CustomerInfo', () async {
    final client = _FakeRevenueCatClient(
      restoreEntitlement: const StoreEntitlement(
        active: true,
        productId: 'pro_monthly',
      ),
    );
    final c = _container(configured: true, active: false, client: client);
    await c.read(entitlementProvider.future);
    expect(c.read(isPremiumProvider), isFalse);

    final result = await c
        .read(subscriptionServiceProvider)
        .restorePurchases();
    expect(result, SubscriptionResult.success);
    expect(c.read(localStoreEntitlementProvider)?.active, isTrue);
    expect(c.read(optimisticTierProvider), AccountTier.pro);
    expect(c.read(isPremiumProvider), isTrue);
  });

  // ── immediate optimistic reflection (bridge the webhook gap) ──

  test('purchasing Pro Max reflects proMax + premium IMMEDIATELY', () async {
    final client = _FakeRevenueCatClient();
    final c = _container(configured: true, active: false, client: client);
    await c.read(entitlementProvider.future); // server: not active
    expect(c.read(isPremiumProvider), isFalse);

    final result = await c
        .read(subscriptionServiceProvider)
        .purchase('pro_max_monthly');
    expect(result, SubscriptionResult.success);
    // Reflected before any webhook/backend refresh lands.
    expect(c.read(optimisticTierProvider), AccountTier.proMax);
    expect(c.read(isPremiumProvider), isTrue);
  });

  test('purchasing Pro reflects the pro tier (not proMax)', () async {
    final client = _FakeRevenueCatClient();
    final c = _container(configured: true, active: false, client: client);
    await c.read(subscriptionServiceProvider).purchase('pro_monthly');
    expect(c.read(optimisticTierProvider), AccountTier.pro);
  });

  test('a successful purchase stores the CustomerInfo snapshot locally', () async {
    final client = _FakeRevenueCatClient(
      purchaseEntitlement: const StoreEntitlement(
        active: true,
        productId: 'pro_max_monthly:monthly',
      ),
    );
    final c = _container(configured: true, active: false, client: client);
    await c.read(subscriptionServiceProvider).purchase('pro_max_monthly');
    expect(c.read(localStoreEntitlementProvider)?.active, isTrue);
    expect(
      c.read(localStoreEntitlementProvider)?.productId,
      'pro_max_monthly:monthly',
    );
  });

  // ── identity sync: RevenueCat app_user_id must track the Supabase session ──

  test('syncIdentity(uuid) logs the Supabase UUID into RevenueCat', () async {
    final client = _FakeRevenueCatClient();
    final c = _container(configured: true, active: false, client: client);
    const uuid = '11111111-2222-4333-8444-555555555555';
    await c.read(subscriptionServiceProvider).syncIdentity(uuid);
    expect(client.loggedInIds, [uuid]);
    expect(client.logOutCalls, 0);
  });

  test('syncIdentity(null) logs OUT so the next user starts clean', () async {
    final client = _FakeRevenueCatClient();
    final c = _container(configured: true, active: false, client: client);
    await c.read(subscriptionServiceProvider).syncIdentity(null);
    expect(client.logOutCalls, 1);
    expect(client.loggedInIds, isEmpty);
  });

  test('syncIdentity is a no-op when RevenueCat is unconfigured', () async {
    final client = _FakeRevenueCatClient();
    final c = _container(configured: false, active: false, client: client);
    await c.read(subscriptionServiceProvider).syncIdentity('abc');
    await c.read(subscriptionServiceProvider).syncIdentity(null);
    expect(client.loggedInIds, isEmpty);
    expect(client.logOutCalls, 0);
  });

  test('account switch clears the previous user\'s optimistic plan', () async {
    final client = _FakeRevenueCatClient();
    final c = _container(configured: true, active: false, client: client);
    c.read(optimisticTierProvider.notifier).set(AccountTier.proMax);
    c.read(localStoreEntitlementProvider.notifier).set(
      const StoreEntitlement(active: true, productId: 'pro_max_monthly'),
    );

    await c.read(subscriptionServiceProvider).syncIdentity('new-user-uuid');

    expect(c.read(optimisticTierProvider), isNull);
    expect(c.read(localStoreEntitlementProvider), isNull);
  });

  // ── top-up: purchased OUTSIDE the offering, never confers premium ──

  test('purchaseTopUp buys the topup_40 product id (not a package)', () async {
    final client = _FakeRevenueCatClient();
    final c = _container(configured: true, active: false, client: client);
    final result = await c
        .read(subscriptionServiceProvider)
        .purchaseTopUp('topup_40');
    expect(result, SubscriptionResult.success);
    expect(client.topUpProductIds, ['topup_40']);
    // A top-up must never flip premium or set an optimistic tier.
    expect(c.read(subscriptionServiceProvider).isPremiumUser(), isFalse);
    expect(c.read(optimisticTierProvider), isNull);
  });

  test('purchaseTopUp is notConfigured when RevenueCat has no key', () async {
    final client = _FakeRevenueCatClient();
    final c = _container(configured: false, active: false, client: client);
    expect(
      await c.read(subscriptionServiceProvider).purchaseTopUp('topup_40'),
      SubscriptionResult.notConfigured,
    );
    expect(client.topUpProductIds, isEmpty);
  });

  // ── CustomerInfo update listener: bound exactly once, updates state ──

  test('the CustomerInfo listener is bound at most once', () async {
    final client = _FakeRevenueCatClient();
    final c = _container(configured: true, active: false, client: client);
    final svc = c.read(subscriptionServiceProvider);
    await svc.syncIdentity('11111111-2222-4333-8444-555555555555');
    await svc.getOffers();
    await svc.purchase('pro_monthly');
    await svc.restorePurchases();
    expect(client.bindCalls, 1);
  });

  test('a listener entitlement update reflects premium locally', () async {
    final client = _FakeRevenueCatClient();
    final c = _container(configured: true, active: false, client: client);
    await c.read(entitlementProvider.future);
    await c
        .read(subscriptionServiceProvider)
        .syncIdentity('11111111-2222-4333-8444-555555555555');
    expect(c.read(isPremiumProvider), isFalse);

    client.listener!(
      const StoreEntitlement(active: true, productId: 'pro_max_monthly'),
    );
    expect(c.read(localStoreEntitlementProvider)?.active, isTrue);
    expect(c.read(isPremiumProvider), isTrue);
  });

  // ── bounded backend reconcile ──

  test('syncAfterPurchase stops early + clears optimistic on server catch-up',
      () async {
    final client = _FakeRevenueCatClient();
    final repo = _FakeCreditsRepo([
      _credits(tier: 'pro_max', total: 150, monthly: 150),
    ]);
    final c = _container(
      configured: true,
      active: false,
      client: client,
      creditsRepo: repo,
    );
    c.read(optimisticTierProvider.notifier).set(AccountTier.proMax);

    final synced = await c
        .read(subscriptionServiceProvider)
        .syncAfterPurchase(AccountTier.proMax, backoffs: _fast);

    expect(synced, isTrue);
    expect(repo.calls, 1); // satisfied on the immediate attempt
    expect(c.read(optimisticTierProvider), isNull); // cleared once synced
  });

  test('syncAfterPurchase is bounded when the server never catches up',
      () async {
    final client = _FakeRevenueCatClient();
    final repo = _FakeCreditsRepo([_credits(tier: 'free', total: 3)]);
    final c = _container(
      configured: true,
      active: false,
      client: client,
      creditsRepo: repo,
    );

    final synced = await c
        .read(subscriptionServiceProvider)
        .syncAfterPurchase(AccountTier.pro, backoffs: _fast);

    expect(synced, isFalse);
    expect(repo.calls, _fast.length + 1); // attempts capped
  });

  test('syncAfterTopUp resolves once the balance rises', () async {
    final client = _FakeRevenueCatClient();
    final repo = _FakeCreditsRepo([
      _credits(total: 5),
      _credits(total: 45),
    ]);
    final c = _container(
      configured: true,
      active: false,
      client: client,
      creditsRepo: repo,
    );

    final synced = await c
        .read(subscriptionServiceProvider)
        .syncAfterTopUp(5, backoffs: _fast);

    expect(synced, isTrue);
    expect(repo.calls, 2);
  });
}
