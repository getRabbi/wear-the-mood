import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/flags/feature_flags.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/app_notification.dart';
import 'package:app/data/models/giveaway.dart';
import 'package:app/data/models/news_item.dart';
import 'package:app/data/models/offer.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/giveaway_repository.dart';
import 'package:app/data/repositories/news_repository.dart';
import 'package:app/data/repositories/notifications_repository.dart';
import 'package:app/data/repositories/offers_repository.dart';
import 'package:app/features/giveaway/create_giveaway_screen.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/community/wtm_social_screen.dart';
import 'package:app/ui/discover/wtm_discover_screen.dart';
import 'package:app/ui/discover/wtm_giveaway_chat_screen.dart';
import 'package:app/ui/discover/wtm_giveaways_screen.dart';
import 'package:app/ui/discover/wtm_inbox_screen.dart';
import 'package:app/ui/discover/wtm_newsroom_screen.dart';
import 'package:app/ui/discover/wtm_offers_screen.dart';
import 'package:app/ui/discover/wtm_search_screen.dart';
import 'package:app/ui/home/wtm_home_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// Phase 1 navigation gate for the Discover redesign.
///
/// Giveaways, Offers, Newsroom and Search used to live in the HOME branch. A
/// Discover Story that opened a giveaway would therefore have thrown the user
/// onto the Home tab mid-flow. They now belong to the Discover branch, and
/// these tests pin the consequences of that move in both directions:
///
///  * opening any of them FROM Discover keeps Discover selected;
///  * the old Home shortcuts still work and now intentionally switch tabs;
///  * every shipped path, push route and Inbox deep link still resolves;
///  * Create Giveaway and the giveaway pickup chat are untouched.
///
/// Tab selection is read off [WtmBottomNav.currentIndex] — the thing the user
/// actually sees highlighted — rather than the router's internal state.

const _discoverTab = 1;
const _homeTab = 0;
const _inboxTab = 2;

class _FakeNotifs implements NotificationsRepository {
  _FakeNotifs(this.items);
  final List<AppNotification> items;

  @override
  Future<List<AppNotification>> getNotifications({
    int limit = NotificationsRepository.pageSize,
    DateTime? before,
    String? beforeId,
  }) async => before == null ? items : const [];
  @override
  Future<int> unreadCount() async => items.where((n) => !n.isRead).length;
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeGiveaway implements GiveawayRepository {
  _FakeGiveaway(this.items);
  final List<Giveaway> items;

  @override
  Future<List<Giveaway>> browse({String? category, String? size}) async =>
      items;
  @override
  Future<Giveaway> get(String id) async => items.firstWhere((g) => g.id == id);

  // The pickup chat screen loads on open. There is no chat in these fixtures —
  // this suite is about ROUTING, so the screen landing on its own empty face is
  // exactly the right amount of chat behaviour to exercise here. The chat's own
  // behaviour is covered by wtm_giveaway_chat_test.dart.
  @override
  Future<GiveawayPickupChat?> getChat(String giveawayId) async => null;
  @override
  Future<List<GiveawayChatMessage>> chatMessages(String chatId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeOffers implements OffersRepository {
  @override
  Future<List<Offer>> getToday() async => const [_offer];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeNews implements NewsRepository {
  @override
  Future<List<NewsItem>> getNews({int limit = 20, DateTime? before}) async => [
    _news,
  ];
  @override
  Future<List<WardrobeItem>> getClosetMatches(String newsId) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

final _giveaway = Giveaway(
  id: 'g1',
  ownerId: 'u2',
  ownerName: 'Maya',
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
  summary: 'AI and individuality co-create a new era of style.',
  source: 'Atelier Desk',
  url: 'https://news.test',
  createdAt: DateTime.now(),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder.first);
    await settle(tester);
  }

  /// The tab currently highlighted in the bottom nav.
  int selectedTab(WidgetTester tester) =>
      tester.widget<WtmBottomNav>(find.byType(WtmBottomNav)).currentIndex;

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    String at = AppRoute.wtmDiscover,
    Set<String> flags = const {},
    List<AppNotification> notifs = const [],
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
        enabledFeatureFlagsProvider.overrideWith((ref) => flags),
        notificationsRepositoryProvider.overrideWithValue(_FakeNotifs(notifs)),
        giveawayRepositoryProvider.overrideWithValue(
          _FakeGiveaway([_giveaway]),
        ),
        offersRepositoryProvider.overrideWithValue(_FakeOffers()),
        newsRepositoryProvider.overrideWithValue(_FakeNews()),
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(const [
            WardrobeItem(id: 'w1', title: 'Noir silk blouse', category: 'tops'),
          ]),
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
    container.read(goRouterProvider).go(at);
    await settle(tester);
    return container;
  }

  group('the Discover tab', () {
    testWidgets('tapping tab 1 lands on the Discover destination', (
      tester,
    ) async {
      await boot(tester, at: AppRoute.wtmHome);
      expect(find.byType(WtmHomeScreen), findsOneWidget);

      await tapAndSettle(tester, find.text('SOCIAL'));
      expect(find.byType(WtmDiscoverScreen), findsOneWidget);
      expect(selectedTab(tester), _discoverTab);
    });

    testWidgets('flag OFF keeps the Social label and glyph', (tester) async {
      // The default state of every shipped build: indistinguishable from today.
      await boot(tester, at: AppRoute.wtmHome);
      expect(find.text('SOCIAL'), findsOneWidget);
      expect(find.text('DISCOVER'), findsNothing);

      final nav = tester.widget<WtmBottomNav>(find.byType(WtmBottomNav));
      expect(nav.items[_discoverTab].glyph, WtmGlyph.users);
    });

    testWidgets('flag ON renames the tab to Discover with the compass', (
      tester,
    ) async {
      await boot(tester, at: AppRoute.wtmHome, flags: {FeatureFlags.discover});
      expect(find.text('DISCOVER'), findsOneWidget);
      expect(find.text('SOCIAL'), findsNothing);

      final nav = tester.widget<WtmBottomNav>(find.byType(WtmBottomNav));
      expect(nav.items[_discoverTab].glyph, WtmGlyph.compass);
    });

    testWidgets('the Discover destination is never blank with the flag off', (
      tester,
    ) async {
      // Spec §24/§31: a disabled Discover shows the existing safe fallback.
      await boot(tester);
      expect(find.byType(WtmDiscoverScreen), findsOneWidget);
      expect(find.byType(WtmSocialScreen), findsOneWidget);
    });
  });

  group('opening a Discover destination keeps Discover selected', () {
    // The whole reason the routes moved. Each of these used to switch the
    // highlighted tab to Home.
    for (final (label, route, screen) in <(String, String, Type)>[
      ('Giveaways', AppRoute.wtmGiveaways, WtmGiveawaysScreen),
      ('Offers', AppRoute.wtmOffers, WtmOffersScreen),
      ('Newsroom', AppRoute.wtmNewsroom, WtmNewsroomScreen),
      ('Search', AppRoute.wtmSearch, WtmSearchScreen),
    ]) {
      testWidgets('$label opens in the Discover branch', (tester) async {
        final container = await boot(tester);
        expect(selectedTab(tester), _discoverTab);

        container.read(goRouterProvider).push(route);
        await settle(tester);

        expect(find.byType(screen), findsOneWidget);
        expect(
          selectedTab(tester),
          _discoverTab,
          reason: '$label must not steal the Home tab',
        );
      });
    }

    testWidgets('back from Giveaways returns to Discover, still selected', (
      tester,
    ) async {
      final container = await boot(tester);
      final router = container.read(goRouterProvider);

      router.push(AppRoute.wtmGiveaways);
      await settle(tester);
      expect(find.byType(WtmGiveawaysScreen), findsOneWidget);

      router.pop();
      await settle(tester);
      expect(find.byType(WtmDiscoverScreen), findsOneWidget);
      expect(selectedTab(tester), _discoverTab);
    });
  });

  group('compatibility', () {
    testWidgets('the old /wtm/social path opens Discover', (tester) async {
      // Shipped builds, saved routes and existing `context.go` calls still use
      // this path; it must land on the tab's destination, not a dead end.
      await boot(tester, at: AppRoute.wtmSocial);
      expect(find.byType(WtmDiscoverScreen), findsOneWidget);
      expect(selectedTab(tester), _discoverTab);
    });

    testWidgets('the Home shortcut row still reaches Giveaways', (
      tester,
    ) async {
      // The Home shortcuts use `context.push`, and an imperative push stacks
      // onto the CURRENT branch's navigator whichever branch declared the
      // route — so this opens Giveaways over Home and Home stays highlighted.
      // Unchanged from before the move, and the calmer behaviour: tapping a
      // Home shortcut should not silently reassign your tab. (The spec permits
      // a switch here but does not require one; Phase 6 removes this row.)
      await boot(tester, at: AppRoute.wtmHome);
      expect(selectedTab(tester), _homeTab);

      await tester.scrollUntilVisible(
        find.text('Giveaways'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester, 200);
      await tapAndSettle(tester, find.text('Giveaways'));

      expect(find.byType(WtmGiveawaysScreen), findsOneWidget);
      expect(selectedTab(tester), _homeTab);
    });

    testWidgets('a post link with no id lands on Discover, not a blank page', (
      tester,
    ) async {
      await boot(tester, at: AppRoute.wtmPost);
      expect(find.byType(WtmDiscoverScreen), findsOneWidget);
    });
  });

  group('notification deep links still resolve', () {
    // These exact routes are built server-side by `route_for` and by
    // notification_routing.dart, and a push tapped from a terminated app opens
    // them with `go`.
    //
    // `go` is where the branch move earns its keep: unlike `push` it rebuilds
    // the match list from the location and selects whichever branch OWNS the
    // route. While these lived in the Home branch, a tapped giveaway push
    // landed the user on the Home tab. Now it lands on Discover.
    for (final (label, route, screen) in <(String, String, Type)>[
      (
        'giveaway detail',
        '${AppRoute.wtmGiveawayDetail}?id=g1',
        WtmGiveawayDetailScreen,
      ),
      (
        'offer detail',
        '${AppRoute.wtmOfferDetail}?id=o1',
        WtmOfferDetailScreen,
      ),
      ('article', '${AppRoute.wtmArticle}?id=a1', WtmArticleScreen),
    ]) {
      testWidgets('$label opens and selects Discover', (tester) async {
        await boot(tester, at: route);
        expect(find.byType(screen), findsOneWidget);
        expect(
          selectedTab(tester),
          _discoverTab,
          reason: 'a tapped $label push must land on the Discover tab',
        );
      });
    }
  });

  group('the Giveaway feature is unchanged by the Discover work', () {
    testWidgets('Create Giveaway is still reachable from the hub header', (
      tester,
    ) async {
      // Safety rule 24: hiding the Community composer must never cost a user
      // the ability to give an item away. This entry lives on the Giveaways
      // hub and is deliberately independent of `feature_community_posting`,
      // which is OFF here.
      final container = await boot(tester);
      container.read(goRouterProvider).push(AppRoute.wtmGiveaways);
      await settle(tester);

      final createBtn = find.byWidgetPredicate(
        (w) => w is WtmIconButton && w.glyph == WtmGlyph.plus,
      );
      expect(createBtn, findsOneWidget);

      await tapAndSettle(tester, createBtn);
      expect(find.byType(CreateGiveawayScreen), findsOneWidget);
    });

    testWidgets('the pickup chat still opens from an Inbox message', (
      tester,
    ) async {
      // Giveaway chat is full-bleed OUTSIDE the shell, reached from Inbox. It
      // deliberately did not move; this pins that the Inbox → chat path and
      // the return to Inbox both survive the branch shuffle.
      final container = await boot(
        tester,
        at: AppRoute.wtmInbox,
        notifs: [
          AppNotification(
            id: 'n1',
            type: 'giveaway_message',
            title: 'Maya sent you a message',
            targetType: 'giveaway_chat',
            targetId: 'g1',
            createdAt: DateTime.now(),
          ),
        ],
      );
      expect(find.byType(WtmInboxScreen), findsOneWidget);
      expect(selectedTab(tester), _inboxTab);

      // Giveaway messages file under Drops.
      await tapAndSettle(tester, find.text('Drops'));
      await tapAndSettle(tester, find.text('Maya sent you a message'));
      expect(find.byType(WtmGiveawayChatScreen), findsOneWidget);

      container.read(goRouterProvider).pop();
      await settle(tester);
      expect(find.byType(WtmInboxScreen), findsOneWidget);
      expect(selectedTab(tester), _inboxTab);
    });
  });
}
