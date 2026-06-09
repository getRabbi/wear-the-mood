import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/profile/profile_screen.dart';
import 'package:app/l10n/app_localizations.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget app() => MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ProfileScreen(),
  );

  testWidgets('guest sees a sign-in prompt', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [signedInEmailProvider.overrideWithValue(null)],
        child: app(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("You're browsing as a guest"), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('signed-in user sees their email and sign-out', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [signedInEmailProvider.overrideWithValue('a@b.com')],
        child: app(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Signed in as a@b.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('delete account asks for confirmation', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [signedInEmailProvider.overrideWithValue('a@b.com')],
        child: app(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete account & data'));
    await tester.pumpAndSettle();

    expect(find.text('Delete your account?'), findsOneWidget);
  });
}
