import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/news_item.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/news_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/shared/utils/image_rendition.dart';
import 'package:app/ui/discover/wtm_newsroom_screen.dart';

/// What the media-heavy surfaces actually ask the network for.
///
/// A screenshot cannot tell a 7.94 MB master apart from a 64 KB thumbnail —
/// both eventually draw the same picture — so "the images are slow" was never
/// visible in a widget test. These assert the REQUEST: which URL each card
/// hands the image layer, how many distinct URLs a screenful produces, and
/// whether revisiting the surface changes any of them.
///
/// Production shape, 2026-08-14: 1 503 articles carry an image and 1 283 of
/// them point at `assets.vogue.com/photos/<id>/master/pass/…`, which is the
/// uncropped editorial master. Sampled: 717 KB (3000×4500), 1.72 MB
/// (3024×4032), 7.94 MB (3586×4482).

class _FakeNews implements NewsRepository {
  _FakeNews(this.feed);
  final List<NewsItem> feed;
  int feedCalls = 0;

  @override
  Future<List<NewsItem>> getNews({int limit = 20, DateTime? before}) async {
    feedCalls++;
    return feed;
  }

  @override
  Future<List<WardrobeItem>> getClosetMatches(String newsId) async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

/// A Condé Nast master, exactly as the RSS ingest stores it.
String _master(int i) =>
    'https://assets.vogue.com/photos/6a7df3c57c43c883a806bf3$i/master/pass/'
    'story-$i.jpg';

NewsItem _article(int i) => NewsItem(
  id: 'n$i',
  title: 'Story number $i',
  summary: 'A short standfirst.',
  source: 'Vogue',
  url: 'https://vogue.com/story-$i',
  imageUrl: _master(i),
  createdAt: DateTime.utc(2026, 8, 1),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<(ProviderContainer, _FakeNews)> boot(
    WidgetTester tester, {
    int articles = 6,
  }) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final repo = _FakeNews([for (var i = 0; i < articles; i++) _article(i)]);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        newsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    await settle(tester);
    container.read(goRouterProvider).go(AppRoute.wtmNewsroom);
    await settle(tester);
    expect(find.byType(WtmNewsroomScreen), findsOneWidget);
    return (container, repo);
  }

  /// Every image request the screen has configured, in tree order.
  List<CachedNetworkImage> requests(WidgetTester tester) => [
    for (final element in find.byType(CachedNetworkImage).evaluate())
      element.widget as CachedNetworkImage,
  ];

  group('the Newsroom asks for thumbnails, not editorial masters', () {
    testWidgets('no card requests a master', (tester) async {
      await boot(tester);

      final vogue = requests(
        tester,
      ).where((r) => r.imageUrl.contains('assets.vogue.com')).toList();
      expect(vogue, isNotEmpty, reason: 'the fixture has Vogue artwork');
      for (final r in vogue) {
        expect(
          r.imageUrl,
          isNot(contains('/master/pass/')),
          reason: 'the uncropped master is what made this surface slow',
        );
        expect(r.imageUrl, contains(',c_limit/'));
      }
    });

    testWidgets('each card asks for the width it is drawn at', (tester) async {
      await boot(tester);

      for (final r in requests(tester)) {
        if (!r.imageUrl.contains('assets.vogue.com')) continue;
        final decode = r.memCacheWidth;
        expect(
          decode,
          isNotNull,
          reason: 'a decode cap is what the request width is derived from',
        );
        expect(
          r.imageUrl,
          contains('w_${renditionWidth(decode!)},c_limit'),
          reason: 'the requested rendition must match the drawn size',
        );
      }
    });

    testWidgets('the list thumbnail asks for less than the feature card', (
      tester,
    ) async {
      await boot(tester);

      final widths = <int>{
        for (final r in requests(tester))
          if (r.imageUrl.contains('assets.vogue.com')) r.memCacheWidth!,
      };
      expect(
        widths.length,
        greaterThan(1),
        reason: 'a 96 dp thumb and a full-width hero are not the same asset',
      );
      // And the small one really is small: the 320-rung is 26x-123x fewer bytes
      // than the master it replaced, measured against the live CDN.
      expect(widths.reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(320));
    });
  });

  group('one picture, one request', () {
    testWidgets('a screenful produces no duplicate image requests', (
      tester,
    ) async {
      await boot(tester);

      final urls = [
        for (final r in requests(tester))
          if (r.imageUrl.contains('assets.vogue.com')) r.imageUrl,
      ];
      expect(
        urls.toSet(),
        hasLength(urls.length),
        reason: 'the same article must not be fetched twice on one screen',
      );
    });

    testWidgets('every request carries a cache key that survives a refresh', (
      tester,
    ) async {
      // Signed first-party URLs rotate their query on every load; a key that
      // moved with them would re-download bytes already on disk.
      await boot(tester);
      for (final r in requests(tester)) {
        expect(r.cacheKey, isNotNull);
        expect(r.cacheKey, isNot(contains('?')));
      }
    });

    testWidgets('leaving and returning re-requests nothing new', (
      tester,
    ) async {
      final (container, repo) = await boot(tester);
      final before = [for (final r in requests(tester)) r.cacheKey];
      final feedCallsBefore = repo.feedCalls;

      final router = container.read(goRouterProvider);
      router.go(AppRoute.wtmHome);
      await settle(tester);
      router.go(AppRoute.wtmNewsroom);
      await settle(tester);

      expect(
        [for (final r in requests(tester)) r.cacheKey],
        before,
        reason: 'the same keys means the image cache is hit, not refetched',
      );
      expect(
        repo.feedCalls,
        feedCallsBefore,
        reason: 'the feed provider is not autoDispose; revisiting is free',
      );
    });

    testWidgets('a rebuild does not change any request', (tester) async {
      // Rebuilds are frequent — a flag settling, a seen-state write, a theme
      // change. Each one that changed a URL would throw the cache away.
      await boot(tester);
      final before = [for (final r in requests(tester)) r.imageUrl];

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect([for (final r in requests(tester)) r.imageUrl], before);
    });
  });
}
