import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
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
import 'package:app/ui/discover/wtm_giveaways_screen.dart';
import 'package:app/ui/discover/wtm_newsroom_screen.dart';
import 'package:app/ui/discover/wtm_offers_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// P9 gate coverage: the discover surfaces on the real news/giveaway/offer/
/// notification backends, and the **Inbox Drops deep-link** that opens a
/// giveaway / offer / article.

class _FakeNotifs implements NotificationsRepository {
  _FakeNotifs(this.items);
  List<AppNotification> items;
  final read = <String>[];

  @override
  Future<List<AppNotification>> getNotifications({int limit = 50}) async =>
      items;
  @override
  Future<void> markRead(String id) async => read.add(id);
  @override
  Future<void> markAllRead() async {}
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeGiveaway implements GiveawayRepository {
  _FakeGiveaway(this.items);
  List<Giveaway> items;
  final claimed = <String>[];

  @override
  Future<List<Giveaway>> browse({String? category, String? size}) async =>
      items;
  @override
  Future<Giveaway> get(String id) async => items.firstWhere((g) => g.id == id);
  @override
  Future<void> claim(String id, {String? message}) async => claimed.add(id);
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeOffers implements OffersRepository {
  _FakeOffers(this.items);
  List<Offer> items;
  @override
  Future<List<Offer>> getToday() async => items;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeNews implements NewsRepository {
  _FakeNews(this.items);
  List<NewsItem> items;
  @override
  Future<List<NewsItem>> getNews({int limit = 20, DateTime? before}) async =>
      items;
  @override
  Future<List<WardrobeItem>> getClosetMatches(String newsId) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

AppNotification _notif(String id, String type, String title,
        {String? targetType, String? targetId}) =>
    AppNotification(
        id: id,
        type: type,
        title: title,
        targetType: targetType,
        targetId: targetId,
        createdAt: DateTime.now());

final _giveaway = Giveaway(
    id: 'g1',
    ownerId: 'u2',
    ownerName: 'Maya',
    title: 'Vintage shoulder bag',
    status: 'available',
    createdAt: DateTime.now());

const _offer = Offer(
    id: 'o1',
    title: 'Across the new collection',
    brand: 'ZARA',
    discountLabel: '15% Off',
    affiliateUrl: 'https://zara.test');

final _news = NewsItem(
    id: 'a1',
    title: 'The Future of Fashion Is Personal',
    summary: 'AI and individuality co-create a new era of style.',
    source: 'Atelier Desk',
    url: 'https://news.test',
    createdAt: DateTime.now());

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

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    List<AppNotification> notifs = const [],
    List<Giveaway>? giveaways,
    List<Offer> offers = const [_offer],
    List<NewsItem>? news,
    _FakeGiveaway? giveawayRepo,
    String at = AppRoute.wtmInbox,
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
        notificationsRepositoryProvider
            .overrideWithValue(_FakeNotifs(notifs)),
        giveawayRepositoryProvider.overrideWithValue(
            giveawayRepo ?? _FakeGiveaway(giveaways ?? [_giveaway])),
        offersRepositoryProvider.overrideWithValue(_FakeOffers(offers)),
        newsRepositoryProvider.overrideWithValue(_FakeNews(news ?? [_news])),
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

  testWidgets('GATE: an Inbox Drops item deep-links to the giveaway detail', (
    tester,
  ) async {
    await boot(tester, notifs: [
      _notif('n1', 'giveaway', 'Vintage bag giveaway is live',
          targetType: 'giveaway', targetId: 'g1'),
    ]);
    // Drops tab holds the giveaway notification.
    await tapAndSettle(tester, find.text('Drops'));
    await tapAndSettle(tester, find.text('Vintage bag giveaway is live'));
    expect(find.byType(WtmGiveawayDetailScreen), findsOneWidget);
    expect(find.text('Vintage shoulder bag'), findsWidgets);
  });

  testWidgets('Inbox tabs split Activity / Drops / System', (tester) async {
    await boot(tester, notifs: [
      _notif('n1', 'like', 'Lara liked your look', targetType: 'post'),
      _notif('n2', 'giveaway', 'A drop is live', targetType: 'giveaway',
          targetId: 'g1'),
      _notif('n3', 'credit', '25 credits added', targetType: 'credit'),
    ]);
    // Activity is the default tab.
    expect(find.text('Lara liked your look'), findsOneWidget);
    expect(find.text('A drop is live'), findsNothing);

    await tapAndSettle(tester, find.text('Drops'));
    expect(find.text('A drop is live'), findsOneWidget);

    await tapAndSettle(tester, find.text('System'));
    expect(find.text('25 credits added'), findsOneWidget);
  });

  testWidgets('Giveaways create action opens the WTM create screen (Fix B)',
      (tester) async {
    // The header "give an item away" action opens the rebuilt WTM create screen
    // via a /wtm route (reachable in WTM_SHELL, no auth bounce).
    await boot(tester, at: AppRoute.wtmGiveaways);
    final createBtn = find.byWidgetPredicate(
        (w) => w is WtmIconButton && w.glyph == WtmGlyph.plus);
    expect(createBtn, findsOneWidget);

    await tapAndSettle(tester, createBtn);
    expect(find.byType(CreateGiveawayScreen), findsOneWidget);
    // Rebuilt in WTM: the primary action is the gradient Publish CTA.
    expect(
      find.byWidgetPredicate(
          (w) => w is GradientCta && w.label == 'Publish listing'),
      findsOneWidget,
    );
  });

  testWidgets('Empty giveaways invites creating one, not a dead end (Fix 6)',
      (tester) async {
    await boot(tester, giveaways: const [], at: AppRoute.wtmGiveaways);
    expect(find.text('Give it away'), findsWidgets);
  });

  testWidgets('Giveaways browse → detail → Enter claims', (tester) async {
    final repo = _FakeGiveaway([_giveaway]);
    await boot(tester, giveawayRepo: repo, at: AppRoute.wtmGiveaways);
    expect(find.byType(WtmGiveawaysScreen), findsOneWidget);

    await tapAndSettle(tester, find.text('Vintage shoulder bag'));
    expect(find.byType(WtmGiveawayDetailScreen), findsOneWidget);

    await tapAndSettle(tester, find.text('Enter Now'));
    expect(repo.claimed, contains('g1'));
  });

  testWidgets('Offers list renders and the detail resolves by id', (
    tester,
  ) async {
    final container = await boot(tester, at: AppRoute.wtmOffers);
    expect(find.byType(WtmOffersScreen), findsOneWidget);
    expect(find.text('ZARA'), findsWidgets);

    container.read(goRouterProvider).push('${AppRoute.wtmOfferDetail}?id=o1');
    await settle(tester);
    expect(find.byType(WtmOfferDetailScreen), findsOneWidget);
    expect(find.text('Shop Now'), findsOneWidget);
  });

  testWidgets('Newsroom → article reader opens the story', (tester) async {
    final container = await boot(tester, at: AppRoute.wtmNewsroom);
    expect(find.byType(WtmNewsroomScreen), findsOneWidget);

    container.read(goRouterProvider).push('${AppRoute.wtmArticle}?id=a1');
    await settle(tester);
    expect(find.byType(WtmArticleScreen), findsOneWidget);
    expect(find.textContaining('Future of Fashion'), findsWidgets);
  });

  testWidgets(
      'Newsroom "More Stories" are picture cards that open the IN-APP reader '
      '(mobile QA)', (tester) async {
    final stories = [
      _news,
      NewsItem(
        id: 'a2',
        title: 'Quiet Luxury Returns to the Runway',
        summary: 'Tailoring leads the season.',
        source: 'Vogue',
        url: 'https://news.test/a2',
        imageUrl: 'https://cdn.test/a2.jpg',
        createdAt: DateTime.now(),
      ),
      NewsItem(
        id: 'a3',
        title: 'Archive Denim Is Back',
        source: 'GQ',
        imageUrl: 'https://cdn.test/a3.jpg',
        createdAt: DateTime.now(),
      ),
    ];
    await boot(tester, news: stories, at: AppRoute.wtmNewsroom);

    // Every story renders as an image card — no icon-only WtmRow rows.
    expect(find.text('Quiet Luxury Returns to the Runway'), findsOneWidget);
    expect(find.text('Vogue'), findsOneWidget);
    expect(find.text('Tailoring leads the season.'), findsOneWidget);
    expect(find.byType(WtmRow), findsNothing);

    // Tapping the card opens the in-app article reader, not the browser.
    await tapAndSettle(
        tester, find.text('Quiet Luxury Returns to the Runway'));
    expect(find.byType(WtmArticleScreen), findsOneWidget);
    // The external source link stays a secondary option at the bottom.
    expect(find.textContaining('Read on'), findsOneWidget);
  });
}
