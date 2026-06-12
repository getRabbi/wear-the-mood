import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/repositories/calendar_repository.dart';
import 'package:app/features/calendar/calendar_screen.dart';
import 'package:app/l10n/app_localizations.dart';

import '../helpers/fake_dio.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap(Object body) {
    final (dio, _) = fakeDio((_) => jsonResponse(body));
    return ProviderScope(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(CalendarRepository(dio)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CalendarScreen(),
      ),
    );
  }

  testWidgets('adding an event then planning shows an outfit per event', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap({
        'plans': [
          {
            'title': 'Gym',
            'suggestion': {
              'title': 'Activewear',
              'rationale': 'Move freely.',
              'items': [
                {'id': 'a1', 'title': 'Joggers', 'image_url': 'a1.jpg'},
              ],
            },
          },
        ],
      }),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Gym');
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();

    expect(find.text('Gym'), findsOneWidget); // the chip

    await tester.tap(find.text('Plan my outfits'));
    await tester.pump(); // loading
    await tester.pump(const Duration(milliseconds: 50)); // result

    expect(find.text('Activewear'), findsOneWidget);
    expect(find.text('Joggers'), findsNothing); // items show as images, not labels
  });
}
