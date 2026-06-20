import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/giveaway.dart';
import 'package:app/data/repositories/giveaway_repository.dart';
import 'package:app/features/giveaway/giveaway_browse_view.dart';
import 'package:app/l10n/app_localizations.dart';

/// Issue 3: the Giveaway section opens with a warm give-it-forward promo banner.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap(List<Giveaway> items) => ProviderScope(
        overrides: [
          giveawayBrowseProvider.overrideWith((ref) async => items),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: GiveawayBrowseView()),
        ),
      );

  testWidgets('shows the give-it-forward promo header', (tester) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const []));
    await tester.pump();

    expect(find.textContaining('Sharing is caring'), findsOneWidget);
    expect(find.textContaining('Pass it on'), findsOneWidget);
  });
}
