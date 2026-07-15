import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/data/models/credits.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/paywall/account_status.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/loading_shimmer.dart';
import 'package:app/ui/widgets/wtm_badge.dart';
import 'package:app/ui/widgets/wtm_tier_badge.dart';

Credits _credits({String tier = 'free', int total = 0, int monthly = 0}) =>
    Credits(
      balance: monthly,
      dailyFreeUsed: 0,
      dailyFreeLimit: 3,
      dailyFreeRemaining: 3,
      topupBalance: 0,
      totalAvailable: total,
      tier: tier,
      monthlyCredits: monthly,
      hdAllowed: tier == 'pro_max',
    );

AccountStatus _status({
  AccountTier tier = AccountTier.free,
  bool loading = false,
  int total = 0,
  int monthly = 0,
}) => AccountStatus(
  tier: tier,
  loading: loading,
  syncing: false,
  totalAvailable: total,
  topupBalance: 0,
  monthlyCredits: monthly,
  dailyFreeRemaining: 3,
  hdAllowed: tier == AccountTier.proMax,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ProviderContainer? container,
}) async {
  final app = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
  await tester.pumpWidget(
    container == null
        ? ProviderScope(child: app)
        : UncontrolledProviderScope(container: container, child: app),
  );
}

/// A disposed-on-teardown container with [overrides] (type inferred so the
/// Riverpod `Override` type is never named directly).
ProviderContainer _withStatus(AccountStatus status) {
  final container = ProviderContainer(
    overrides: [accountStatusProvider.overrideWithValue(status)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('WtmBadge.tier renders the right label per tier', (tester) async {
    await _pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WtmBadge.free(),
          WtmBadge.pro(),
          WtmBadge.proMax(),
        ],
      ),
    );
    expect(find.text('FREE'), findsOneWidget);
    expect(find.text('PRO'), findsOneWidget);
    expect(find.text('PRO MAX'), findsOneWidget);
  });

  testWidgets('membership pill shows tier + credits', (tester) async {
    await _pump(
      tester,
      const WtmMembershipPill(),
      container: _withStatus(_status(tier: AccountTier.pro, total: 72)),
    );
    expect(find.text('PRO'), findsOneWidget);
    expect(find.text('72'), findsOneWidget);
  });

  testWidgets('membership pill shows a skeleton while loading', (tester) async {
    await _pump(
      tester,
      const WtmMembershipPill(),
      container: _withStatus(_status(loading: true)),
    );
    expect(find.byType(LoadingShimmer), findsOneWidget);
  });

  testWidgets('membership card: free shows Upgrade', (tester) async {
    await _pump(
      tester,
      const WtmMembershipCard(),
      container: _withStatus(_status(tier: AccountTier.free, total: 4)),
    );
    expect(find.text('FREE'), findsOneWidget);
    expect(find.text('UPGRADE'), findsOneWidget); // GoldPill uppercases
  });

  testWidgets('membership card: Pro Max shows Manage + monthly credits', (
    tester,
  ) async {
    await _pump(
      tester,
      const WtmMembershipCard(),
      container: _withStatus(
        _status(tier: AccountTier.proMax, total: 150, monthly: 150),
      ),
    );
    expect(find.text('PRO MAX'), findsOneWidget);
    expect(find.text('MANAGE MEMBERSHIP'), findsOneWidget);
    expect(find.textContaining('150'), findsWidgets);
  });

  testWidgets('indicator updates live when the tier changes (no restart)', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        creditsProvider.overrideWith((ref) => Future.value(_credits(total: 4))),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: WtmMembershipPill())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('FREE'), findsOneWidget);

    // A purchase reflects optimistically — the pill updates without a restart.
    container.read(optimisticTierProvider.notifier).set(AccountTier.proMax);
    await tester.pump();
    expect(find.text('PRO MAX'), findsOneWidget);
    expect(find.text('FREE'), findsNothing);
  });
}
