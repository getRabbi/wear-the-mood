import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/paywall/account_status.dart';
import 'package:app/features/paywall/billing_providers.dart';
import 'package:app/features/paywall/subscription_service.dart';
import 'package:app/ui/home/wtm_mood.dart';
import 'package:app/ui/paywall/wtm_paywall_screen.dart';

/// P6 gate coverage: the real membership paywall on the shipped subscription
/// layer — tier selection, purchase + restore (fake store client), the
/// not-configured honesty, and the server-verified member reflection.

class _FakeMoodRepo implements WtmMoodRepository {
  @override
  Future<double?> read() async => null;
  @override
  Future<void> write(double v) async {}
}

class _FakeRc implements RevenueCatClient {
  String? purchasedId;
  bool restored = false;
  bool cancelNext = false;

  @override
  Future<List<SubscriptionOffer>> offers() async => const [];
  @override
  Future<StorePurchaseResult> purchase(String offerId) async {
    purchasedId = offerId;
    if (cancelNext) {
      return const StorePurchaseResult(SubscriptionResult.cancelled);
    }
    return StorePurchaseResult(
      SubscriptionResult.success,
      entitlement: StoreEntitlement(active: true, productId: offerId),
    );
  }

  @override
  Future<StorePurchaseResult> restore() async {
    restored = true;
    return const StorePurchaseResult(SubscriptionResult.success);
  }

  @override
  Future<void> logIn(String userId) async {}
  @override
  Future<void> logOut() async {}
  @override
  Future<StorePurchaseResult> purchaseTopUp(String productId) async =>
      const StorePurchaseResult(SubscriptionResult.success);
  @override
  Future<String?> topUpPriceString(String productId) async => r'$3.99';
  @override
  Future<StoreEntitlement?> customerInfo() async => null;
  @override
  void bindEntitlementListener(void Function(StoreEntitlement) onUpdate) {}
}

/// Fake credits repo so the post-purchase reconcile resolves on the first
/// attempt (no real network / pending timers) and reflects a Pro Max plan.
class _FakeCreditsRepo implements CreditsRepository {
  @override
  Future<Credits> getCredits() async => const Credits(
    balance: 150,
    dailyFreeUsed: 0,
    dailyFreeLimit: 3,
    dailyFreeRemaining: 3,
    topupBalance: 0,
    totalAvailable: 150,
    tier: 'pro_max',
    monthlyCredits: 150,
    hdAllowed: true,
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder.first);
    await settle(tester);
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    bool configured = true,
    bool premium = false,
    _FakeRc? client,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        wtmMoodRepositoryProvider.overrideWithValue(_FakeMoodRepo()),
        isPremiumProvider.overrideWithValue(premium),
        revenueCatConfiguredProvider.overrideWithValue(configured),
        creditsRepositoryProvider.overrideWithValue(_FakeCreditsRepo()),
        if (client != null)
          revenueCatClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    await settle(tester);
    container.read(goRouterProvider).go(AppRoute.wtmPaywall);
    await settle(tester);
    return container;
  }

  testWidgets('renders the three tiers, Continue and Restore', (tester) async {
    await boot(tester);
    expect(find.byType(WtmPaywallScreen), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Pro Max'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Restore Purchases'), findsOneWidget);
  });

  testWidgets('Continue purchases the pre-selected best-value plan', (
    tester,
  ) async {
    final rc = _FakeRc();
    await boot(tester, client: rc);
    await tapAndSettle(tester, find.text('Continue'));
    expect(rc.purchasedId, 'pro_max_monthly');
  });

  testWidgets('a successful purchase shows the immediate confirmation', (
    tester,
  ) async {
    final rc = _FakeRc();
    await boot(tester, client: rc);
    await tapAndSettle(tester, find.text('Continue'));
    // Instant in-app confirmation for the purchased tier (no push, no reload).
    expect(find.text("You're now Pro Max"), findsOneWidget);
  });

  testWidgets('cancelling a purchase never shows the success confirmation', (
    tester,
  ) async {
    final rc = _FakeRc()..cancelNext = true;
    await boot(tester, client: rc);
    await tapAndSettle(tester, find.text('Continue'));
    expect(find.text("You're now Pro Max"), findsNothing);
    expect(find.text('Purchase cancelled'), findsOneWidget);
  });

  testWidgets('selecting Pro then Continue purchases pro_monthly', (
    tester,
  ) async {
    final rc = _FakeRc();
    await boot(tester, client: rc);
    await tapAndSettle(tester, find.text('Pro'));
    await tapAndSettle(tester, find.text('Continue'));
    expect(rc.purchasedId, 'pro_monthly');
  });

  testWidgets('Restore Purchases calls the store restore', (tester) async {
    final rc = _FakeRc();
    await boot(tester, client: rc);
    await tapAndSettle(tester, find.text('Restore Purchases'));
    expect(rc.restored, isTrue);
  });

  testWidgets('unconfigured billing hides Restore but keeps Continue', (
    tester,
  ) async {
    await boot(tester, configured: false);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Restore Purchases'), findsNothing);
  });

  testWidgets('an active member sees the reflection, not the sell', (
    tester,
  ) async {
    await boot(tester, premium: true);
    expect(find.text("You're an Atelier member"), findsOneWidget);
    expect(find.text('Manage subscription'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });
}
