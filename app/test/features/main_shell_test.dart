import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/shell/main_shell.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/l10n/app_localizations.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget app() => ProviderScope(
    overrides: [
      creditsProvider.overrideWith(
        (ref) async => const Credits(
          balance: 0,
          dailyFreeUsed: 0,
          dailyFreeLimit: 5,
          dailyFreeRemaining: 5,
        ),
      ),
      wardrobeItemsProvider.overrideWith((ref) async => const <WardrobeItem>[]),
      signedInEmailProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const MainShell(),
    ),
  );

  testWidgets('starts on Home and switches tabs via the bottom nav', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Start a try-on'), findsOneWidget);

    await tester.tap(find.text('Wardrobe'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Your closet is empty'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("You're browsing as a guest"), findsOneWidget);
  });
}
