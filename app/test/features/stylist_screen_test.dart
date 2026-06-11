import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/repositories/stylist_repository.dart';
import 'package:app/features/stylist/stylist_screen.dart';
import 'package:app/l10n/app_localizations.dart';

import '../helpers/fake_dio.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap(Object responseBody, {int status = 200}) {
    final (dio, _) = fakeDio((_) => jsonResponse(responseBody, status: status));
    return ProviderScope(
      overrides: [
        stylistRepositoryProvider.overrideWithValue(StylistRepository(dio)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const StylistScreen(),
      ),
    );
  }

  // Flush the controller's awaits (analytics + repo) without settling the
  // infinite shimmer animation.
  Future<void> styleAndFlush(WidgetTester tester) async {
    await tester.tap(find.text('Style me'));
    await tester.pump(); // -> loading
    await tester.pump(const Duration(milliseconds: 100)); // future resolves
  }

  testWidgets('idle shows the intro and a Style me CTA', (tester) async {
    await tester.pumpWidget(
      wrap({'title': '', 'rationale': '', 'items': <Object>[]}),
    );
    await tester.pump();

    expect(find.text('What do I wear today?'), findsOneWidget);
    expect(find.text('Style me'), findsOneWidget);
  });

  testWidgets('a suggestion renders its title, rationale and pieces', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap({
        'title': 'Smart casual',
        'rationale': 'Mild and dry today.',
        'items': [
          {'id': 'a', 'title': 'Tee', 'image_url': 'a.jpg'},
          {'id': 'b', 'title': 'Jeans', 'thumbnail_url': 'b.jpg'},
        ],
      }),
    );
    await tester.pump();

    await styleAndFlush(tester);

    expect(find.text('Smart casual'), findsOneWidget);
    expect(find.text('Mild and dry today.'), findsOneWidget);
    expect(find.text('Style me again'), findsOneWidget);
  });

  testWidgets('an empty closet shows the empty state', (tester) async {
    await tester.pumpWidget(
      wrap({
        'title': 'Your closet is empty',
        'rationale': '',
        'items': <Object>[],
      }),
    );
    await tester.pump();

    await styleAndFlush(tester);

    expect(find.text('Your closet is empty'), findsOneWidget);
    expect(find.text('Add a piece'), findsOneWidget);
  });

  testWidgets('a failure shows the error state with retry', (tester) async {
    await tester.pumpWidget(
      wrap({
        'error': {'code': 'PROVIDER_ERROR', 'message': 'Stylist unavailable.'},
      }, status: 502),
    );
    await tester.pump();

    await styleAndFlush(tester);

    expect(find.text("Couldn't style you"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
