import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/router/routes.dart';
import 'package:app/data/models/giveaway.dart';
import 'package:app/data/models/news_item.dart';
import 'package:app/data/models/offer.dart';
import 'package:app/features/discover/data/discover_story_adapters.dart';
import 'package:app/features/discover/domain/discover_story.dart';

/// The Discover Stories rules, tested where they live: pure functions, no
/// widgets. Story eligibility, ordering, the seen/fresh contract, and the
/// adapters that turn giveaway / offer / news content into cards.

final _now = DateTime(2026, 8, 5, 12);

DiscoverStory _story({
  String id = 's1',
  DiscoverStoryType type = DiscoverStoryType.giveaway,
  String title = 'A title',
  String route = AppRoute.wtmGiveaways,
  int contentVersion = 1,
  DateTime? expiresAt,
}) => DiscoverStory(
  id: id,
  type: type,
  category: 'CAT',
  title: title,
  destination: DiscoverStoryDestination(route: route),
  contentVersion: contentVersion,
  expiresAt: expiresAt,
);

Giveaway _giveaway({
  String id = 'g1',
  String status = 'available',
  bool isMine = false,
  List<String> images = const [],
}) => Giveaway(
  id: id,
  ownerId: 'u2',
  title: 'Vintage bag',
  status: status,
  isMine: isMine,
  images: images,
  createdAt: _now,
);

void main() {
  group('story type ranking', () {
    test('rank fixes the rail order, Today\'s Edit always first', () {
      final shuffled = [
        DiscoverStoryType.newsroom,
        DiscoverStoryType.dailyEdit,
        DiscoverStoryType.offer,
        DiscoverStoryType.closetMatch,
      ]..sort((a, b) => a.rank.compareTo(b.rank));

      expect(shuffled.first, DiscoverStoryType.dailyEdit);
      expect(shuffled, [
        DiscoverStoryType.dailyEdit,
        DiscoverStoryType.closetMatch,
        DiscoverStoryType.offer,
        DiscoverStoryType.newsroom,
      ]);
    });

    test('an unknown wire name resolves to null, never a guess', () {
      // §37.4: a kind from a newer backend is data to skip, not a crash and
      // certainly not a blank card.
      expect(
        DiscoverStoryType.fromWire('giveaway'),
        DiscoverStoryType.giveaway,
      );
      expect(DiscoverStoryType.fromWire('flash_sale_v2'), isNull);
      expect(DiscoverStoryType.fromWire(null), isNull);
    });
  });

  group('destination safety', () {
    test('accepts an in-app path', () {
      expect(
        const DiscoverStoryDestination(route: '/wtm/giveaways').isSafe,
        isTrue,
      );
    });

    test('rejects schemes, hosts and protocol-relative URLs', () {
      // §38: a story may never point the router at anything but an in-app
      // route — the same rule pushes already live under.
      for (final bad in [
        'https://evil.test/x',
        'javascript:alert(1)',
        '//evil.test/x',
        'wtm://deep/link',
        'giveaways',
      ]) {
        expect(
          DiscoverStoryDestination(route: bad).isSafe,
          isFalse,
          reason: '$bad must not be accepted as a destination',
        );
      }
    });
  });

  group('eligibility', () {
    test('a well-formed story is eligible', () {
      expect(_story().isEligibleAt(_now), isTrue);
    });

    test('an expired story is not', () {
      final expired = _story(
        expiresAt: _now.subtract(const Duration(hours: 1)),
      );
      expect(expired.isEligibleAt(_now), isFalse);
    });

    test('expiry is exclusive at the boundary', () {
      expect(_story(expiresAt: _now).isEligibleAt(_now), isFalse);
      expect(
        _story(
          expiresAt: _now.add(const Duration(seconds: 1)),
        ).isEligibleAt(_now),
        isTrue,
      );
    });

    test('a blank title or unsafe destination is not', () {
      expect(_story(title: '   ').isEligibleAt(_now), isFalse);
      expect(_story(route: 'https://evil.test').isEligibleAt(_now), isFalse);
    });
  });

  group('seen and fresh', () {
    test('unseen when absent, seen at or past its version', () {
      final story = _story(contentVersion: 3);
      expect(story.isSeenIn(const {}), isFalse);
      expect(story.isSeenIn(const {'s1': 2}), isFalse);
      expect(story.isSeenIn(const {'s1': 3}), isTrue);
      expect(story.isSeenIn(const {'s1': 4}), isTrue);
    });

    test('a content-version bump makes a seen story fresh again', () {
      // §6.4: freshness is earned by a version move, never by a timestamp.
      const seen = {'s1': 3};
      expect(_story(contentVersion: 3).isSeenIn(seen), isTrue);
      expect(_story(contentVersion: 4).isSeenIn(seen), isFalse);
    });
  });

  group('rail composition', () {
    test('orders by type rank and drops ineligible stories', () {
      final composed = DiscoverRail.compose([
        _story(id: 'news', type: DiscoverStoryType.newsroom),
        _story(id: 'gone', expiresAt: _now.subtract(const Duration(days: 1))),
        _story(id: 'offer', type: DiscoverStoryType.offer),
        _story(id: 'give', type: DiscoverStoryType.giveaway),
      ], now: _now);

      expect(composed.map((s) => s.id), ['give', 'offer', 'news']);
    });

    test('de-duplicates by id, keeping the first', () {
      final composed = DiscoverRail.compose([
        _story(id: 'dup', title: 'first'),
        _story(id: 'dup', title: 'second'),
      ], now: _now);

      expect(composed, hasLength(1));
      expect(composed.single.title, 'first');
    });

    test('caps at six cards', () {
      final composed = DiscoverRail.compose([
        for (var i = 0; i < 12; i++) _story(id: 's$i'),
      ], now: _now);
      expect(composed, hasLength(DiscoverRail.maxCards));
    });

    test('ordering is stable across rebuilds for equal ranks', () {
      // §33.2: an already rendered rail must not reshuffle itself.
      List<String> ids(Iterable<DiscoverStory> input) =>
          DiscoverRail.compose(input, now: _now).map((s) => s.id).toList();

      final a = [_story(id: 'b'), _story(id: 'a'), _story(id: 'c')];
      expect(ids(a), ids(a.reversed));
    });

    test('returns fewer than the minimum rather than padding', () {
      // The UI decides between a rail and the compact fallback; composition
      // never invents a card to reach the threshold.
      final composed = DiscoverRail.compose([_story()], now: _now);
      expect(composed, hasLength(1));
      expect(composed.length < DiscoverRail.minCards, isTrue);
    });
  });

  group('giveaway adapter', () {
    List<DiscoverStory> adaptAll(List<Giveaway> items) =>
        DiscoverStoryAdapters.giveaways(
          items,
          now: _now,
          category: 'GIVEAWAY',
          title: 'Free to a good home',
          subtitle: (count) => '$count pieces available',
          liveBadge: 'LIVE',
        );
    DiscoverStory? adapt(List<Giveaway> items) => adaptAll(items).firstOrNull;

    test('no live listings produces no card, never an empty placeholder', () {
      expect(adapt(const []), isNull);
      expect(adapt([_giveaway(status: 'claimed')]), isNull);
    });

    test('your own listing is not a discovery', () {
      expect(adapt([_giveaway(isMine: true)]), isNull);
    });

    test('counts only live listings and opens the listing itself', () {
      final stories = adaptAll([
        _giveaway(id: 'g1'),
        _giveaway(id: 'g2'),
        _giveaway(id: 'g3', status: 'claimed'),
        _giveaway(id: 'g4', isMine: true),
      ]);

      expect(stories, hasLength(2));
      expect(stories.first.subtitle, '2 pieces available');
      expect(stories.first.type, DiscoverStoryType.giveaway);
      // Its OWN listing, not the hub — three cards pointing at one page would
      // be the same content three times.
      expect(stories.first.destination.route, contains('id=g1'));
      expect(stories.last.destination.route, contains('id=g2'));
      expect(stories.every((s) => s.destination.isSafe), isTrue);
    });

    test('one card per live listing, up to the ceiling', () {
      // The rail collapsed to two cards on a stocked account because every
      // adapter answered with exactly one. Several real listings are several
      // real cards — and never more than the ceiling.
      final stories = adaptAll([
        for (var i = 0; i < 8; i++) _giveaway(id: 'g$i'),
      ]);
      expect(stories, hasLength(DiscoverStoryAdapters.maxGiveawayCards));
      expect(stories.map((s) => s.id).toSet(), hasLength(stories.length));
      // Stable, source order — never id order, which for a uuid is arbitrary.
      expect(
        stories.map((s) => s.ordinal),
        List.generate(stories.length, (i) => i),
      );
    });

    test('uses each listing own cover', () {
      final stories = adaptAll([
        _giveaway(id: 'g1'),
        _giveaway(id: 'g2', images: const ['https://cdn.test/bag.jpg']),
      ]);
      expect(stories[1].imageUrl, 'https://cdn.test/bag.jpg');
    });

    test('content version tracks WHICH listings are live, not the order', () {
      // §33.3: a refetch that returns the same items in a new order is not
      // new content and must not re-light the fresh ring.
      final first = adapt([_giveaway(id: 'g1'), _giveaway(id: 'g2')])!;
      final reordered = adapt([_giveaway(id: 'g2'), _giveaway(id: 'g1')])!;
      final changed = adapt([_giveaway(id: 'g1'), _giveaway(id: 'g9')])!;

      expect(reordered.contentVersion, first.contentVersion);
      expect(changed.contentVersion, isNot(first.contentVersion));
    });
  });

  group('offer adapter', () {
    List<DiscoverStory> adaptAll(List<Offer> items) =>
        DiscoverStoryAdapters.offers(
          items,
          now: _now,
          category: 'OFFER',
          fallbackTitle: "Today's offers",
        );
    DiscoverStory? adapt(List<Offer> items) => adaptAll(items).firstOrNull;

    test('no offers, or an offer with no destination, produces no card', () {
      expect(adapt(const []), isNull);
      expect(
        adapt(const [Offer(id: 'o1', title: 'Deal', affiliateUrl: '  ')]),
        isNull,
      );
    });

    test(
      'uses the real discount label as the badge, never an invented one',
      () {
        final story = adapt(const [
          Offer(
            id: 'o1',
            title: 'Knitwear event',
            brand: 'Studio Label',
            discountLabel: '-40%',
            affiliateUrl: 'https://shop.test',
          ),
        ]);

        expect(story!.badge, '-40%');
        expect(story.title, 'Knitwear event');
        expect(story.subtitle, 'Studio Label');
        expect(story.destination.route, contains('id=o1'));
      },
    );

    test('one card per live offer, up to the ceiling', () {
      final stories = adaptAll([
        for (var i = 0; i < 5; i++)
          Offer(id: 'o$i', title: 'Deal $i', affiliateUrl: 'https://shop.test'),
      ]);
      expect(stories, hasLength(DiscoverStoryAdapters.maxOfferCards));
      expect(stories.map((s) => s.id).toSet(), hasLength(stories.length));
    });

    test('falls back to generic copy only when the offer has no title', () {
      final story = adapt(const [
        Offer(id: 'o1', title: '  ', affiliateUrl: 'https://shop.test'),
      ]);
      expect(story!.title, "Today's offers");
    });
  });

  group('newsroom adapter', () {
    List<DiscoverStory> adaptAll(List<NewsItem> items) =>
        DiscoverStoryAdapters.newsroom(
          items,
          now: _now,
          category: 'STYLE NOTE',
          subtitle: (source) => 'From $source',
          newBadge: 'NEW',
        );
    DiscoverStory? adapt(List<NewsItem> items) => adaptAll(items).firstOrNull;

    NewsItem news({
      String id = 'a1',
      String title = 'One black dress, three looks',
      String? source = 'Atelier Desk',
      DateTime? publishedAt,
    }) => NewsItem(
      id: id,
      title: title,
      source: source,
      publishedAt: publishedAt,
      createdAt: publishedAt ?? _now,
    );

    test('no articles produces no card', () {
      expect(adapt(const []), isNull);
      expect(adapt([news(title: '   ')]), isNull);
    });

    test('leads with the newest article and names the source', () {
      final story = adapt([news()]);
      expect(story!.title, 'One black dress, three looks');
      expect(story.subtitle, 'From Atelier Desk');
      // Its own article. A card per story that all opened the hub would be one
      // piece of content wearing four headlines.
      expect(story.destination.route, contains('id=a1'));
    });

    test('one card per recent article, up to the ceiling', () {
      final stories = adaptAll([
        for (var i = 0; i < 12; i++) news(id: 'a$i', title: 'Story $i'),
      ]);
      expect(stories, hasLength(DiscoverStoryAdapters.maxNewsroomCards));
      expect(stories.map((s) => s.id).toSet(), hasLength(stories.length));
      expect(stories.map((s) => s.title).toSet(), hasLength(stories.length));
    });

    test('the NEW badge is earned by recency, not by position', () {
      // Top of the feed does not make a two-week-old article new (§26.10).
      final fresh = adapt([
        news(publishedAt: _now.subtract(const Duration(hours: 6))),
      ]);
      final stale = adapt([
        news(publishedAt: _now.subtract(const Duration(days: 14))),
      ]);

      expect(fresh!.badge, 'NEW');
      expect(stale!.badge, isNull);
    });

    test('a missing source simply omits the supporting line', () {
      expect(adapt([news(source: null)])!.subtitle, isNull);
    });
  });
}
