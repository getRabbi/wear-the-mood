import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/entitlement.dart';
import 'package:app/features/paywall/billing_providers.dart';
import 'package:app/features/paywall/subscription_service.dart';

/// Fake store client — no live RevenueCat. Returns canned offers/results.
class _FakeRevenueCatClient implements RevenueCatClient {
  _FakeRevenueCatClient({
    this.offersResult = const [],
    this.purchaseResult = SubscriptionResult.success,
    this.restoreResult = SubscriptionResult.success,
  });

  final List<SubscriptionOffer> offersResult;
  final SubscriptionResult purchaseResult;
  final SubscriptionResult restoreResult;
  int purchaseCalls = 0;

  @override
  Future<List<SubscriptionOffer>> offers() async => offersResult;

  @override
  Future<SubscriptionResult> purchase(String offerId) async {
    purchaseCalls++;
    return purchaseResult;
  }

  @override
  Future<SubscriptionResult> restore() async => restoreResult;
}

ProviderContainer _container({
  required bool configured,
  required bool active,
  RevenueCatClient? client,
}) {
  final c = ProviderContainer(
    overrides: [
      revenueCatConfiguredProvider.overrideWithValue(configured),
      entitlementProvider.overrideWith((ref) async => Entitlement(active: active)),
      if (client != null) revenueCatClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

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
}
