import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/features/paywall/account_status.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/widgets/wtm_purchase_success.dart';

AccountStatus _status({AccountTier tier = AccountTier.proMax, int total = 150}) =>
    AccountStatus(
      tier: tier,
      loading: false,
      syncing: false,
      totalAvailable: total,
      topupBalance: 0,
      monthlyCredits: 150,
      dailyFreeRemaining: 3,
      hdAllowed: true,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Opens the confirmation and returns a Future for the sheet's result. The
  /// caller controls [runSync] to drive syncing / synced / pending states.
  Future<Future<bool>> open(
    WidgetTester tester, {
    required PurchaseSuccessKind kind,
    required Future<bool> Function() runSync,
    AccountStatus? status,
  }) async {
    late Future<bool> result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStatusProvider.overrideWithValue(status ?? _status()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => result = showWtmPurchaseSuccess(
                    context,
                    kind: kind,
                    runSync: runSync,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    return result;
  }

  testWidgets('Pro success shows the Pro confirmation + actions', (tester) async {
    await open(
      tester,
      kind: PurchaseSuccessKind.pro,
      runSync: () async => true,
      status: _status(tier: AccountTier.pro, total: 80),
    );
    await tester.pumpAndSettle();

    expect(find.text("You're now Pro"), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('View membership'), findsOneWidget);
    // Synced → the fresh, server-authoritative total is shown.
    expect(find.textContaining('80'), findsWidgets);
  });

  testWidgets('Pro Max success shows the Pro Max confirmation', (tester) async {
    await open(
      tester,
      kind: PurchaseSuccessKind.proMax,
      runSync: () async => true,
    );
    await tester.pumpAndSettle();
    expect(find.text("You're now Pro Max"), findsOneWidget);
  });

  testWidgets('top-up shows +40 and NO membership action', (tester) async {
    await open(
      tester,
      kind: PurchaseSuccessKind.topUp,
      runSync: () async => true,
      status: _status(tier: AccountTier.free, total: 45),
    );
    await tester.pumpAndSettle();
    expect(find.text('40 credits added'), findsOneWidget);
    expect(find.text('View membership'), findsNothing); // top-up ≠ subscription
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('delayed backend sync shows syncing, then synced (not failure)', (
    tester,
  ) async {
    final gate = Completer<bool>();
    await open(
      tester,
      kind: PurchaseSuccessKind.proMax,
      runSync: () => gate.future,
    );
    await tester.pump();
    // Still reconciling — a calm syncing state, never "purchase failed".
    expect(find.text('Syncing your account…'), findsOneWidget);
    expect(find.textContaining('failed'), findsNothing);

    gate.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Syncing your account…'), findsNothing);
  });

  testWidgets('pending sync shows reassurance + Refresh, not an error', (
    tester,
  ) async {
    await open(
      tester,
      kind: PurchaseSuccessKind.pro,
      runSync: () async => false, // server still catching up
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('still syncing'),
      findsOneWidget,
    );
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.textContaining('failed'), findsNothing);
  });

  testWidgets('Continue resolves false; View membership resolves true', (
    tester,
  ) async {
    final result = await open(
      tester,
      kind: PurchaseSuccessKind.pro,
      runSync: () async => true,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View membership'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });
}
