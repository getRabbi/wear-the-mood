import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:app/features/wardrobe/wardrobe_insights_screen.dart';
import 'package:app/l10n/app_localizations.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _stat(String id, {required int wears, double? cpw}) => {
  'id': id,
  'title': 'Item $id',
  'image_url': null,
  'wear_count': wears,
  'cost_per_wear': cpw,
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap(Object body) {
    final (dio, _) = fakeDio((_) => jsonResponse(body));
    return ProviderScope(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(WardrobeRepository(dio)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const WardrobeInsightsScreen(),
      ),
    );
  }

  testWidgets('shows the empty state for an empty closet', (tester) async {
    await tester.pumpWidget(wrap({'item_count': 0}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No insights yet'), findsOneWidget);
  });

  testWidgets('renders summary stats and highlights', (tester) async {
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap({
        'item_count': 4,
        'total_spend': 300.0,
        'total_wears': 19,
        'never_worn_count': 1,
        'avg_cost_per_wear': 21.43,
        'most_worn': _stat('a', wears: 10, cpw: 2.0),
        'best_value': _stat('a', wears: 10, cpw: 2.0),
        'biggest_waste': _stat('b', wears: 0),
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Wardrobe insights'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // item count
    expect(find.text(r'$300'), findsOneWidget); // total spend
    expect(find.text('MOST WORN'), findsOneWidget);
    expect(find.text('BEST VALUE'), findsOneWidget);
    expect(find.text('BIGGEST WASTE'), findsOneWidget);
    expect(find.text('Never worn'), findsOneWidget); // biggest-waste trailing
  });
}
