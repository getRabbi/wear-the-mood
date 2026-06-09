import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/onboarding/onboarding_repository.dart';
import 'package:app/features/onboarding/onboarding_screen.dart';
import 'package:app/l10n/app_localizations.dart';

class _FakeOnboardingRepo extends OnboardingRepository {
  _FakeOnboardingRepo() : super(const FlutterSecureStorage());

  bool completed = false;

  @override
  Future<bool> isComplete() async => completed;

  @override
  Future<void> markComplete() async => completed = true;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap(OnboardingRepository repo) => ProviderScope(
    overrides: [onboardingRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const OnboardingScreen(),
    ),
  );

  testWidgets('value carousel advances with Next', (tester) async {
    await tester.pumpWidget(wrap(_FakeOnboardingRepo()));
    await tester.pumpAndSettle();

    expect(find.text('See it on you'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Your closet, digitized'), findsOneWidget);
  });

  testWidgets('Skip jumps to consent and agreeing completes onboarding', (
    tester,
  ) async {
    final repo = _FakeOnboardingRepo();
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Before we start'), findsOneWidget);

    await tester.tap(find.text("I agree — let's go"));
    await tester.pump(); // run _finish; don't settle (button shows a spinner)
    await tester.pump();

    expect(repo.completed, isTrue);
  });
}
