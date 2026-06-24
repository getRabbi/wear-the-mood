import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/data/repositories/social_repository.dart';
import 'package:app/features/shell/main_shell.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/floating_bottom_nav.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';

import '../helpers/fake_dio.dart';
import '../helpers/fake_wardrobe_items.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget app() {
    // The Community tab builds inside the IndexedStack, so stub its feed to an
    // empty list rather than letting it hit the network.
    final (dio, _) = fakeDio((_) => jsonResponse(<Object>[]));
    return ProviderScope(
      overrides: [
        creditsProvider.overrideWith(
          (ref) async => const Credits(
            balance: 0,
            dailyFreeUsed: 0,
            dailyFreeLimit: 5,
            dailyFreeRemaining: 5,
          ),
        ),
        wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(const <WardrobeItem>[])),
        signedInEmailProvider.overrideWithValue(null),
        socialRepositoryProvider.overrideWithValue(SocialRepository(dio)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MainShell(),
      ),
    );
  }

  testWidgets('shows the floating 5-tab nav and switches tabs', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byType(FloatingBottomNav), findsOneWidget);
    expect(find.text('Open MoodMirror'), findsOneWidget); // Home hero CTA

    // All five nav slots are present (Try-On is the raised center).
    final nav = find.byType(FloatingBottomNav);
    for (final label in const ['Home', 'Closet', 'Try-On', 'Community', 'Profile']) {
      expect(
        find.descendant(of: nav, matching: find.text(label)),
        findsOneWidget,
      );
    }

    // Switching to the Profile tab surfaces the guest prompt.
    await tester.tap(find.descendant(of: nav, matching: find.text('Profile')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("You're browsing as a guest"), findsOneWidget);
  });
}
