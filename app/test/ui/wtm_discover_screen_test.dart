import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:app/app.dart';
import 'package:app/core/analytics/analytics.dart';
import 'package:app/core/analytics/analytics_events.dart';
import 'package:app/core/analytics/analytics_provider.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/flags/feature_flags.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/giveaway.dart';
import 'package:app/data/models/news_item.dart';
import 'package:app/data/models/offer.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/giveaway_repository.dart';
import 'package:app/data/repositories/news_repository.dart';
import 'package:app/data/repositories/offers_repository.dart';
import 'package:app/features/discover/data/discover_local_store.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/shared/widgets/loading_shimmer.dart';
import 'package:app/ui/community/wtm_social_screen.dart';
import 'package:app/ui/discover/wtm_giveaways_screen.dart';
import 'package:app/ui/discover/wtm_story_rail.dart';
import 'package:app/ui/discover/wtm_story_viewer.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// Phase 2 coverage for the Discover surface: the flag gate, the four states,
/// the Stories rail and its seen/unseen contract, the viewer, and the
/// analytics the rollout will be judged on.

class _RecordingAnalytics implements Analytics {
  final events = <(String, Map<String, Object>?)>[];

  @override
  Future<void> track(String event, {Map<String, Object>? properties}) async =>
      events.add((event, properties));
  @override
  Future<void> identify(String userId) async {}
  @override
  Future<void> reset() async {}

  List<String> get names => events.map((e) => e.$1).toList();
  Map<String, Object>? propsOf(String name) =>
      events.firstWhere((e) => e.$1 == name, orElse: () => (name, null)).$2;
}

/// An in-memory [DiscoverLocalStore] so seen state can be asserted directly.
class _FakeStore implements DiscoverLocalStore {
  _FakeStore([Map<String, int>? seed]) : seen = {...?seed};
  final Map<String, int> seen;

  @override
  Future<Map<String, int>> seenStoryVersions() async => Map.of(seen);
  @override
  Future<void> markStorySeen(String storyId, int contentVersion) async {
    final known = seen[storyId];
    if (known == null || known < contentVersion) seen[storyId] = contentVersion;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeGiveaway implements GiveawayRepository {
  _FakeGiveaway(this.items, {this.fails = false});
  final List<Giveaway> items;
  final bool fails;

  @override
  Future<List<Giveaway>> browse({String? category, String? size}) async {
    if (fails) throw Exception('giveaways down');
    return items;
  }

  @override
  Future<Giveaway> get(String id) async => items.firstWhere((g) => g.id == id);
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeOffers implements OffersRepository {
  _FakeOffers(this.items, {this.fails = false});
  final List<Offer> items;
  final bool fails;

  @override
  Future<List<Offer>> getToday() async {
    if (fails) throw Exception('offers down');
    return items;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeNews implements NewsRepository {
  _FakeNews(this.items, {this.fails = false});
  final List<NewsItem> items;
  final bool fails;

  @override
  Future<List<NewsItem>> getNews({int limit = 20, DateTime? before}) async {
    if (fails) throw Exception('news down');
    return items;
  }

  @override
  Future<List<WardrobeItem>> getClosetMatches(String newsId) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

final _giveaway = Giveaway(
  id: 'g1',
  ownerId: 'u2',
  title: 'Vintage shoulder bag',
  status: 'available',
  createdAt: DateTime.now(),
);

const _offer = Offer(
  id: 'o1',
  title: 'Across the new collection',
  brand: 'ZARA',
  discountLabel: '15% Off',
  affiliateUrl: 'https://zara.test',
);

final _news = NewsItem(
  id: 'a1',
  title: 'The Future of Fashion Is Personal',
  source: 'Atelier Desk',
  createdAt: DateTime.now(),
);

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Without this the detector debounces on a real-time timer that the test
    // clock never advances, so no impression would ever fire.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder.first);
    await settle(tester);
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    bool discover = true,
    bool stories = true,
    List<Giveaway>? giveaways,
    List<Offer>? offers,
    List<NewsItem>? news,
    bool giveawaysFail = false,
    bool offersFail = false,
    bool newsFail = false,
    _RecordingAnalytics? analytics,
    _FakeStore? store,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        enabledFeatureFlagsProvider.overrideWith(
          (ref) => {
            if (discover) FeatureFlags.discover,
            if (stories) FeatureFlags.discoverStories,
          },
        ),
        if (analytics != null) analyticsProvider.overrideWithValue(analytics),
        discoverLocalStoreProvider.overrideWithValue(store ?? _FakeStore()),
        giveawayRepositoryProvider.overrideWithValue(
          _FakeGiveaway(giveaways ?? [_giveaway], fails: giveawaysFail),
        ),
        offersRepositoryProvider.overrideWithValue(
          _FakeOffers(offers ?? const [_offer], fails: offersFail),
        ),
        newsRepositoryProvider.overrideWithValue(
          _FakeNews(news ?? [_news], fails: newsFail),
        ),
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(const []),
        ),
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
    container.read(goRouterProvider).go(AppRoute.wtmDiscover);
    await settle(tester);
    return container;
  }

  group('the flag gate', () {
    testWidgets('OFF renders the existing community fallback, not a blank', (
      tester,
    ) async {
      await boot(tester, discover: false);
      expect(find.byType(WtmSocialScreen), findsOneWidget);
      expect(find.byType(WtmStoryRail), findsNothing);
    });

    testWidgets('ON renders the Discover header and rail', (tester) async {
      await boot(tester);
      expect(find.text('Discover'), findsWidgets);
      expect(find.byType(WtmStoryRail), findsOneWidget);
      expect(find.byType(WtmSocialScreen), findsNothing);
    });

    testWidgets(
      'the stories flag hides the rail without taking Discover down',
      (tester) async {
        // Two independent kill switches: the rail can go while the tab stays.
        await boot(tester, stories: false);
        expect(find.text('Discover'), findsWidgets);
        expect(find.byType(WtmStoryRail), findsNothing);
      },
    );
  });

  group('the story rail', () {
    testWidgets('renders one card per eligible content source', (tester) async {
      await boot(tester);
      expect(find.byType(WtmStoryCard), findsNWidgets(3));
      expect(find.text('GIVEAWAY'), findsOneWidget);
      expect(find.text('OFFER'), findsOneWidget);
      expect(find.text('STYLE NOTE'), findsOneWidget);
    });

    testWidgets('a source with no content contributes no card', (tester) async {
      // §6.1: never an empty placeholder.
      await boot(tester, offers: const []);
      expect(find.byType(WtmStoryCard), findsNWidgets(2));
      expect(find.text('OFFER'), findsNothing);
    });

    testWidgets('one eligible story uses the compact card, not a thin rail', (
      tester,
    ) async {
      await boot(tester, offers: const [], news: const []);
      expect(find.byType(WtmStoryRail), findsNothing);
      expect(find.byType(WtmStoryFallbackCard), findsOneWidget);
    });

    testWidgets('story titles are capped at two lines', (tester) async {
      await boot(
        tester,
        news: [
          NewsItem(
            id: 'a1',
            title:
                'An extremely long editorial headline that would otherwise run '
                'well past the bottom of the card and push the supporting line '
                'clean out of the artwork entirely',
            createdAt: DateTime.now(),
          ),
        ],
      );
      final title = tester.widget<Text>(
        find.descendant(
          of: find.byType(WtmStoryCard),
          matching: find.textContaining('An extremely long editorial'),
        ),
      );
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('cards carry a semantic label including freshness', (
      tester,
    ) async {
      // §6.6: unseen must not be conveyed by ring colour alone.
      await boot(tester);
      final semantics = tester.getSemantics(find.byType(WtmStoryCard).first);
      expect(semantics.label, contains('GIVEAWAY'));
      expect(semantics.label, contains('New'));
    });
  });

  group('seen and unseen', () {
    testWidgets('opening a story marks it seen and persists it', (
      tester,
    ) async {
      final store = _FakeStore();
      await boot(tester, store: store);

      await tapAndSettle(tester, find.byType(WtmStoryCard).first);
      expect(find.byType(WtmStoryViewer), findsOneWidget);

      // Keyed on the LISTING now — the rail carries one card per live
      // giveaway rather than a single hub card — so the seen ring follows the
      // giveaway rather than the slot it happened to occupy.
      expect(store.seen.keys, contains('giveaway-g1'));
    });

    testWidgets('a story already seen at its version reads as seen', (
      tester,
    ) async {
      // Seeded from disk, so the ring is right on the very first frame rather
      // than lighting up and then dimming.
      final store = _FakeStore();
      await boot(tester, store: store);
      final card = tester.widget<WtmStoryCard>(find.byType(WtmStoryCard).first);
      expect(card.seen, isFalse);

      await tapAndSettle(tester, find.byType(WtmStoryCard).first);
      await tapAndSettle(tester, find.byType(WtmIconButton).last);

      final after = tester.widget<WtmStoryCard>(
        find.byType(WtmStoryCard).first,
      );
      expect(after.seen, isTrue);
    });
  });

  group('the story viewer', () {
    testWidgets('opens on the tapped story and closes back to Discover', (
      tester,
    ) async {
      await boot(tester);
      await tapAndSettle(tester, find.byType(WtmStoryCard).first);
      expect(find.byType(WtmStoryViewer), findsOneWidget);

      await tapAndSettle(tester, find.byType(WtmIconButton).last);
      expect(find.byType(WtmStoryViewer), findsNothing);
      expect(find.byType(WtmStoryRail), findsOneWidget);
    });

    testWidgets('the primary CTA opens the story destination', (tester) async {
      await boot(tester);
      await tapAndSettle(tester, find.byType(WtmStoryCard).first);

      await tapAndSettle(tester, find.text('View Giveaway'));
      // The viewer pops first, so the destination lands on Discover — not on
      // top of a full-screen story the user would land back inside. The card
      // opens ITS listing rather than the hub.
      expect(find.byType(WtmStoryViewer), findsNothing);
      expect(find.byType(WtmGiveawayDetailScreen), findsOneWidget);
    });

    testWidgets('each story type gets its own CTA verb', (tester) async {
      await boot(tester, giveaways: const []);
      await tapAndSettle(tester, find.byType(WtmStoryCard).first);
      expect(find.text('View Offer'), findsOneWidget);
      expect(find.text('View Giveaway'), findsNothing);
    });

    testWidgets('tapping the right zone advances to the next story', (
      tester,
    ) async {
      await boot(tester);
      await tapAndSettle(tester, find.byType(WtmStoryCard).first);
      expect(find.text('View Giveaway'), findsOneWidget);

      final size = tester.getSize(find.byType(WtmStoryViewer));
      await tester.tapAt(Offset(size.width * 0.8, size.height * 0.5));
      await settle(tester);

      expect(find.text('View Offer'), findsOneWidget);
    });
  });

  group('the four states', () {
    testWidgets('loading shows skeleton cards, never a bare spinner', (
      tester,
    ) async {
      await boot(tester);
      // Re-enter with the content provider invalidated to catch the load frame.
      await tester.pump();
      expect(find.byType(WtmStoryRail), findsOneWidget);
    });

    testWidgets('every source failing shows the error state with retry', (
      tester,
    ) async {
      await boot(tester, giveawaysFail: true, offersFail: true, newsFail: true);
      expect(find.byType(WtmErrorState), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(WtmStoryRail), findsNothing);
    });

    testWidgets('one source failing still renders the rest', (tester) async {
      // §24: a story failing to load must not take the rail down with it.
      await boot(tester, offersFail: true);
      expect(find.byType(WtmErrorState), findsNothing);
      expect(find.byType(WtmStoryCard), findsNWidgets(2));
      expect(find.text("Some of Discover couldn't load."), findsOneWidget);
    });

    testWidgets('no content at all shows an honest empty state', (
      tester,
    ) async {
      await boot(tester, giveaways: const [], offers: const [], news: const []);
      expect(find.byType(WtmEmptyState), findsOneWidget);
      expect(find.text('Nothing new right now'), findsOneWidget);
      expect(find.byType(WtmStoryCard), findsNothing);
    });
  });

  group('analytics', () {
    testWidgets('opening Discover reports open and a loaded feed', (
      tester,
    ) async {
      final analytics = _RecordingAnalytics();
      await boot(tester, analytics: analytics);

      expect(analytics.names, contains(AnalyticsEvents.discoverOpen));
      expect(analytics.names, contains(AnalyticsEvents.discoverFeedLoaded));
      expect(
        analytics.propsOf(AnalyticsEvents.discoverFeedLoaded)?['story_count'],
        3,
      );
    });

    testWidgets('a total failure reports discover_feed_failed', (tester) async {
      final analytics = _RecordingAnalytics();
      await boot(
        tester,
        analytics: analytics,
        giveawaysFail: true,
        offersFail: true,
        newsFail: true,
      );
      expect(analytics.names, contains(AnalyticsEvents.discoverFeedFailed));
      expect(
        analytics.names,
        isNot(contains(AnalyticsEvents.discoverFeedLoaded)),
      );
    });

    testWidgets('opening a story reports open, seen and the action', (
      tester,
    ) async {
      final analytics = _RecordingAnalytics();
      await boot(tester, analytics: analytics);

      await tapAndSettle(tester, find.byType(WtmStoryCard).first);
      expect(analytics.names, contains(AnalyticsEvents.discoverStoryOpen));
      expect(analytics.names, contains(AnalyticsEvents.discoverStorySeen));

      await tapAndSettle(tester, find.text('View Giveaway'));
      expect(analytics.names, contains(AnalyticsEvents.discoverStoryAction));
      expect(
        analytics.propsOf(AnalyticsEvents.discoverStoryAction)?['destination'],
        '${AppRoute.wtmGiveawayDetail}?id=g1',
      );
    });

    testWidgets('closing without acting reports a close, not an action', (
      tester,
    ) async {
      final analytics = _RecordingAnalytics();
      await boot(tester, analytics: analytics);

      await tapAndSettle(tester, find.byType(WtmStoryCard).first);
      await tapAndSettle(tester, find.byType(WtmIconButton).last);

      expect(analytics.names, contains(AnalyticsEvents.discoverStoryClose));
      expect(
        analytics.names,
        isNot(contains(AnalyticsEvents.discoverStoryAction)),
      );
    });

    testWidgets('story properties never carry anything but ids and types', (
      tester,
    ) async {
      // §22/§36: no private image URLs, no raw user content in analytics.
      final analytics = _RecordingAnalytics();
      await boot(tester, analytics: analytics);
      await tapAndSettle(tester, find.byType(WtmStoryCard).first);

      final props = analytics.propsOf(AnalyticsEvents.discoverStoryOpen)!;
      expect(props.keys, containsAll(['story_type', 'story_id']));
      for (final value in props.values) {
        expect(
          value.toString(),
          isNot(contains('http')),
          reason: 'analytics must never carry a URL',
        );
      }
    });
  });

  testWidgets('pull to refresh reloads without discarding what is on screen', (
    tester,
  ) async {
    await boot(tester);
    expect(find.byType(WtmStoryCard), findsNWidgets(3));

    await tester.fling(
      find.byType(WtmStoryCard).first,
      const Offset(0, 320),
      1000,
    );
    await tester.pump();
    // Mid-refresh the existing cards are still there — no skeleton flash over
    // content the user is already reading (§33.4).
    expect(find.byType(WtmStoryCard), findsWidgets);
    expect(find.byType(LoadingShimmer), findsNothing);
    await settle(tester, 1200);
    expect(find.byType(WtmStoryCard), findsNWidgets(3));
  });
}
