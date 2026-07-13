import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/credits.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/paywall/account_status.dart';

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

/// Container whose credits resolve to [credits]; null means "never loads"
/// (loading state). Optimistic/local hints are set via the returned container.
ProviderContainer _c({Credits? credits}) {
  final container = ProviderContainer(
    overrides: [
      creditsProvider.overrideWith(
        (ref) => credits == null ? Completer<Credits>().future : Future.value(credits),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('AccountTier', () {
    test('fromTier maps backend strings', () {
      expect(AccountTier.fromTier('free'), AccountTier.free);
      expect(AccountTier.fromTier('pro'), AccountTier.pro);
      expect(AccountTier.fromTier('pro_max'), AccountTier.proMax);
      expect(AccountTier.fromTier('mystery'), AccountTier.free);
    });

    test('labels + isPaid', () {
      expect(AccountTier.free.label, 'FREE');
      expect(AccountTier.pro.label, 'PRO');
      expect(AccountTier.proMax.label, 'PRO MAX');
      expect(AccountTier.free.isPaid, isFalse);
      expect(AccountTier.pro.isPaid, isTrue);
      expect(AccountTier.proMax.isPaid, isTrue);
    });
  });

  group('tierForProductId', () {
    test('subscription ids (bare + Play colon form)', () {
      expect(tierForProductId('pro_monthly'), AccountTier.pro);
      expect(tierForProductId('pro_monthly:monthly'), AccountTier.pro);
      expect(tierForProductId('pro_max_monthly'), AccountTier.proMax);
      expect(tierForProductId('pro_max_monthly:monthly'), AccountTier.proMax);
    });

    test('non-subscription / unknown ids confer no tier', () {
      expect(tierForProductId('topup_40'), isNull);
      expect(tierForProductId(''), isNull);
      expect(tierForProductId(null), isNull);
    });
  });

  test('StoreEntitlement.tierHint only when active', () {
    expect(
      const StoreEntitlement(active: true, productId: 'pro_max_monthly').tierHint,
      AccountTier.proMax,
    );
    expect(
      const StoreEntitlement(active: false, productId: 'pro_max_monthly').tierHint,
      isNull,
    );
  });

  group('accountStatusProvider', () {
    test('server free -> free, not premium, not loading', () async {
      final c = _c(credits: _credits(total: 4));
      await c.read(creditsProvider.future);
      final s = c.read(accountStatusProvider);
      expect(s.tier, AccountTier.free);
      expect(s.premium, isFalse);
      expect(s.loading, isFalse);
      expect(s.syncing, isFalse);
      expect(s.totalAvailable, 4);
    });

    test('server pro_max -> proMax with credit buckets', () async {
      final c = _c(credits: _credits(tier: 'pro_max', total: 190, monthly: 150, topup: 40));
      await c.read(creditsProvider.future);
      final s = c.read(accountStatusProvider);
      expect(s.tier, AccountTier.proMax);
      expect(s.premium, isTrue);
      expect(s.monthlyCredits, 150);
      expect(s.topupBalance, 40);
      expect(s.totalAvailable, 190);
    });

    test('optimistic proMax over server free -> proMax + syncing', () async {
      final c = _c(credits: _credits(total: 4));
      await c.read(creditsProvider.future);
      c.read(optimisticTierProvider.notifier).set(AccountTier.proMax);
      final s = c.read(accountStatusProvider);
      expect(s.tier, AccountTier.proMax);
      expect(s.premium, isTrue);
      expect(s.syncing, isTrue); // ahead of the server
    });

    test('optimistic never downgrades a higher server tier', () async {
      final c = _c(credits: _credits(tier: 'pro_max', total: 150, monthly: 150));
      await c.read(creditsProvider.future);
      c.read(optimisticTierProvider.notifier).set(AccountTier.pro);
      final s = c.read(accountStatusProvider);
      expect(s.tier, AccountTier.proMax); // server wins (max)
      expect(s.syncing, isFalse); // server already caught up / ahead
    });

    test('loading with no hint -> loading true (skeleton, not wrong Free)', () {
      final c = _c(credits: null); // never resolves
      final s = c.read(accountStatusProvider);
      expect(s.loading, isTrue);
    });

    test('loading but with optimistic hint -> not loading, shows the tier', () {
      final c = _c(credits: null);
      c.read(optimisticTierProvider.notifier).set(AccountTier.pro);
      final s = c.read(accountStatusProvider);
      expect(s.loading, isFalse);
      expect(s.tier, AccountTier.pro);
      expect(s.syncing, isTrue);
    });

    test('active local store entitlement bridges premium', () async {
      final c = _c(credits: _credits(total: 4));
      await c.read(creditsProvider.future);
      c.read(localStoreEntitlementProvider.notifier).set(
        const StoreEntitlement(active: true, productId: 'pro_monthly'),
      );
      final s = c.read(accountStatusProvider);
      expect(s.tier, AccountTier.pro);
      expect(s.premium, isTrue);
    });
  });
}
