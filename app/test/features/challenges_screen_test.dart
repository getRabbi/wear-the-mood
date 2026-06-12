import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/data/repositories/challenges_repository.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/challenges/challenges_screen.dart';
import 'package:app/l10n/app_localizations.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _challenge(String id) => {
  'id': id,
  'slug': 'monochrome-$id',
  'title': 'Monochrome $id',
  'prompt': 'Style an all-one-colour look.',
  'cover_url': null,
  'starts_at': '2026-06-01T00:00:00Z',
  'ends_at': null,
  'entry_count': 4,
  'joined_by_me': false,
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrapDio(Dio dio) {
    return ProviderScope(
      overrides: [
        challengesRepositoryProvider.overrideWithValue(
          ChallengesRepository(dio),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ChallengesScreen(),
      ),
    );
  }

  Widget wrap(Object body, {int status = 200}) {
    final (dio, _) = fakeDio((_) => jsonResponse(body, status: status));
    return wrapDio(dio);
  }

  testWidgets('shows the empty state when there are no challenges', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(<Object>[]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No challenges yet'), findsOneWidget);
  });

  testWidgets('renders challenge cards with title and entry count', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap([_challenge('a'), _challenge('b')]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Monochrome a'), findsOneWidget);
    expect(find.text('Monochrome b'), findsOneWidget);
    expect(find.text('4 entries'), findsNWidgets(2));
  });
}
