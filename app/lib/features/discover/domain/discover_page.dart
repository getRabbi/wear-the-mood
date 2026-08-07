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

/// Which curated product row this is.
///
/// The slot is a TYPE, never display text: the renderer maps it to a heading
/// from l10n, and nothing downstream reads a row's meaning out of its copy.
///
/// Order here is the order rows are handed out, and every slot is used AT MOST
/// ONCE per page — which is precisely what stops "Keep exploring" from
/// appearing four times down the same scroll.
enum DiscoverRowSlot {
  /// The lead curated row, under the interaction card.
  pickedForYou,

  /// The approved layout's closing row, after the editorial modules.
  newForYourMood,

  // Everything below is reached only by pagination. The copy is deliberately
  // about POSITION in the feed rather than a filter — "in your colours" would
  // promise a narrowing the ranking does not actually do.
  moreToExplore,
  furtherAfield,
  stillWorthALook,
  oneMoreEdit,
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

  /// How many curated rows were emitted. When this reaches the number of
  /// available slots the page has no heading left to give a further row, and
  /// asking the server for another page would fetch products nothing can draw.
  final int rowsRendered;

  /// Whether another page of products could still be placed.
  bool get canPaginate => rowsRendered < DiscoverRowSlot.values.length;
}

/// Builds the approved Discover layout.
///
/// The visible order is fixed here and nowhere else:
///
/// ```text
/// story rail → interaction → Picked for You → Complete Your Look
///            → Giveaway|Offer → Newsroom → New for Your Mood → (pagination)
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

  /// Suggestions beside the owned garment in Complete Your Look.
  static const lookSuggestions = 3;

  /// Composes the initial page plus any rows pagination has earned.
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

    // ---- 1. Story rail ------------------------------------------------
    //
    // Below `minCards` a rail is a one-card scroller, which reads as a broken
    // carousel, so the screen shows a compact fallback card for the single
    // story instead.
    final hasRail = storiesEnabled && stories.length >= DiscoverRail.minCards;
    if (hasRail) sections.add(StoryRailSection(stories));

    // A full rail card is a glance and the feed card is the editorial pitch, so
    // the approved layout carries both — that is what the prototype shows.
    final modules = stories;

    // When the rail collapsed, the compact card is the ONLY place that story
    // would appear — unless an editorial slot below is about to show it, which
    // it now always does for a campaign or a read. Handing it to that card and
    // dropping the compact one keeps the content in the richer of the two
    // places without ever showing it twice (caught on device with only a
    // Newsroom item live).
    final DiscoverStory? fallback;
    if (hasRail || stories.isEmpty) {
      fallback = null;
    } else {
      final only = stories.first;
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
    bool addRow({bool requireSeparator = false}) {
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
      final take = unused().take(perRow).toList(growable: false);
      if (take.isEmpty) return false;
      usedProducts.addAll(take.map((p) => p.id));
      sections.add(
        ProductRowSection(slot: DiscoverRowSlot.values[rows], products: take),
      );
      rows++;
      return true;
    }

    // ---- 3. Picked for You --------------------------------------------
    addRow();

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
      sections.add(
        CampaignSection(
          _firstOfType(modules, DiscoverStoryType.giveaway) ??
              _firstOfType(modules, DiscoverStoryType.offer),
        ),
      );

      // ---- 6. One Newsroom card ----------------------------------------
      sections.add(
        NewsroomSection(_firstOfType(modules, DiscoverStoryType.newsroom)),
      );
    }

    // ---- 7. The closing curated row -------------------------------------
    //
    // Separated: on a page where no module was available — an empty closet, no
    // live campaign, no article — this row is skipped rather than stacked
    // straight onto the lead row. The products are not lost; they arrive as
    // pagination once the user has actually scrolled for them.
    addRow(requireSeparator: true);

    // ---- 8. Pagination ---------------------------------------------------
    //
    // Only ever reached once the mixed modules above are placed. Each further
    // row takes the next unused slot, so it arrives with a heading of its own;
    // when the slots run out the page stops rather than repeating one.
    while (addRow()) {}

    return DiscoverPageLayout(
      sections: List.unmodifiable(sections),
      usedProductIds: Set.unmodifiable(usedProducts),
      rowsRendered: rows,
      fallbackStory: fallback,
    );
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
