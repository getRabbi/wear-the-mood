import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/onboarding/age_gate_repository.dart';
import 'package:app/features/onboarding/age_gate_screen.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/l10n/app_localizations.dart';

/// In-memory repo so the gate's persistence is exercised without the secure-
/// storage platform channel.
class _FakeAgeGateRepo extends AgeGateRepository {
  _FakeAgeGateRepo() : super(const FlutterSecureStorage());
  bool accepted = false;
  @override
  Future<bool> isAccepted() async => accepted;
  @override
  Future<void> markAccepted() async => accepted = true;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap(AgeGateRepository repo) => ProviderScope(
        overrides: [ageGateRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AgeGateScreen(),
        ),
      );

  testWidgets('declaring under 16 blocks politely, then Go back re-opens it', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(_FakeAgeGateRepo()));
    expect(find.text("I'm 16 or older"), findsOneWidget);

    await tester.tap(find.text("I'm under 16"));
    await tester.pumpAndSettle();
    expect(
      find.text('Wear The Mood is available only for users aged 16 or older.'),
      findsOneWidget,
    );
    expect(find.text("I'm 16 or older"), findsNothing);

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(find.text("I'm 16 or older"), findsOneWidget);
  });

  testWidgets('confirming 16+ persists acceptance', (tester) async {
    final repo = _FakeAgeGateRepo();
    await tester.pumpWidget(wrap(repo));

    await tester.tap(find.text("I'm 16 or older"));
    await tester.pumpAndSettle();

    expect(repo.accepted, isTrue);
  });
}
