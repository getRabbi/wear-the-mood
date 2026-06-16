import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/entitlement.dart';
import 'package:app/features/paywall/billing_providers.dart';
import 'package:app/features/paywall/subscription_service.dart';

ProviderContainer _container({
  required bool configured,
  required bool active,
}) {
  final c = ProviderContainer(
    overrides: [
      revenueCatConfiguredProvider.overrideWithValue(configured),
      entitlementProvider.overrideWith((ref) async => Entitlement(active: active)),
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
}
