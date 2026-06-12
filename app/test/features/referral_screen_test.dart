import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/referral.dart';
import 'package:app/data/repositories/referral_repository.dart';
import 'package:app/features/referral/referral_screen.dart';
import 'package:app/l10n/app_localizations.dart';

/// Fake repo so the screen renders + redeems without a network.
class _FakeReferralRepo extends ReferralRepository {
  _FakeReferralRepo() : super(Dio());

  String? lastCode;

  @override
  Future<Referral> getReferral() async =>
      const Referral(code: 'ABCD2345', referralCount: 2, rewardCredits: 5);

  @override
  Future<int> redeem(String code) async {
    lastCode = code;
    return 5;
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap(_FakeReferralRepo fake) => ProviderScope(
    overrides: [referralRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ReferralScreen(),
    ),
  );

  testWidgets('shows the code and redeem field', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(_FakeReferralRepo()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('ABCD2345'), findsOneWidget);
    expect(find.text('Have a code?'), findsOneWidget);
  });

  testWidgets('redeeming a code shows the reward', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fake = _FakeReferralRepo();
    await tester.pumpWidget(wrap(fake));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextField), 'friend123');
    await tester.tap(find.byIcon(Icons.redeem_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.lastCode, 'friend123');
    expect(find.textContaining('You earned 5 credits'), findsOneWidget);
  });
}
