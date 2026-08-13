import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/router/routes.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/utils/link_launcher.dart';
import 'package:app/data/repositories/news_repository.dart';
import 'package:app/data/repositories/shop_repository.dart';
import 'package:app/features/news/news_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/discover/wtm_article_web_screen.dart';

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

  testWidgets('tapping "Shop this trend" opens the affiliate link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final opened = <String>[];
    final (dio, _) = fakeDio((opts) {
      if (opts.path.contains('/shop/link')) {
        return jsonResponse({
          'url': 'https://shop.example.com/s?q=trend',
          'label': 'Shop this trend',
          'query': 'trend',
        });
      }
      return jsonResponse([_news('a')]);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          newsRepositoryProvider.overrideWithValue(NewsRepository(dio)),
          shopRepositoryProvider.overrideWithValue(ShopRepository(dio)),
          linkLauncherProvider.overrideWithValue(_FakeLauncher(opened)),
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

    await tester.tap(find.text('Shop this trend'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(opened, ['https://shop.example.com/s?q=trend']);
  });

  testWidgets('tapping a card opens the story INSIDE the app', (tester) async {
    // This legacy newsroom is not reachable from the WTM shell, but it is still
    // compiled and still routed at `/news`, so it keeps the same rule as the
    // shipping one: a Wear The Mood article never hands the reader to a browser.
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final opened = <String>[];
    final (dio, _) = fakeDio((_) => jsonResponse([_news('a')]));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const NewsScreen()),
        GoRoute(
          path: AppRoute.wtmArticleWeb,
          builder: (_, state) =>
              WtmArticleWebScreen(args: state.extra! as WtmArticleWebArgs),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          newsRepositoryProvider.overrideWithValue(NewsRepository(dio)),
          linkLauncherProvider.overrideWithValue(_FakeLauncher(opened)),
          // No WebView platform under test — the reader still enters its route.
          webViewControllerBuilderProvider.overrideWithValue(() => null),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Headline a'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(WtmArticleWebScreen), findsOneWidget);
    expect(
      opened,
      isEmpty,
      reason: 'no external browser may be launched for an article',
    );
  });
}
