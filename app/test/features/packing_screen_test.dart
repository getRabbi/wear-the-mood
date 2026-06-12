import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/repositories/packing_repository.dart';
import 'package:app/features/packing/packing_screen.dart';
import 'package:app/l10n/app_localizations.dart';

import '../helpers/fake_dio.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap(Object body) {
    final (dio, _) = fakeDio((_) => jsonResponse(body));
    return ProviderScope(
      overrides: [
        packingRepositoryProvider.overrideWithValue(PackingRepository(dio)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PackingScreen(),
      ),
    );
  }

  testWidgets('shows the intro until a trip is planned', (tester) async {
    await tester.pumpWidget(wrap({'title': 'x', 'notes': '', 'items': <Object>[]}));
    await tester.pump();

    expect(find.text('Trip length'), findsOneWidget);
    expect(
      find.textContaining("I'll pack a versatile list"),
      findsOneWidget,
    );
  });

  testWidgets('planning a trip shows the packing list', (tester) async {
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap({
        'title': 'Packing for 3 days',
        'notes': '8 pieces for your trip.',
        'items': [
          {'id': 't1', 'title': 'Tee', 'image_url': 't1.jpg'},
        ],
      }),
    );
    await tester.pump();

    await tester.tap(find.text('Pack my bag'));
    await tester.pump(); // loading
    await tester.pump(const Duration(milliseconds: 50)); // result

    expect(find.text('Packing for 3 days'), findsOneWidget);
    expect(find.text('Tee'), findsOneWidget);
  });
}
