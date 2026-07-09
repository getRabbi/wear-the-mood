import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/giveaway/create_giveaway_screen.dart';
import 'package:app/features/giveaway/giveaway_status.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/l10n/app_localizations_en.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final l10n = AppLocalizationsEn();

  test('giveawayStatusStyle maps each status to its user-facing label', () {
    expect(giveawayStatusStyle('available', l10n).label, 'Available');
    expect(giveawayStatusStyle('reserved', l10n).label, 'Pending pickup');
    expect(giveawayStatusStyle('claimed', l10n).label, 'Given away');
    expect(giveawayStatusStyle('closed', l10n).label, 'Cancelled');
  });

  test('giveawayStatusStyle uses a distinct colour per state', () {
    final colors = {
      giveawayStatusStyle('available', l10n).color,
      giveawayStatusStyle('reserved', l10n).color,
      giveawayStatusStyle('claimed', l10n).color,
      giveawayStatusStyle('closed', l10n).color,
    };
    expect(colors.length, 4); // available / pending / given away / cancelled
  });

  Widget host(Widget child) => ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      );

  testWidgets('GiveawayStatusBadge renders the label for each status', (
    tester,
  ) async {
    const cases = {
      'available': 'Available',
      'reserved': 'Pending pickup',
      'claimed': 'Given away',
      'closed': 'Cancelled',
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(
        host(Scaffold(body: GiveawayStatusBadge(status: entry.key))),
      );
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('Create giveaway shows the privacy warning near the fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const CreateGiveawayScreen()));
    await tester.pump();

    // The privacy guidance (no phone/email/address publicly) is present.
    expect(find.textContaining('For your privacy'), findsOneWidget);
  });
}
