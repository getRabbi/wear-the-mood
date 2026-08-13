import 'package:flutter/foundation.dart';

import '../../../data/models/product.dart';
import '../../../data/models/wardrobe_item.dart';
import 'discover_feed.dart';
import 'discover_story.dart';

/// One section of the Discover page, in the approved layout's own vocabulary.
///
/// A sealed hierarchy so the renderer switches exhaustively: a new section kind
/// is a compile error at every place that has to draw it, never a blank band
/// found on a device.
///
/// This is deliberately NOT the old [DiscoverFeedItem]. That type described a
/// feed the SERVER ordered — products arriving in pages, with modules dropped
/// into whatever gaps were left. The approved layout is the opposite: Flutter
/// fixes the sequence and the backend only supplies what goes in each slot.
@immutable
sealed class DiscoverSection {
  const DiscoverSection();

  /// Stable across rebuilds — this is the widget key, so a churning value would
  /// throw away scroll position and the image cache on every refresh.
  String get key;
}

/// The horizontal portrait Story rail. Always the first content section.
final class StoryRailSection extends DiscoverSection {
  const StoryRailSection(this.stories);

  final List<DiscoverStory> stories;

  @override
  String get key => 'rail:${stories.map((s) => s.id).join(',')}';
}

/// The one compact interactive card (the mood pulse).
final class MoodPulseSection extends DiscoverSection {
  const MoodPulseSection();

  @override
  String get key => 'pulse';
}

/// Which curated product row this is. There are exactly TWO, and the page never
/// grows a third.
///
/// The slot is a TYPE, never display text: the renderer maps it to a heading
/// from l10n, and nothing downstream reads a row's meaning out of its copy. Each
/// is used at most once, so a heading can never repeat.
///
/// The approved prototype carries two product strips and nothing else: one under
/// the interaction card, one closing the page after the editorial modules.
/// Discover is a curated surface, not a catalog — everything past these two rows
/// lives behind View all, which is a browse screen built for exactly that.
enum DiscoverRowSlot {
  /// The lead curated row, under the interaction card.
  pickedForYou,

  /// The approved layout's closing row, after the editorial modules.
  newForYourMood,
}

/// A curated row of products, scrolled horizontally under its own heading.
///
/// Capped at [DiscoverPage.productsPerRow]. There is no grid variant on
/// purpose: a two-column wall is the shape this redesign exists to remove.
final class ProductRowSection extends DiscoverSection {
  const ProductRowSection({required this.slot, required this.products});

  final DiscoverRowSlot slot;
  final List<Product> products;

  @override
  String get key => 'row:${slot.name}';
}

/// `COMPLETE YOUR LOOK` — exactly one per page.
final class CompleteLookSection extends DiscoverSection {
  const CompleteLookSection(this.look);

  final CompleteLookItem look;

  @override
  String get key => 'look:${look.anchor.id}';
}

/// The full-width Giveaway **or** Offer editorial card — exactly one, never
/// both, and never two of either.
///
/// [story] is null when nothing is live. The card still renders, as an
/// invitation into the Giveaways hub rather than a fabricated campaign: the
/// approved layout keeps a fixed rhythm, so this slot holding its place is what
/// stops the page reshuffling every time a campaign starts or ends.
final class CampaignSection extends DiscoverSection {
  const CampaignSection(this.story);

  final DiscoverStory? story;

  @override
  String get key => story == null
      ? 'campaign:empty'
      : 'campaign:${story!.id}:${story!.contentVersion}';
}

/// The landscape Newsroom / Style Note card — exactly one.
///
/// [story] is null when there is nothing new to read; the card then invites the
/// user into the Newsroom instead of claiming an article that is not there.
final class NewsroomSection extends DiscoverSection {
  const NewsroomSection(this.story);

  final DiscoverStory? story;

  @override
  String get key => story == null
      ? 'news:empty'
      : 'news:${story!.id}:${story!.contentVersion}';
}

/// The composed page: an ordered section list plus what it consumed.
@immutable
class DiscoverPageLayout {
  const DiscoverPageLayout({
    required this.sections,
    required this.usedProductIds,
    required this.rowsRendered,
    required this.cardCount,
    this.fallbackStory,
  });

  final List<DiscoverSection> sections;

  /// The single story to draw as the compact card above the page, when there
  /// were too few for a rail AND no editorial slot below will already be
  /// showing it. Null the rest of the time — including when the one story IS
  /// the campaign or the read, because that card is the fuller telling of it
  /// and showing both put the same content on screen twice.
  final DiscoverStory? fallbackStory;

  /// Every product id placed on the page. The renderer needs no knowledge of
  /// this; it exists so a test can assert the deduplication rule directly.
  final Set<String> usedProductIds;

  /// How many curated rows were emitted — at most
  /// [DiscoverRowSlot.values.length], which is two. Discover does not
  /// paginate: the page closes on the second row and View all takes over.
  final int rowsRendered;

  /// Real content cards the user can see and act on.
  ///
  /// Counts story cards, product cards, Complete Your Look, and each editorial
  /// card that actually carries content. It deliberately does NOT count the
  /// mood pulse (an interaction, not content) or an editorial slot standing
  /// empty (an invitation into a hub, not an item) — counting either would let
  /// the page report depth it does not have.
  ///
  /// Nothing is ever repeated to raise it. It exists so [isThin] can be
  /// observed rather than guessed at.
  final int cardCount;

  /// The page came out below [DiscoverPage.targetCards].
  ///
  /// Not an error and never rendered: on a young account, an empty region or a
  /// quiet news day it is simply the truth about how much eligible content
  /// exists. The screen reports it so a real content shortage is visible in
  /// analytics instead of being discovered on a device.
  bool get isThin => cardCount < DiscoverPage.targetCards;

  /// Story cards of [type] anywhere on the page — the rail, the compact
  /// fallback and both editorial slots counted together.
  ///
  /// The mix rule this exists for is about what the user SEES, and no single
  /// section can answer that: the campaign card and the rail draw from the same
  /// pool, so counting either alone is how "at most two giveaways" became four
  /// on a device.
  int cardsOfType(DiscoverStoryType type) {
    var count = fallbackStory?.type == type ? 1 : 0;
    for (final section in sections) {
      count += switch (section) {
        StoryRailSection(:final stories) =>
          stories.where((s) => s.type == type).length,
        CampaignSection(:final story) => story?.type == type ? 1 : 0,
        NewsroomSection(:final story) => story?.type == type ? 1 : 0,
        _ => 0,
      };
    }
    return count;
  }
}

/// Builds the approved Discover layout.
///
/// The visible order is fixed here and nowhere else:
///
/// ```text
/// story rail → interaction → Picked for You → Complete Your Look
///            → Giveaway|Offer → Newsroom → New for Your Mood → END
/// ```
///
/// The backend still decides WHAT the content is; this decides where it goes
/// and how often it may appear. That inversion is the whole point — the old
/// composer let a paginated product feed generate its own section rhythm, and
/// what came back was the same module three times and the same heading four.
abstract final class DiscoverPage {
  /// Cards in one curated row. Four is a ceiling, not a target: a row never
  /// grows into a grid.
  static const productsPerRow = 4;

  /// Fewest cards a row is worth drawing with, when another row could have had
  /// them instead.
  ///
  /// The lead row used to take four and leave whatever was left, which on a
  /// small catalog meant `Picked for You` got four, Complete Your Look starved,
  /// and `New for your mood` closed the page with one lonely card — the "content
  /// disappears further down" the founder saw on a five-product catalog. Rows
  /// are now planned against what actually exists, so the page thins evenly
  /// instead of collapsing at the bottom.
  ///
  /// A single row IS allowed to fall below this when it is the only one: two
  /// products under one heading beats two products under no heading.
  static const minProductsPerRow = 2;

  /// Suggestions beside the owned garment in Complete Your Look.
  static const lookSuggestions = 3;

  /// How deep the page aims to be on its first screenful.
  ///
  /// A TARGET, never a quota. Nothing is repeated, padded or invented to reach
  /// it — a page built from four real things shows four. It is here so
  /// [DiscoverPageLayout.isThin] means something specific and can be watched.
  static const targetCards = 10;

  /// The most giveaway cards the whole page may carry — rail and campaign card
  /// counted TOGETHER.
  ///
  /// Discover is a fashion discovery surface, not a giveaway board. Before this
  /// budget the page took whatever the giveaway table happened to hold: the
  /// rail's six slots were filled in type-rank order, giveaways outrank offers
  /// and the newsroom, and three live listings therefore took half the rail and
  /// the campaign card as well — four giveaway cards, and not one article, on
  /// an account with a full news feed.
  ///
  /// Availability is never the reason a kind dominates. This is a CEILING over
  /// real listings: one live giveaway still yields one card.
  static const maxGiveawayCards = 2;

  /// Composes the whole page. There is no second page.
  ///
  /// [products] arrives in server rank order and is consumed strictly in that
  /// order, so a row is always the best remaining content rather than a
  /// reshuffle. Every rule below is enforced HERE, where it can be tested
  /// without a widget:
  ///
  /// * a product id is placed at most once on the whole page;
  /// * Complete Your Look, the campaign card and the Newsroom card appear at
  ///   most once each;
  /// * every row slot is used at most once, so no heading ever repeats;
  /// * a row holds at most [productsPerRow] cards;
  /// * there are at most two rows, and the page ends after the second;
  /// * two rows are never adjacent while a module is available to separate
  ///   them.
  ///
  /// Content-driven slots with nothing behind them are omitted rather than
  /// rendered blank — an empty closet contributes no Complete Your Look, an
  /// empty catalog no rows. The two EDITORIAL slots are the exception: they are
  /// fixed furniture and always emitted, carrying a null story when nothing is
  /// live so the renderer can offer the hub instead. That keeps the page's
  /// rhythm stable and keeps Giveaways and the Newsroom reachable from here on
  /// a quiet day; it never invents a campaign.
  static DiscoverPageLayout compose({
    required List<DiscoverStory> stories,
    required List<Product> products,
    List<WardrobeItem> closet = const [],
    bool storiesEnabled = true,
    bool shoppingEnabled = true,
    int productsPerRow = productsPerRow,
  }) {
    final perRow = productsPerRow < 1 ? 1 : productsPerRow;
    final sections = <DiscoverSection>[];
    final usedProducts = <String>{};

    // A full rail card is a glance and the feed card is the editorial pitch, so
    // the approved layout carries both — that is what the prototype shows.
    final modules = stories;

    // ---- 0. Which campaign the page will run ---------------------------
    //
    // Decided BEFORE the rail, because the two share one giveaway budget and
    // the rail is the one that can give way. A live giveaway is the stronger
    // invitation, so an offer only takes the slot when no giveaway is running.
    final campaign = shoppingEnabled
        ? (_firstOfType(modules, DiscoverStoryType.giveaway) ??
              _firstOfType(modules, DiscoverStoryType.offer))
        : null;

    // ---- 1. Story rail ------------------------------------------------
    //
    // [stories] is the POOL — everything eligible, in rank order.
    // [DiscoverRail.select] draws the visible six from it round-robin, so every
    // source that has something to say is on the rail before any source is on
    // it twice. The editorial slots below still choose from the WHOLE pool, so
    // a rail cannot make a later card claim its own source is empty.
    //
    // The giveaway budget is the page's, not the rail's: when the campaign card
    // is about to re-tell the leading giveaway, the rail takes one fewer, so
    // `maxGiveawayCards` is a promise about the PAGE rather than about one
    // section that another section can quietly double.
    //
    // Below `minCards` a rail is a one-card scroller, which reads as a broken
    // carousel, so the screen shows a compact fallback card for the single
    // story instead.
    final rail = DiscoverRail.select(
      stories,
      caps: {
        DiscoverStoryType.giveaway: campaign?.type == DiscoverStoryType.giveaway
            ? maxGiveawayCards - 1
            : maxGiveawayCards,
      },
    );
    final hasRail = storiesEnabled && rail.length >= DiscoverRail.minCards;
    if (hasRail) sections.add(StoryRailSection(rail));

    // When the rail collapsed, the compact card is the ONLY place that story
    // would appear — unless an editorial slot below is about to show it, which
    // it now always does for a campaign or a read. Handing it to that card and
    // dropping the compact one keeps the content in the richer of the two
    // places without ever showing it twice (caught on device with only a
    // Newsroom item live).
    final DiscoverStory? fallback;
    if (hasRail || rail.isEmpty) {
      fallback = null;
    } else {
      final only = rail.first;
      final claimedBelow =
          shoppingEnabled &&
          const {
            DiscoverStoryType.giveaway,
            DiscoverStoryType.offer,
            DiscoverStoryType.newsroom,
          }.contains(only.type);
      fallback = claimedBelow ? null : only;
    }

    // ---- 2. The one interaction ---------------------------------------
    sections.add(const MoodPulseSection());

    // Remaining products, in rank order, minus anything already placed.
    List<Product> unused() => products
        .where((p) => !usedProducts.contains(p.id))
        .toList(growable: false);

    // ---- How big the LEAD row should be ---------------------------------
    //
    // The page used to be assembled greedily: the lead row took
    // [productsPerRow] and whatever came after made do. On a small catalog that
    // stranded the remainder — five products became a row of four and then a
    // closing row holding a single lonely card, which is the "content
    // disappears further down" the founder saw on the five-product prod
    // catalog.
    //
    // So the lead row still fills to the ceiling whenever the remainder can
    // stand on its own, and only steps back when it cannot. Nothing changes for
    // a catalog of six or more; four still reads as one full row and no second.
    final leadSize = _leadRowSize(products.length, perRow);

    var rows = 0;

    /// Emits one curated row, if there is anything left to put in it.
    ///
    /// [requireSeparator] holds while the approved modules are still being
    /// placed: within that stretch a row may only follow a NON-row, because the
    /// module between them is what keeps two strips from reading as one long
    /// catalog. Past the modules there is nothing left to separate with, and a
    /// distinct heading per row does that work instead.
    ///
    /// Returns false when the row was skipped — the catalog is exhausted,
    /// shopping is off, no heading is left, or the separator rule refused it.
    bool addRow({int? size, bool requireSeparator = false}) {
      if (!shoppingEnabled) return false;
      if (requireSeparator &&
          sections.isNotEmpty &&
          sections.last is ProductRowSection) {
        return false;
      }
      // A slot is a heading, and headings are finite. Take one only once there
      // is content to put under it — a consumed-but-empty slot would silently
      // cost the page a later row.
      if (rows >= DiscoverRowSlot.values.length) return false;
      final take = unused()
          .take(size == null || size > perRow ? perRow : size)
          .toList(growable: false);
      if (take.isEmpty) return false;
      usedProducts.addAll(take.map((p) => p.id));
      sections.add(
        ProductRowSection(slot: DiscoverRowSlot.values[rows], products: take),
      );
      rows++;
      return true;
    }

    // ---- 3. Picked for You --------------------------------------------
    addRow(size: leadSize);

    // ---- 4. Complete Your Look — exactly one --------------------------
    //
    // Built from products NOT already on the page, so the module is a genuinely
    // new idea rather than the lead row restated as thumbnails.
    final look = DiscoverFeedComposer.completeLook(
      closet: closet,
      products: unused(),
      maxSuggestions: lookSuggestions,
    );
    if (look != null) {
      sections.add(CompleteLookSection(look));
      usedProducts.addAll(look.suggestions.map((p) => p.id));
    }

    // ---- 5. One campaign card: giveaway preferred ----------------------
    //
    // A live giveaway is the stronger invitation, so an offer only takes the
    // slot when no giveaway is running. Never both — the approved layout has
    // one campaign card, and two stacked would be the rail repeated in the
    // feed.
    //
    // Both editorial cards ride with [shoppingEnabled], exactly as they did
    // before this composer existed. That flag is the single lever over the
    // whole lower half of Discover; with it off the surface is the rail and
    // the interaction, and the same content is still one tap away from its
    // rail card.
    //
    // Both cards are emitted whether or not there is anything live. A slot that
    // vanishes when a campaign ends makes the page reshuffle under the user and
    // costs Giveaways and the Newsroom their only entry point on this surface;
    // an empty one is an honest invitation, not an invented campaign.
    if (shoppingEnabled) {
      sections.add(CampaignSection(campaign));

      // ---- 6. One Newsroom card ----------------------------------------
      sections.add(
        NewsroomSection(_firstOfType(modules, DiscoverStoryType.newsroom)),
      );
    }

    // ---- 7. The closing curated row -------------------------------------
    //
    // Separated: on a page where no module was available — an empty closet, no
    // live campaign, no article — this row is skipped rather than stacked
    // straight onto the lead row. The products are not lost; they are one tap
    // away behind View all, which paginates.
    //
    // BACKFILL. Whatever is genuinely left, up to the row ceiling — not a share
    // fixed in advance. Complete Your Look may have declined (too few distinct
    // categories to make a real suggestion), and when it does its inventory
    // comes back here rather than being stranded.
    addRow(requireSeparator: true);

    // ---- 8. Nothing ------------------------------------------------------
    //
    // The page ENDS here. No pagination tail, no further rows: the approved
    // layout closes on this row and the bottom spacing, and anything more is a
    // catalog wall growing back one heading at a time. More products are a tap
    // away behind View all.

    return DiscoverPageLayout(
      sections: List.unmodifiable(sections),
      usedProductIds: Set.unmodifiable(usedProducts),
      rowsRendered: rows,
      cardCount: _countCards(sections, fallback: fallback),
      fallbackStory: fallback,
    );
  }

  /// Real content cards in [sections] — see [DiscoverPageLayout.cardCount].
  static int _countCards(
    List<DiscoverSection> sections, {
    required DiscoverStory? fallback,
  }) {
    // The compact fallback card is what the rail collapses into, so it is the
    // one story card the page carries when there is no rail.
    var count = fallback == null ? 0 : 1;
    for (final section in sections) {
      count += switch (section) {
        StoryRailSection(:final stories) => stories.length,
        ProductRowSection(:final products) => products.length,
        CompleteLookSection() => 1,
        // An empty editorial slot is an invitation into a hub, not an item.
        CampaignSection(:final story) => story == null ? 0 : 1,
        NewsroomSection(:final story) => story == null ? 0 : 1,
        // An interaction, not content.
        MoodPulseSection() => 0,
      };
    }
    return count;
  }

  /// How many cards the lead row takes, given [available] products.
  ///
  /// Fill the row, unless filling it would leave a remainder too small to be a
  /// row of its own — in which case split so both rows clear
  /// [minProductsPerRow]. A remainder of zero is not a problem: the closing row
  /// is simply skipped, and View all is where the rest of the catalog lives.
  ///
  /// ```text
  ///  4 products → 4        (one full row, no second — nothing stranded)
  ///  5 products → 3, then 2   (was 4, then a single lonely card)
  ///  6 products → 4, then 2
  ///  9 products → 4, then 4   (the ceiling; the rest is behind View all)
  /// ```
  @visibleForTesting
  static int leadRowSize(int available, [int perRow = productsPerRow]) =>
      _leadRowSize(available, perRow < 1 ? 1 : perRow);

  static int _leadRowSize(int available, int perRow) {
    if (available <= 0) return 0;
    final lead = available < perRow ? available : perRow;
    final rest = available - lead;
    if (rest == 0 || rest >= minProductsPerRow) return lead;
    // The remainder cannot stand alone. Split instead, remainder to the lead.
    final split = (available + 1) ~/ 2;
    return split < perRow ? split : perRow;
  }

  static DiscoverStory? _firstOfType(
    List<DiscoverStory> stories,
    DiscoverStoryType type,
  ) {
    for (final story in stories) {
      if (story.type == type) return story;
    }
    return null;
  }
}
