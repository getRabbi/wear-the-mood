import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/core/utils/link_launcher.dart';
import 'package:app/data/models/news_item.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/news_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/ui/discover/wtm_article_web_screen.dart';
import 'package:app/ui/discover/wtm_newsroom_screen.dart';

/// Newsroom must never hand a reader to Chrome or Safari.
///
/// Every test boots the REAL app and pushes the REAL registered route, because
/// the thing that broke in production was which screen navigation reaches — not
/// what a repository returns. A launcher that records instead of launching is
/// installed everywhere, so "did we leave the app" is a direct assertion rather
/// than an inference.
class _RecordingLauncher extends LinkLauncher {
  const _RecordingLauncher(this.opened);
  final List<String> opened;

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

class _FakeNews implements NewsRepository {
  _FakeNews({this.feed = const [], this.byId, this.byIdError});

  List<NewsItem> feed;

  /// What [getById] resolves to when there is no error.
  NewsItem? byId;
  Object? byIdError;

  int feedCalls = 0;
  int byIdCalls = 0;

  @override
  Future<List<NewsItem>> getNews({int limit = 20, DateTime? before}) async {
    feedCalls++;
    return feed;
  }

  /// Mirrors the server: the story if it exists, else a 404.
  @override
  Future<NewsItem> getById(String id) async {
    byIdCalls++;
    if (byIdError != null) throw byIdError!;
    if (byId != null) return byId!;
    for (final n in feed) {
      if (n.id == id) return n;
    }
    throw ApiException(
      code: ApiErrorCode.notFound,
      message: 'News item not found.',
      statusCode: 404,
    );
  }

  @override
  Future<List<WardrobeItem>> getClosetMatches(String newsId) async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

NewsItem _item({
  String id = 'n1',
  String title = 'The new tailoring',
  String? url = 'https://vogue.com/the-new-tailoring',
}) => NewsItem(
  id: id,
  title: title,
  summary: 'A short standfirst.',
  source: 'Vogue',
  url: url,
  createdAt: DateTime.utc(2026, 8, 1),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<(ProviderContainer, List<String>)> boot(
    WidgetTester tester, {
    required _FakeNews repo,
    required String at,
  }) async {
    // Tall enough that the article's read action is on screen without a
    // scroll — these tests are about navigation, not layout.
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final opened = <String>[];
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        newsRepositoryProvider.overrideWithValue(repo),
        linkLauncherProvider.overrideWithValue(_RecordingLauncher(opened)),
        // No WebView platform in a unit test. Returning null deliberately puts
        // the reader in its "can't show it here" state, which is enough to
        // prove the ROUTE was entered — the assertion these tests care about.
        webViewControllerBuilderProvider.overrideWithValue(() => null),
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
    container.read(goRouterProvider).push(at);
    await settle(tester);
    return (container, opened);
  }

  final readOn = find.byKey(const Key('wtm-article-read-on'));

  /// The read action sits below the artwork + standfirst, and WtmPage's list
  /// only mounts what is on screen — so bring it into view before asserting.
  /// Returns false when it genuinely is not in the page at all.
  Future<bool> revealReadOn(WidgetTester tester) async {
    if (readOn.evaluate().isNotEmpty) return true;
    try {
      await tester.dragUntilVisible(
        readOn,
        find.byType(ListView).last,
        const Offset(0, -220),
        maxIteration: 12,
      );
      await settle(tester);
      return readOn.evaluate().isNotEmpty;
    } on Object {
      return false;
    }
  }

  group('the article reader stays in the app', () {
    testWidgets('"Read on source" opens the in-app reader, not a browser', (
      tester,
    ) async {
      final repo = _FakeNews(feed: [_item()]);
      final (_, opened) = await boot(
        tester,
        repo: repo,
        at: '${AppRoute.wtmArticle}?id=n1',
      );

      expect(find.byType(WtmArticleScreen), findsOneWidget);
      expect(await revealReadOn(tester), isTrue);

      await tester.tap(readOn);
      await settle(tester);

      expect(
        find.byType(WtmArticleWebScreen),
        findsOneWidget,
        reason: 'the publisher page must render on an in-app route',
      );
      expect(
        opened,
        isEmpty,
        reason: 'no external browser may be launched from Newsroom',
      );
    });

    testWidgets('a story whose link is not https never navigates', (
      tester,
    ) async {
      // A syndicated feed can carry anything. http is a downgrade the audited
      // policy has always refused, and the reader refuses it too.
      final repo = _FakeNews(feed: [_item(url: 'http://vogue.com/insecure')]);
      final (_, opened) = await boot(
        tester,
        repo: repo,
        at: '${AppRoute.wtmArticle}?id=n1',
      );

      expect(await revealReadOn(tester), isTrue);
      await tester.tap(readOn);
      await settle(tester);

      expect(find.byType(WtmArticleWebScreen), findsNothing);
      expect(opened, isEmpty);
      expect(find.text("That link isn't safe to open."), findsOneWidget);
    });

    testWidgets('a story with no link offers no read action at all', (
      tester,
    ) async {
      final repo = _FakeNews(feed: [_item(url: null)], byId: _item(url: null));
      await boot(tester, repo: repo, at: '${AppRoute.wtmArticle}?id=n1');

      expect(find.byType(WtmArticleScreen), findsOneWidget);
      expect(
        await revealReadOn(tester),
        isFalse,
        reason: 'no link means no read action anywhere on the page',
      );
    });

    testWidgets('the reader shows the publisher domain, never an address bar', (
      tester,
    ) async {
      final repo = _FakeNews(feed: [_item()]);
      await boot(tester, repo: repo, at: '${AppRoute.wtmArticle}?id=n1');
      expect(await revealReadOn(tester), isTrue);
      await tester.tap(readOn);
      await settle(tester);

      expect(find.text('VOGUE.COM'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('Newsroom list navigation', () {
    testWidgets('tapping a story opens the internal article route', (
      tester,
    ) async {
      final repo = _FakeNews(feed: [_item()]);
      final (_, opened) = await boot(
        tester,
        repo: repo,
        at: AppRoute.wtmNewsroom,
      );

      expect(find.byType(WtmNewsroomScreen), findsOneWidget);
      await tester.tap(find.text('The new tailoring').first);
      await settle(tester);

      expect(find.byType(WtmArticleScreen), findsOneWidget);
      expect(opened, isEmpty);
    });
  });

  group('cold start / deep link', () {
    testWidgets('an article opens with an EMPTY feed via fetch-by-id', (
      tester,
    ) async {
      // Exactly the push-notification case: nothing has loaded the feed yet.
      final repo = _FakeNews(feed: const [], byId: _item());
      await boot(tester, repo: repo, at: '${AppRoute.wtmArticle}?id=n1');

      expect(find.text('The new tailoring'), findsOneWidget);
      expect(find.text('This story moved on'), findsNothing);
      expect(repo.byIdCalls, 1);
    });

    testWidgets('opening from the loaded list costs no extra request', (
      tester,
    ) async {
      // The ordinary path: the feed is on screen, so the reader must resolve
      // the story from it rather than spending a second round trip.
      final repo = _FakeNews(feed: [_item()], byId: _item());
      final (container, _) = await boot(
        tester,
        repo: repo,
        at: AppRoute.wtmNewsroom,
      );
      container.read(goRouterProvider).push('${AppRoute.wtmArticle}?id=n1');
      await settle(tester);

      expect(find.byType(WtmArticleScreen), findsOneWidget);
      expect(
        repo.byIdCalls,
        0,
        reason: 'the loaded feed already had it — do not re-fetch',
      );
    });

    testWidgets('a deleted story shows the unavailable state, not a retry', (
      tester,
    ) async {
      final repo = _FakeNews(
        feed: const [],
        byIdError: ApiException(
          code: ApiErrorCode.notFound,
          message: 'News item not found.',
          statusCode: 404,
        ),
      );
      await boot(tester, repo: repo, at: '${AppRoute.wtmArticle}?id=gone');

      expect(find.text('This story moved on'), findsOneWidget);
      expect(
        find.text('Try again'),
        findsNothing,
        reason: '404 is permanent — a retry button could never work',
      );
    });

    testWidgets('a transient failure keeps its retry', (tester) async {
      final repo = _FakeNews(
        feed: const [],
        byIdError: ApiException(
          code: ApiErrorCode.providerError,
          message: 'boom',
          statusCode: 503,
        ),
      );
      await boot(tester, repo: repo, at: '${AppRoute.wtmArticle}?id=n1');

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('This story moved on'), findsNothing);
    });
  });
}
