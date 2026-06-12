import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/utils/link_launcher.dart';
import 'package:app/data/repositories/news_repository.dart';
import 'package:app/features/news/news_screen.dart';
import 'package:app/l10n/app_localizations.dart';

import '../helpers/fake_dio.dart';

/// Records the opened URL instead of hitting the platform.
class _FakeLauncher extends LinkLauncher {
  const _FakeLauncher(this.opened);
  final List<String> opened;
  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

Map<String, dynamic> _news(String id) => {
  'id': id,
  'title': 'Headline $id',
  'summary': 'A short summary.',
  'source': 'Wire',
  'url': 'https://example.com/$id',
  'image_url': null,
  'published_at': '2026-06-10T08:00:00Z',
  'created_at': '2026-06-10T09:00:00Z',
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap(Object body, {List<String>? opened}) {
    final (dio, _) = fakeDio((_) => jsonResponse(body));
    return ProviderScope(
      overrides: [
        newsRepositoryProvider.overrideWithValue(NewsRepository(dio)),
        if (opened != null)
          linkLauncherProvider.overrideWithValue(_FakeLauncher(opened)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NewsScreen(),
      ),
    );
  }

  testWidgets('shows the empty state when there is no news', (tester) async {
    await tester.pumpWidget(wrap(<Object>[]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No news yet'), findsOneWidget);
  });

  testWidgets('renders news cards with title and source', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap([_news('a'), _news('b')]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Headline a'), findsOneWidget);
    expect(find.text('Headline b'), findsOneWidget);
    expect(find.text('WIRE'), findsNWidgets(2));
  });

  testWidgets('tapping "In your closet" opens the matches sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (dio, _) = fakeDio((opts) {
      if (opts.path.contains('/closet')) {
        return jsonResponse([
          {'id': 'w1', 'title': 'Beige trench', 'image_url': 'w1.jpg'},
        ]);
      }
      return jsonResponse([_news('a')]);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          newsRepositoryProvider.overrideWithValue(NewsRepository(dio)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NewsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('In your closet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Your closet for this trend'), findsOneWidget);
    expect(find.text('Beige trench'), findsOneWidget);
  });

  testWidgets('tapping a card opens its url', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final opened = <String>[];
    await tester.pumpWidget(wrap([_news('a')], opened: opened));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Headline a'));
    await tester.pump();

    expect(opened, ['https://example.com/a']);
  });
}
