import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/router/routes.dart';
import 'package:app/data/models/money.dart';
import 'package:app/data/models/product.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/features/discover/domain/discover_page.dart';
import 'package:app/features/discover/domain/discover_story.dart';

/// The approved Discover composition, as rules rather than pixels.
///
/// Every defect that got the previous build rejected was a COMPOSITION defect —
/// Complete Your Look three times, "Keep exploring" four times, product after
/// product with nothing between them. Those are decided in one pure function,
/// so this is where they are pinned down: no widget, no pump, no flake.

Product _product(
  String id, {
  String? category = 'dresses',
  bool sold = false,
}) => Product(
  id: id,
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: 'Piece $id',
  category: category,
  price: const Money(amountMinor: 349900, currency: 'BDT'),
  stockStatus: sold ? StockStatus.outOfStock : StockStatus.inStock,
);

List<Product> _products(int count) => [
  for (var i = 0; i < count; i++)
    // Rotating categories, so Complete Your Look has different things to pair.
    _product('p$i', category: ['tops', 'bottoms', 'shoes', 'bags'][i % 4]),
];

WardrobeItem _owned(String id, {String? title = 'Noir blouse'}) =>
    WardrobeItem(id: id, title: title, category: 'dresses');

/// A story as the adapters actually build one — WITH artwork.
///
/// The image is not decoration in these fixtures: the Newsroom slot is a
/// full-bleed editorial card and now requires a story that has a picture, so a
/// fixture without one is not a realistic newsroom story. Pass
/// `imageUrl: null` to test the picture-less case deliberately.
DiscoverStory _story(DiscoverStoryType type, {String? id, String? imageUrl = 'https://cdn/story.jpg'}) =>
    DiscoverStory(
      id: id ?? type.name,
      type: type,
      category: type.name.toUpperCase(),
      title: 'Story ${type.name}',
      imageUrl: imageUrl,
      destination: const DiscoverStoryDestination(route: AppRoute.wtmGiveaways),
    );

/// The six-card rail the approved layout asks for.
List<DiscoverStory> _fullRail() => [
  for (final type in DiscoverStoryType.values) _story(type),
];

List<T> _sectionsOf<T>(DiscoverPageLayout layout) =>
    layout.sections.whereType<T>().toList();

void main() {
  group('section order', () {
    test('is the approved sequence, top to bottom', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
      );

      expect(layout.sections.map((s) => s.runtimeType.toString()).toList(), [
        'StoryRailSection',
        'MoodPulseSection',
        'ProductRowSection', // Picked for You
        'CompleteLookSection',
        'CampaignSection',
        'NewsroomSection',
        'ProductRowSection', // New for your mood
      ]);
    });

    test('the Story rail is the first content section', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
      );
      expect(layout.sections.first, isA<StoryRailSection>());
    });

    test('the one interaction card sits above the first product row', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
      );
      final pulse = layout.sections.indexWhere((s) => s is MoodPulseSection);
      final row = layout.sections.indexWhere((s) => s is ProductRowSection);
      expect(pulse, lessThan(row));
      expect(_sectionsOf<MoodPulseSection>(layout), hasLength(1));
    });

    test('a rail under two cards is not a rail', () {
      // One eligible story: the screen shows the compact fallback card, so the
      // composer must not claim a rail section.
      final layout = DiscoverPage.compose(
        stories: [_story(DiscoverStoryType.newsroom)],
        products: _products(8),
      );
      expect(_sectionsOf<StoryRailSection>(layout), isEmpty);
    });
  });

  group('repetition rules', () {
    test('Complete Your Look appears exactly once, however big the closet', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(24),
        closet: [
          for (var i = 0; i < 6; i++) _owned('w$i', title: 'Garment $i'),
        ],
      );
      expect(_sectionsOf<CompleteLookSection>(layout), hasLength(1));
    });

    test('one campaign card only, and a giveaway outranks an offer', () {
      final layout = DiscoverPage.compose(
        stories: [
          _story(DiscoverStoryType.giveaway),
          _story(DiscoverStoryType.offer),
          _story(DiscoverStoryType.newsroom),
        ],
        products: _products(8),
      );
      final campaigns = _sectionsOf<CampaignSection>(layout);
      expect(campaigns, hasLength(1));
      expect(campaigns.single.story!.type, DiscoverStoryType.giveaway);
    });

    test('an offer takes the campaign slot when no giveaway is live', () {
      final layout = DiscoverPage.compose(
        stories: [
          _story(DiscoverStoryType.offer),
          _story(DiscoverStoryType.newsroom),
        ],
        products: _products(8),
      );
      expect(
        _sectionsOf<CampaignSection>(layout).single.story!.type,
        DiscoverStoryType.offer,
      );
    });

    test('the Newsroom card appears exactly once', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(24),
        closet: [_owned('w1')],
      );
      expect(_sectionsOf<NewsroomSection>(layout), hasLength(1));
    });

    test('no row heading is ever used twice', () {
      // 24 products is six full rows — every slot the page has. If any heading
      // repeated, this is where "Keep exploring" ×4 would come back.
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(40),
        closet: [_owned('w1')],
      );
      final slots = _sectionsOf<ProductRowSection>(
        layout,
      ).map((r) => r.slot).toList();
      expect(slots.toSet(), hasLength(slots.length));
    });

    test('the page ends after two rows, however big the catalog', () {
      // 200 products used to become row after row down an endless tail. The
      // approved layout has exactly two strips; the rest lives behind View all.
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(200),
        closet: [_owned('w1')],
      );
      expect(_sectionsOf<ProductRowSection>(layout), hasLength(2));
      expect(layout.rowsRendered, 2);
      // And the LAST thing on the page is that second row.
      expect(layout.sections.last, isA<ProductRowSection>());
      expect(
        (layout.sections.last as ProductRowSection).slot,
        DiscoverRowSlot.newForYourMood,
      );
    });

    test('nothing follows the Newsroom card except one row', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(60),
        closet: [_owned('w1')],
      );
      final news = layout.sections.indexWhere((s) => s is NewsroomSection);
      expect(news, greaterThan(-1));
      final after = layout.sections.sublist(news + 1);
      expect(after, hasLength(1));
      expect(after.single, isA<ProductRowSection>());
    });
  });

  group('deduplication', () {
    test('a product id is never placed twice on one page', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(24),
        closet: [_owned('w1')],
      );

      final placed = <String>[
        for (final row in _sectionsOf<ProductRowSection>(layout))
          ...row.products.map((p) => p.id),
        for (final look in _sectionsOf<CompleteLookSection>(layout))
          ...look.look.suggestions.map((p) => p.id),
      ];
      expect(placed.toSet(), hasLength(placed.length));
      expect(layout.usedProductIds, placed.toSet());
    });

    test(
      'Complete Your Look pairs products the lead row did not already use',
      () {
        final layout = DiscoverPage.compose(
          stories: _fullRail(),
          products: _products(12),
          closet: [_owned('w1')],
        );
        final lead = _sectionsOf<ProductRowSection>(layout).first;
        final look = _sectionsOf<CompleteLookSection>(layout).single;
        expect(
          look.look.suggestions
              .map((p) => p.id)
              .toSet()
              .intersection(lead.products.map((p) => p.id).toSet()),
          isEmpty,
        );
      },
    );

    test('a collapsed rail hands its story to the card, not to both', () {
      // Caught on device: with only a Newsroom item live, the compact fallback
      // card AND the feed's editorial card showed the same Style Note. The
      // editorial card is the fuller telling, so it keeps the story and the
      // compact card stands down.
      final layout = DiscoverPage.compose(
        stories: [_story(DiscoverStoryType.newsroom)],
        products: _products(8),
      );
      expect(_sectionsOf<NewsroomSection>(layout).single.story, isNotNull);
      expect(layout.fallbackStory, isNull);
    });

    test('a lone personalized story still gets the compact card', () {
      // Nothing below would show a Closet Match, so dropping the compact card
      // here would lose the story altogether.
      final layout = DiscoverPage.compose(
        stories: [_story(DiscoverStoryType.closetMatch)],
        products: _products(8),
      );
      expect(layout.fallbackStory?.type, DiscoverStoryType.closetMatch);
    });

    test('with shopping off, a lone campaign story keeps the compact card', () {
      // No editorial slot renders at all, so the compact card is the only place
      // left for it.
      final layout = DiscoverPage.compose(
        stories: [_story(DiscoverStoryType.giveaway)],
        products: _products(8),
        shoppingEnabled: false,
      );
      expect(layout.fallbackStory?.type, DiscoverStoryType.giveaway);
    });
  });

  group('density', () {
    test('a row never holds more than four products', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(40),
        closet: [_owned('w1')],
      );
      for (final row in _sectionsOf<ProductRowSection>(layout)) {
        expect(
          row.products,
          hasLength(lessThanOrEqualTo(DiscoverPage.productsPerRow)),
        );
      }
    });

    test('two rows never sit back to back while a module could separate', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
      );
      for (var i = 1; i < layout.sections.length; i++) {
        if (layout.sections[i] is! ProductRowSection) continue;
        expect(
          layout.sections[i - 1],
          isNot(isA<ProductRowSection>()),
          reason: 'two product rows in a row is the catalog wall returning',
        );
      }
    });

    test('the fixed editorial slots separate the rows even when empty', () {
      // No closet, no campaign, no article — yet the two editorial cards still
      // hold their slots, so the closing row is never stacked straight onto the
      // lead row. That is the second thing those fixed slots buy: a stable
      // rhythm rather than two strips running together on a quiet day.
      final layout = DiscoverPage.compose(
        stories: [
          _story(DiscoverStoryType.dailyEdit),
          _story(DiscoverStoryType.closetMatch),
        ],
        products: _products(8),
      );
      expect(_sectionsOf<ProductRowSection>(layout), hasLength(2));
      for (var i = 1; i < layout.sections.length; i++) {
        if (layout.sections[i] is! ProductRowSection) continue;
        expect(layout.sections[i - 1], isNot(isA<ProductRowSection>()));
      }
    });
  });

  group('empty modules are omitted, never rendered blank', () {
    test('an empty closet contributes no Complete Your Look', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
      );
      expect(_sectionsOf<CompleteLookSection>(layout), isEmpty);
    });

    test('no campaign story still keeps the card, holding its slot', () {
      // The two editorial slots are fixed furniture: they hold their place so
      // the page does not reshuffle when a campaign starts or ends, and so
      // Giveaways keeps an entry point on this surface. Empty means an
      // invitation, never an invented campaign — the null story is what makes
      // that distinction impossible to lose.
      final layout = DiscoverPage.compose(
        stories: [
          _story(DiscoverStoryType.newForYou),
          _story(DiscoverStoryType.newsroom),
        ],
        products: _products(8),
      );
      expect(_sectionsOf<CampaignSection>(layout).single.story, isNull);
      expect(_sectionsOf<NewsroomSection>(layout).single.story, isNotNull);
    });

    test('both editorial cards render with nothing live at all', () {
      final layout = DiscoverPage.compose(
        stories: [
          _story(DiscoverStoryType.dailyEdit),
          _story(DiscoverStoryType.closetMatch),
        ],
        products: _products(8),
      );
      expect(_sectionsOf<CampaignSection>(layout).single.story, isNull);
      expect(_sectionsOf<NewsroomSection>(layout).single.story, isNull);
    });

    test('an empty catalog contributes no rows at all', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: const [],
        closet: [_owned('w1')],
      );
      expect(_sectionsOf<ProductRowSection>(layout), isEmpty);
      expect(_sectionsOf<CompleteLookSection>(layout), isEmpty);
    });
  });

  group('the two kill switches', () {
    test('stories off drops the rail and keeps the rest', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
        storiesEnabled: false,
      );
      expect(_sectionsOf<StoryRailSection>(layout), isEmpty);
      expect(_sectionsOf<ProductRowSection>(layout), isNotEmpty);
      expect(_sectionsOf<MoodPulseSection>(layout), hasLength(1));
    });

    test('shopping off leaves the rail and the interaction standing', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
        shoppingEnabled: false,
      );
      expect(_sectionsOf<StoryRailSection>(layout), hasLength(1));
      expect(_sectionsOf<MoodPulseSection>(layout), hasLength(1));
      expect(_sectionsOf<ProductRowSection>(layout), isEmpty);
      // The whole commerce half goes with the flag, editorial cards included —
      // that is what the flag meant before this composer existed.
      expect(_sectionsOf<CampaignSection>(layout), isEmpty);
      expect(_sectionsOf<NewsroomSection>(layout), isEmpty);
    });
  });

  group('inventory: no avoidable holes, no invented content', () {
    // The five-product production catalog. It used to compose as a row of four
    // and then a closing row holding ONE card — "products disappear further
    // down Discover" — because the lead row filled greedily and whatever came
    // after made do with the remainder.
    test('a five-product catalog no longer strands a single card', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(5),
        closet: const [],
      );
      final rows = _sectionsOf<ProductRowSection>(layout);
      expect(rows, hasLength(2));
      expect(rows.first.products, hasLength(3));
      expect(rows.last.products, hasLength(2));
      for (final row in rows) {
        expect(
          row.products.length,
          greaterThanOrEqualTo(DiscoverPage.minProductsPerRow),
          reason: 'a row below the minimum is the stranded-card defect',
        );
      }
    });

    test(
      'every product placed exactly once — no duplication to fill a row',
      () {
        final layout = DiscoverPage.compose(
          stories: _fullRail(),
          products: _products(5),
          closet: const [],
        );
        final placed = [
          for (final row in _sectionsOf<ProductRowSection>(layout))
            ...row.products.map((p) => p.id),
        ];
        expect(placed.toSet(), hasLength(placed.length));
        expect(placed.length, lessThanOrEqualTo(5));
      },
    );

    test('a full catalog is unchanged: both rows at the ceiling', () {
      final rows = _sectionsOf<ProductRowSection>(
        DiscoverPage.compose(
          stories: _fullRail(),
          products: _products(20),
          closet: const [],
        ),
      );
      expect(rows, hasLength(2));
      expect(
        rows.map((r) => r.products.length),
        everyElement(DiscoverPage.productsPerRow),
      );
    });

    test(
      'four products still read as one full row, with nothing left over',
      () {
        final rows = _sectionsOf<ProductRowSection>(
          DiscoverPage.compose(
            stories: _fullRail(),
            products: _products(4),
            closet: const [],
          ),
        );
        expect(rows, hasLength(1));
        expect(rows.single.products, hasLength(4));
      },
    );

    test('the lead-row rule, stated directly', () {
      // Fill the row unless the remainder could not stand on its own.
      expect(DiscoverPage.leadRowSize(0), 0);
      expect(DiscoverPage.leadRowSize(1), 1); // the only row it will ever have
      expect(DiscoverPage.leadRowSize(2), 2);
      expect(DiscoverPage.leadRowSize(4), 4); // remainder 0 — nothing stranded
      expect(DiscoverPage.leadRowSize(5), 3); // was 4, stranding one
      expect(DiscoverPage.leadRowSize(6), 4);
      expect(DiscoverPage.leadRowSize(9), 4);
    });

    test(
      'a module that declines hands its inventory back to the closing row',
      () {
        // Complete Your Look needs two DIFFERENT categories to say anything
        // real. Given products that are all one category it returns nothing —
        // and the products it did not take must not vanish with it.
        final products = [
          for (var i = 0; i < 6; i++) _product('p$i', category: 'tops'),
        ];
        final layout = DiscoverPage.compose(
          stories: _fullRail(),
          products: products,
          closet: [_owned('w1')],
        );
        expect(_sectionsOf<CompleteLookSection>(layout), isEmpty);
        expect(
          layout.usedProductIds,
          hasLength(6),
          reason: 'nothing may be left behind by a module that stood down',
        );
      },
    );

    test('an exhausted catalog does not blank the editorial slots', () {
      // One source running dry must not take the rest of the page with it.
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: const [],
        closet: const [],
      );
      expect(_sectionsOf<ProductRowSection>(layout), isEmpty);
      expect(_sectionsOf<CampaignSection>(layout), hasLength(1));
      expect(_sectionsOf<NewsroomSection>(layout), hasLength(1));
      expect(_sectionsOf<MoodPulseSection>(layout), hasLength(1));
    });
  });

  group('the pool feeds the editorial slots, the rail only shows six', () {
    test('a deep giveaway pool cannot crowd the newsroom off the rail', () {
      // The regression this guards, in both of its forms.
      //
      // FIRST: giveaways rank above the newsroom, so once a source could
      // contribute several cards, the giveaways filled the rail and the
      // Newsroom card below it claimed there was nothing to read — on an
      // account with thousands of articles. That half was fixed by having the
      // editorial slots read the POOL rather than the visible rail.
      //
      // SECOND, and what this release fixes: the RAIL itself was still six
      // giveaways. The card below was right and the surface was still a
      // giveaway board. The rail is now drawn round-robin and giveaways carry a
      // page-wide budget, so a giveaway table of any size buys the same one or
      // two cards.
      final pool = <DiscoverStory>[
        for (var i = 0; i < 7; i++)
          _story(DiscoverStoryType.giveaway, id: 'g$i'),
        _story(DiscoverStoryType.newsroom, id: 'n1'),
      ];
      final layout = DiscoverPage.compose(
        stories: pool,
        products: _products(8),
        closet: const [],
      );

      final rail = _sectionsOf<StoryRailSection>(layout).single;
      expect(
        rail.stories.map((s) => s.id),
        contains('n1'),
        reason: 'the one article must reach the rail past seven giveaways',
      );
      expect(
        rail.stories.where((s) => s.type == DiscoverStoryType.giveaway),
        hasLength(lessThanOrEqualTo(DiscoverPage.maxGiveawayCards)),
      );
      expect(
        _sectionsOf<NewsroomSection>(layout).single.story?.id,
        'n1',
        reason: 'the card chooses from the POOL, not from the visible rail',
      );
    });

    test('the rail is a prefix of the pool — no reshuffle', () {
      final pool = <DiscoverStory>[
        for (var i = 0; i < 9; i++)
          _story(DiscoverStoryType.newsroom, id: 'n$i'),
      ];
      final rail = _sectionsOf<StoryRailSection>(
        DiscoverPage.compose(
          stories: pool,
          products: const [],
          closet: const [],
        ),
      ).single;
      expect(
        rail.stories.map((s) => s.id).toList(),
        pool.take(DiscoverRail.maxCards).map((s) => s.id).toList(),
      );
    });
  });

  // ---------------------------------------------------------------------
  // Depth and mix.
  //
  // Two separate complaints, one composition: Discover could come out with too
  // few cards to be worth opening, and what it did show was mostly giveaways.
  // Both are decided here, so both are pinned here.
  // ---------------------------------------------------------------------

  group('content mix', () {
    /// Giveaway cards anywhere on the page — rail, fallback and campaign card
    /// together. Counting one section alone is how "at most two" became four.
    int giveaways(DiscoverPageLayout layout) =>
        layout.cardsOfType(DiscoverStoryType.giveaway);
    int news(DiscoverPageLayout layout) =>
        layout.cardsOfType(DiscoverStoryType.newsroom);

    test('20 news + 10 giveaways: news leads, giveaways stay capped', () {
      final layout = DiscoverPage.compose(
        stories: [
          for (var i = 0; i < 10; i++)
            _story(DiscoverStoryType.giveaway, id: 'g$i'),
          for (var i = 0; i < 20; i++)
            _story(DiscoverStoryType.newsroom, id: 'n$i'),
        ],
        products: _products(8),
        closet: [_owned('w1')],
      );

      expect(
        giveaways(layout),
        lessThanOrEqualTo(DiscoverPage.maxGiveawayCards),
      );
      expect(
        news(layout),
        greaterThan(giveaways(layout)),
        reason: 'an editorial surface with 20 articles must read as editorial',
      );
      expect(layout.cardCount, greaterThanOrEqualTo(DiscoverPage.targetCards));
      expect(layout.isThin, isFalse);
    });

    test('few news + many giveaways: availability never buys dominance', () {
      // The founder's actual report. Ten live listings and one article used to
      // produce four giveaway cards and one read.
      final layout = DiscoverPage.compose(
        stories: [
          for (var i = 0; i < 10; i++)
            _story(DiscoverStoryType.giveaway, id: 'g$i'),
          _story(DiscoverStoryType.newsroom, id: 'n0'),
        ],
        products: _products(8),
        closet: [_owned('w1')],
      );

      expect(
        giveaways(layout),
        lessThanOrEqualTo(DiscoverPage.maxGiveawayCards),
      );
      expect(
        news(layout),
        greaterThanOrEqualTo(1),
        reason: 'the one article there is must not be crowded out',
      );
    });

    test('many news + zero giveaways: no empty giveaway card is invented', () {
      final layout = DiscoverPage.compose(
        stories: [
          for (var i = 0; i < 12; i++)
            _story(DiscoverStoryType.newsroom, id: 'n$i'),
        ],
        products: _products(8),
        closet: [_owned('w1')],
      );

      expect(giveaways(layout), 0);
      expect(news(layout), greaterThanOrEqualTo(1));
      // The slot still holds its place — as an honest invitation into the hub,
      // never as a fabricated campaign.
      expect(_sectionsOf<CampaignSection>(layout).single.story, isNull);
    });

    test('the campaign card and the rail share ONE giveaway budget', () {
      final layout = DiscoverPage.compose(
        stories: [
          for (var i = 0; i < 5; i++)
            _story(DiscoverStoryType.giveaway, id: 'g$i'),
          for (var i = 0; i < 5; i++)
            _story(DiscoverStoryType.newsroom, id: 'n$i'),
        ],
        products: _products(8),
        closet: [_owned('w1')],
      );

      expect(
        _sectionsOf<CampaignSection>(layout).single.story?.type,
        DiscoverStoryType.giveaway,
        reason: 'a live giveaway is still the stronger campaign',
      );
      expect(
        giveaways(layout),
        lessThanOrEqualTo(DiscoverPage.maxGiveawayCards),
        reason: 'the campaign card counts against the same budget as the rail',
      );
    });

    test('one kind cannot take every rail slot while another waits', () {
      final layout = DiscoverPage.compose(
        stories: [
          for (var i = 0; i < 6; i++)
            _story(DiscoverStoryType.offer, id: 'o$i'),
          for (var i = 0; i < 6; i++)
            _story(DiscoverStoryType.newsroom, id: 'n$i'),
        ],
        products: const [],
        closet: const [],
      );

      final kinds = _sectionsOf<StoryRailSection>(
        layout,
      ).single.stories.map((s) => s.type).toSet();
      expect(kinds, hasLength(greaterThan(1)));
    });
  });

  group('feed depth', () {
    test('a stocked account clears the ten-card target', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(12),
        closet: [_owned('w1')],
      );
      expect(layout.cardCount, greaterThanOrEqualTo(DiscoverPage.targetCards));
      expect(layout.isThin, isFalse);
    });

    test('exactly ten eligible records still make a full page', () {
      // Six stories and four products — the smallest input that can honestly
      // reach the target, and it must, without borrowing anything.
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(4),
        closet: const [],
      );
      expect(layout.cardCount, greaterThanOrEqualTo(DiscoverPage.targetCards));
    });

    test('fewer than ten degrades honestly — never padded, never repeated', () {
      final layout = DiscoverPage.compose(
        stories: [
          _story(DiscoverStoryType.newsroom, id: 'n0'),
          _story(DiscoverStoryType.giveaway, id: 'g0'),
        ],
        products: _products(2),
        closet: const [],
      );

      expect(layout.isThin, isTrue);
      expect(
        layout.cardCount,
        lessThan(DiscoverPage.targetCards),
        reason: 'the shortage is REPORTED, not filled in with duplicates',
      );
      final ids = [
        for (final section in layout.sections)
          if (section is StoryRailSection)
            ...section.stories.map((s) => s.id)
          else if (section is ProductRowSection)
            ...section.products.map((p) => p.id),
      ];
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('duplicate candidates count once, and cannot pad the page', () {
      final duplicated = <DiscoverStory>[
        for (var i = 0; i < 4; i++)
          _story(DiscoverStoryType.newsroom, id: 'n0'), // the SAME article
        _story(DiscoverStoryType.giveaway, id: 'g0'),
      ];
      final layout = DiscoverPage.compose(
        // The screen hands over a pool that DiscoverRail.pool has already
        // de-duplicated; this asserts the composer does not undo that, and that
        // repetition cannot buy depth.
        stories: DiscoverRail.pool(duplicated, now: DateTime.now()),
        products: _products(3),
        closet: const [],
      );

      final rail = _sectionsOf<StoryRailSection>(layout).single;
      expect(rail.stories.map((s) => s.id).toSet(), hasLength(2));
      expect(layout.isThin, isTrue);
    });

    test('a later page appends without reshuffling what is already drawn', () {
      // Discover itself does not paginate — it closes on its second curated row
      // and View all takes over — but the FEED behind it does, and page 2
      // arriving must not rewrite the page the user is already looking at.
      final stories = _fullRail();
      final page1 = _products(6);
      final composed = DiscoverPage.compose(
        stories: stories,
        products: page1,
        closet: const [],
      );
      final appended = DiscoverPage.compose(
        stories: stories,
        // Exactly what ProductFeed.loadMore produces: the same items, in the
        // same order, with the next page after them.
        products: [...page1, for (var i = 6; i < 12; i++) _product('p$i')],
        closet: const [],
      );

      List<String> placed(DiscoverPageLayout l) => [
        for (final section in l.sections)
          if (section is ProductRowSection)
            ...section.products.map((p) => p.id),
      ];
      expect(
        placed(appended).take(placed(composed).length),
        placed(composed),
        reason: 'page 1 keeps its cards and its order when page 2 lands',
      );
      expect(placed(appended).toSet(), hasLength(placed(appended).length));
      expect(
        appended.sections.map((s) => s.key).toList(),
        composed.sections.map((s) => s.key).toList(),
        reason: 'section keys are stable, so scroll and image cache survive',
      );
    });

    test('a product is still placed at most once across the whole page', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(12),
        closet: [_owned('w1')],
      );
      final placed = [
        for (final section in layout.sections)
          if (section is ProductRowSection)
            ...section.products.map((p) => p.id),
      ];
      expect(placed.toSet(), hasLength(placed.length));
      expect(layout.usedProductIds, containsAll(placed));
    });
  });

  /// ISSUE 4 — "products below the Newsroom appear for some accounts and not
  /// others on the same build".
  ///
  /// Root cause: the page allocated greedily and in visual order, so
  /// `Complete Your Look` — an OPTIONAL, personalized module — drew from the
  /// same pool the closing row still needed. On the five-product production
  /// catalog the lead row took three, the look took the remaining two, and the
  /// closing row got nothing. Whether that row existed therefore depended on
  /// whether the viewer's closet happened to contain categorised garments.
  ///
  /// The invariant these pin: the ROWS are a function of the catalog alone.
  group('row reservation: personalization ranks, it never gates', () {
    /// Every account shape the acceptance list names, against one catalog.
    final accounts = <String, ({List<WardrobeItem> closet, bool resolved})>{
      'brand-new account (no closet)': (closet: const [], resolved: true),
      'empty closet, confirmed': (closet: const [], resolved: true),
      'populated closet': (
        closet: [_owned('w1'), _owned('w2', title: 'Wide trousers')],
        resolved: true,
      ),
      'wardrobe still loading': (closet: const [], resolved: false),
      'wardrobe loaded but uncategorised': (
        closet: [WardrobeItem(id: 'w9', title: 'Unknown piece')],
        resolved: true,
      ),
    };

    for (final entry in accounts.entries) {
      test('five-product catalog → same rows for ${entry.key}', () {
        final layout = DiscoverPage.compose(
          stories: _fullRail(),
          products: _products(5),
          closet: entry.value.closet,
          closetResolved: entry.value.resolved,
        );
        final rows = _sectionsOf<ProductRowSection>(layout);
        expect(
          rows,
          hasLength(2),
          reason: 'the closing row below the Newsroom must always exist',
        );
        expect(rows.first.products, hasLength(3));
        expect(
          rows.last.products,
          hasLength(2),
          reason: 'this is the row that used to vanish for stocked accounts',
        );
      });
    }

    test('the rows are byte-identical across every account shape', () {
      List<List<String>> rowsFor(
        List<WardrobeItem> closet, {
        bool resolved = true,
      }) => [
        for (final row in _sectionsOf<ProductRowSection>(
          DiscoverPage.compose(
            stories: _fullRail(),
            products: _products(5),
            closet: closet,
            closetResolved: resolved,
          ),
        ))
          row.products.map((p) => p.id).toList(),
      ];

      final empty = rowsFor(const []);
      expect(rowsFor([_owned('w1'), _owned('w2')]), empty);
      expect(rowsFor(const [], resolved: false), empty);
    });

    test('a loading wardrobe is not read as an empty one', () {
      // Absent-because-loading must not be answered as absent-because-empty:
      // the module used to appear a beat later and take the closing row with
      // it. It is simply withheld until the closet is a fact.
      final loading = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(12),
        closet: [_owned('w1')],
        closetResolved: false,
      );
      expect(_sectionsOf<CompleteLookSection>(loading), isEmpty);

      final resolved = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(12),
        closet: [_owned('w1')],
        closetResolved: true,
      );
      expect(_sectionsOf<CompleteLookSection>(resolved), hasLength(1));

      // ...and the rows did not move when it arrived.
      List<int> shape(DiscoverPageLayout l) =>
          _sectionsOf<ProductRowSection>(l).map((r) => r.products.length).toList();
      expect(shape(loading), shape(resolved));
    });

    test('a mid-sized catalog still affords every module', () {
      // The reservation must not swing the other way and starve the look: at
      // eight products both rows AND the module have to fit.
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
      );
      expect(_sectionsOf<ProductRowSection>(layout), hasLength(2));
      expect(_sectionsOf<CompleteLookSection>(layout), hasLength(1));
    });

    test('the reservation, stated directly', () {
      RowReservation plan(int n) => DiscoverPage.planRows(n);
      expect(plan(0), const RowReservation(lead: 0, closing: 0));
      expect(plan(1), const RowReservation(lead: 1, closing: 0));
      expect(plan(4), const RowReservation(lead: 4, closing: 0));
      // The production catalog: both rows clear the minimum, look gets nothing.
      expect(plan(5), const RowReservation(lead: 3, closing: 2));
      expect(plan(6), const RowReservation(lead: 4, closing: 2));
      // Closing gives back to its own floor so the module can exist too.
      expect(plan(8), const RowReservation(lead: 4, closing: 2));
      // Deep catalog: both rows at the ceiling, module still fed.
      expect(plan(20), const RowReservation(lead: 4, closing: 4));
    });

    test('a deeper catalog never shrinks a row below a shallower one', () {
      var previous = 0;
      for (var n = 4; n <= 30; n++) {
        final p = DiscoverPage.planRows(n);
        expect(
          p.total,
          greaterThanOrEqualTo(previous),
          reason: 'adding catalog must never remove cards from the page',
        );
        previous = p.total;
        if (n > DiscoverPage.productsPerRow) {
          expect(
            p.closing,
            greaterThanOrEqualTo(DiscoverPage.minProductsPerRow),
            reason: 'the closing row is guaranteed once a second row is viable',
          );
        }
      }
    });

    test('a seen-heavy account still receives products', () {
      // Seen-state is display-only in this app — the rail dims a seen story and
      // the product feed carries no seen filter at all. This pins that: nothing
      // about having viewed the catalog may remove it.
      final products = _products(12);
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: products,
        closet: [_owned('w1')],
      );
      expect(_sectionsOf<ProductRowSection>(layout), hasLength(2));
      expect(layout.usedProductIds, isNotEmpty);
    });

    test('nothing is stranded when the module declines', () {
      // Seven products: rows reserve 4 + 2, leaving one — too few for a look,
      // so the leftover falls back into the closing row rather than vanishing.
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: [
          for (var i = 0; i < 7; i++) _product('p$i', category: 'tops'),
        ],
        closet: [_owned('w1')],
      );
      expect(_sectionsOf<CompleteLookSection>(layout), isEmpty);
      expect(layout.usedProductIds, hasLength(7));
    });
  });

  /// ISSUE 3 — image-required placements.
  ///
  /// "A quick read" is a full-width photograph with a headline over it. It used
  /// to take whichever newsroom story ranked first, so a publisher that exposes
  /// no thumbnail (Highsnobiety publishes none; Hypebeast buries it in the
  /// description HTML) could win the slot and render it as a bare gradient next
  /// to a rail of real photographs.
  group('a picture slot asks for a story with a picture', () {
    DiscoverStory news(String id, {String? image}) => DiscoverStory(
      id: id,
      type: DiscoverStoryType.newsroom,
      category: 'NEWSROOM',
      title: 'Article $id',
      imageUrl: image,
      destination: const DiscoverStoryDestination(route: AppRoute.wtmNewsroom),
    );

    NewsroomSection newsroomOf(DiscoverPageLayout layout) =>
        _sectionsOf<NewsroomSection>(layout).single;

    test('skips the top-ranked article when it has no image', () {
      final layout = DiscoverPage.compose(
        stories: [
          news('no-picture'),
          news('has-picture', image: 'https://cdn/hero.jpg'),
        ],
        products: _products(8),
      );
      expect(newsroomOf(layout).story?.id, 'has-picture');
    });

    test('takes the highest-ranked article that DOES have one', () {
      final layout = DiscoverPage.compose(
        stories: [
          news('a'),
          news('b'),
          news('c', image: 'https://cdn/c.jpg'),
          news('d', image: 'https://cdn/d.jpg'),
        ],
        products: _products(8),
      );
      expect(newsroomOf(layout).story?.id, 'c');
    });

    test('falls back to the branded card, never to a borrowed photo', () {
      final layout = DiscoverPage.compose(
        stories: [news('a'), news('b')],
        products: _products(8),
      );
      final section = newsroomOf(layout);
      expect(section.story, isNull, reason: 'the branded placeholder is the fallback');
      // And it must not have reached for someone else's artwork to fill it.
      expect(
        layout.sections.whereType<NewsroomSection>().single.story?.imageUrl,
        isNull,
      );
    });

    test('the slot still holds its place, so the page does not reshuffle', () {
      final layout = DiscoverPage.compose(
        stories: [news('a')],
        products: _products(8),
      );
      expect(_sectionsOf<NewsroomSection>(layout), hasLength(1));
    });

    test('a picture-less article is not deleted from the page', () {
      // It is still eligible, still countable, still reachable — it just does
      // not own the visual slot. Deleting it would remove whole publishers from
      // the Newsroom for a reason that is not theirs.
      final withoutPicture = news('quiet');
      expect(withoutPicture.isEligibleAt(DateTime(2026, 8, 18)), isTrue);
      expect(withoutPicture.isImageReady, isFalse);
    });

    test('image readiness is about having one, not about ranking', () {
      expect(news('x', image: 'https://cdn/x.jpg').isImageReady, isTrue);
      expect(news('x', image: '   ').isImageReady, isFalse);
      expect(news('x', image: null).isImageReady, isFalse);
    });
  });
}
