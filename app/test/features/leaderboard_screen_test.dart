import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/leaderboard.dart';
import 'package:app/data/repositories/social_repository.dart';
import 'package:app/features/community/leaderboard_screen.dart';
import 'package:app/l10n/app_localizations.dart';

/// Issue 4: the leaderboard explains how points are earned, matching the real
/// backend scoring (post +5, like received +1, comment received +3).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap(Leaderboard board) => ProviderScope(
        overrides: [leaderboardProvider.overrideWith((ref) async => board)],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LeaderboardScreen(),
        ),
      );

  testWidgets('"How points work" sheet documents the +5/+1/+3 scoring', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const Leaderboard(month: '2026-06')));
    await tester.pump(); // resolve the leaderboard future

    await tester.tap(find.byTooltip('How points work'));
    await tester.pumpAndSettle();

    expect(find.text('Post a look'), findsOneWidget);
    expect(find.text('Each like your look gets'), findsOneWidget);
    expect(find.text('Each comment your look gets'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
  });
}
