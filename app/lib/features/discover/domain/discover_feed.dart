import 'package:flutter/foundation.dart';

import '../../../data/models/product.dart';
import '../../../data/models/wardrobe_item.dart';
import 'discover_story.dart';

/// One band of the Discover feed (DISCOVER spec §16).
///
/// A sealed hierarchy rather than a map with a `type` string: the renderer
/// switches exhaustively, so adding a variant is a compile error at every
/// place that has to handle it instead of a blank row discovered in QA. And
/// nothing infers a band's kind from its title (§16 is explicit about that).
@immutable
sealed class DiscoverFeedItem {
  const DiscoverFeedItem();

  /// Stable across rebuilds — this is the widget key, so a churning value
  /// would throw away scroll position and image cache on every refresh (§23).
  String get key;
}

/// Which curated band a product strip is.
///
/// The renderer maps this to an eyebrow and a heading from l10n. The slot is a
/// TYPE, never display text: nothing downstream may read a band's meaning out
/// of its copy (§16), and the copy has to be translatable (§34).
enum DiscoverStripSlot {
  /// The lead band under the Story rail.
  pickedForYou,

  /// The first band after the mixed editorial modules.
  moreForYou,

  /// Every band after that, as pagination brings more in.
  keepExploring,
}

/// A small curated band of products, scrolled horizontally.
///
/// Capped at [DiscoverFeedComposer.productsPerStrip] cards and introduced by
/// its own section heading, which is what keeps Discover from turning back
/// into a wall of product tiles. A vertical grid cannot interleave full-width
/// modules without nesting a second scrollable, and two scrollables with
/// conflicting physics is exactly the conflict §15 and §41 call out.
final class ProductStripItem extends DiscoverFeedItem {
  const ProductStripItem({
    required this.slot,
    required this.products,
    required this.ordinal,
  });

  final DiscoverStripSlot slot;
  final List<Product> products;

  /// Position among the strips, counting from zero. Part of the key, so two
  /// bands that somehow held the same products still get distinct identities.
  final int ordinal;

  @override
  String get key => 'strip:$ordinal:${products.map((p) => p.id).join(':')}';
}

/// `COMPLETE YOUR LOOK` — one owned closet item plus matching products (§9.1).
final class CompleteLookItem extends DiscoverFeedItem {
  const CompleteLookItem({required this.anchor, required this.suggestions});

  /// Something the user already owns. Never a purchase suggestion dressed up
  /// as one — the module's whole point is starting from their wardrobe.
  final WardrobeItem anchor;
  final List<Product> suggestions;

  @override
  String get key => 'look:${anchor.id}';
}

/// A Giveaway, Offer or Newsroom module, rendered from the same story the rail
/// uses so there is one source of truth for that content.
final class StoryModuleItem extends DiscoverFeedItem {
  const StoryModuleItem(this.story);

  final DiscoverStory story;

  @override
  String get key => 'module:${story.id}:${story.contentVersion}';
}

/// Composes the Discover feed (§8.3).
abstract final class DiscoverFeedComposer {
  /// Products in one curated band. Four is the ceiling the approved layout
  /// sets: a band never grows into a grid.
  static const productsPerStrip = 4;

  /// Builds the feed in the approved order.
  ///
  /// ```text
  /// curated strip  →  Complete Your Look
  ///                →  Giveaway / Offer card
  ///                →  Newsroom card
  ///                →  more products, one band at a time
  /// ```
  ///
  /// Every product band is at most [productsPerStrip] cards and carries its
  /// own heading, so the feed never reads as product-after-product. Modules are
  /// consumed in order and simply run out; an unavailable module is never
  /// rendered as an empty section (§8.3, §26.15).
  ///
  /// Note on deduplication: a Giveaway/Offer/Newsroom campaign appears BOTH in
  /// the Story rail and as a feed card here. §33.3 allows exactly that when a
  /// campaign rule calls for it, and the approved layout does — the rail is a
  /// glance, the card is the editorial pitch. Product deduplication is still
  /// absolute: [products] arrives already unique by id from the feed.
  static List<DiscoverFeedItem> compose({
    required List<Product> products,
    List<DiscoverStory> modules = const [],
    List<CompleteLookItem> completeLooks = const [],
    int productsPerStrip = productsPerStrip,
  }) {
    if (products.isEmpty) return const [];
    final size = productsPerStrip < 1 ? 1 : productsPerStrip;

    final bands = <List<Product>>[];
    for (var i = 0; i < products.length; i += size) {
      final end = i + size;
      bands.add(
        products.sublist(i, end > products.length ? products.length : end),
      );
    }

    // The lead modules, in the approved order. Taken OUT of the pool so a
    // story cannot be both the lead card and a spare further down.
    final pool = [...modules];
    DiscoverStory? take(DiscoverStoryType type) {
      final index = pool.indexWhere((story) => story.type == type);
      return index < 0 ? null : pool.removeAt(index);
    }

    // One campaign card, giveaway preferred — a live giveaway is the stronger
    // invitation, and §26.13 allows only one module per slot.
    final campaign =
        take(DiscoverStoryType.giveaway) ?? take(DiscoverStoryType.offer);
    final editorial = take(DiscoverStoryType.newsroom);

    final lead = <DiscoverFeedItem>[
      // Complete Your Look leads: it is the retention module, and it is about
      // something the user already owns rather than something to buy.
      if (completeLooks.isNotEmpty) completeLooks.first,
      if (campaign != null) StoryModuleItem(campaign),
      if (editorial != null) StoryModuleItem(editorial),
    ];

    // Real modules held back to break up the tail. Never invented — when these
    // run out the tail is bands with headings, not a manufactured banner.
    //
    // Whatever is left in `pool` is deliberately NOT here. The approved layout
    // carries exactly one campaign card and one read; a second Offer card
    // further down would be the rail repeated in the feed, which is the one
    // duplication the layout rules forbid outright. That content is still one
    // tap away — from its rail card, and from the section heading's action.
    final spare = <DiscoverFeedItem>[
      for (final look in completeLooks.skip(1)) look,
    ];

    final items = <DiscoverFeedItem>[
      ProductStripItem(
        slot: DiscoverStripSlot.pickedForYou,
        products: bands.first,
        ordinal: 0,
      ),
      ...lead,
    ];

    var spareIndex = 0;
    for (var i = 1; i < bands.length; i++) {
      items.add(
        ProductStripItem(
          slot: i == 1
              ? DiscoverStripSlot.moreForYou
              : DiscoverStripSlot.keepExploring,
          products: bands[i],
          ordinal: i,
        ),
      );
      if (spareIndex < spare.length) items.add(spare[spareIndex++]);
    }
    // A module the loop never reached still goes in rather than being dropped:
    // it is real content, and the tail is where it does the most work.
    while (spareIndex < spare.length) {
      items.add(spare[spareIndex++]);
    }

    return items;
  }

  /// Picks the closet item and the products to pair with it (§9.1).
  ///
  /// Deterministic and explainable: anchor on a garment the user owns, then
  /// suggest products from DIFFERENT categories, because "your black dress +
  /// another black dress" is not completing a look. Returns null rather than a
  /// weak module — an empty or nonsensical suggestion set is worse than no
  /// module at all (§26.15).
  static CompleteLookItem? completeLook({
    required List<WardrobeItem> closet,
    required List<Product> products,
    int maxSuggestions = 3,
  }) {
    if (closet.isEmpty || products.isEmpty) return null;

    final anchor = closet.firstWhere(
      (item) => (item.category ?? '').trim().isNotEmpty,
      orElse: () => closet.first,
    );
    return _lookFor(
      anchor: anchor,
      products: products,
      maxSuggestions: maxSuggestions,
    );
  }

  /// Several Complete Your Look modules, one per distinct closet category.
  ///
  /// The first leads the feed; the rest are held back to break up the tail.
  /// Anchors and suggestions are both kept distinct, so the second module is a
  /// genuinely different idea rather than the first one repeated with a new
  /// title — which would be the fake-content trap §26.10 warns about.
  static List<CompleteLookItem> completeLooks({
    required List<WardrobeItem> closet,
    required List<Product> products,
    int max = 3,
    int maxSuggestions = 3,
  }) {
    if (closet.isEmpty || products.isEmpty || max < 1) return const [];

    final looks = <CompleteLookItem>[];
    final anchorCategories = <String>{};
    final spentProducts = <String>{};

    for (final anchor in closet) {
      if (looks.length >= max) break;
      // One anchor per category — "Your dress" then "Your other dress" reads
      // as a bug, not a suggestion. An uncategorised garment gets one turn.
      final category = (anchor.category ?? '').trim().toLowerCase();
      if (!anchorCategories.add(category)) continue;

      final look = _lookFor(
        anchor: anchor,
        products: products
            .where((product) => !spentProducts.contains(product.id))
            .toList(growable: false),
        maxSuggestions: maxSuggestions,
      );
      if (look == null) continue;
      looks.add(look);
      spentProducts.addAll(look.suggestions.map((product) => product.id));
    }
    return looks;
  }

  /// The suggestion half of a Complete Your Look, for one already chosen
  /// [anchor]. Null when fewer than two different categories are available —
  /// two is the minimum that reads as "completing" something.
  static CompleteLookItem? _lookFor({
    required WardrobeItem anchor,
    required List<Product> products,
    required int maxSuggestions,
  }) {
    // The module renders "Your {item}". A garment carrying neither a title nor
    // a category cannot finish that sentence, and the header came out as a
    // bare "Your " on a real closet. Skipped rather than rendered nameless —
    // there is always another garment to anchor on.
    if ((anchor.title ?? anchor.category ?? '').trim().isEmpty) return null;

    final anchorCategory = (anchor.category ?? '').trim().toLowerCase();
    final suggestions = <Product>[];
    final usedCategories = <String>{
      if (anchorCategory.isNotEmpty) anchorCategory,
    };

    for (final product in products) {
      final category = (product.category ?? '').trim().toLowerCase();
      if (category.isEmpty || usedCategories.contains(category)) continue;
      suggestions.add(product);
      usedCategories.add(category);
      if (suggestions.length >= maxSuggestions) break;
    }

    if (suggestions.length < 2) return null;
    return CompleteLookItem(anchor: anchor, suggestions: suggestions);
  }
}
