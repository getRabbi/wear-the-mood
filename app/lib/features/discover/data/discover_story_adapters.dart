import '../../../core/router/routes.dart';
import '../../../data/models/giveaway.dart';
import '../../../data/models/news_item.dart';
import '../../../data/models/offer.dart';
import '../../../data/models/product.dart';
import '../../../data/models/wardrobe_item.dart';
import '../domain/discover_story.dart';

/// Builds Discover Stories out of the content the app already serves.
///
/// No new tables: all six card kinds are adapted from repositories the app
/// already has. Giveaways, Offers and Newsroom come from their own content
/// sources; Today's Edit, Closet Match and New for You are derived from the
/// personalized product feed and the user's wardrobe.
///
/// The personalized three are gated hard on real data — a mood the user
/// actually set, a garment they actually own, products actually ranked for
/// them. Each returns null rather than a card with nothing behind it, because
/// a rail of plausible-looking empty cards is worse than a shorter rail.
///
/// Every function here is pure: content in, stories out. No providers, no
/// clock of its own, no I/O — so the eligibility rules are testable directly.
abstract final class DiscoverStoryAdapters {
  /// `TODAY'S EDIT` — the lead card, built from the mood the user set and the
  /// products ranked under it.
  ///
  /// [moodLabel] is null until the user has actually chosen a mood. There is no
  /// default: naming a mood nobody picked would be the app inventing a
  /// personalization it has not earned.
  static DiscoverStory? dailyEdit(
    List<Product> products, {
    required DateTime now,
    required String category,
    required String? moodLabel,
    required String Function(String mood) title,
    required String Function(int count) subtitle,
    int minProducts = 3,
  }) {
    if (moodLabel == null || moodLabel.trim().isEmpty) return null;
    final ranked = products
        .where((p) => !p.isOutOfStock)
        .toList(growable: false);
    if (ranked.length < minProducts) return null;

    return DiscoverStory(
      id: 'edit-today',
      type: DiscoverStoryType.dailyEdit,
      category: category,
      title: title(moodLabel.trim()),
      subtitle: subtitle(ranked.length),
      imageUrl: ranked.map((p) => p.imageUrl).nonNulls.firstOrNull,
      destination: const DiscoverStoryDestination(
        route: AppRoute.wtmShopSearch,
      ),
      // Moves when the edit itself changes — a different mood or a different
      // set of picks — so yesterday's edit does not stay marked as seen.
      contentVersion: _versionOf([
        moodLabel,
        ...ranked.take(8).map((p) => p.id),
      ]),
      trackingToken: 'story:edit:${ranked.length}',
    );
  }

  /// `CLOSET MATCH` — anchored on something the user owns.
  ///
  /// Needs a garment that can name itself and at least [minMatches] products
  /// from OTHER categories: "your black dress + another black dress" is not a
  /// match, and a card that opened onto that would be worse than no card.
  static DiscoverStory? closetMatch(
    List<WardrobeItem> closet, {
    required List<Product> products,
    required DateTime now,
    required String category,
    required String Function(String garment) title,
    required String Function(int count) subtitle,
    int minMatches = 2,
  }) {
    if (closet.isEmpty || products.isEmpty) return null;

    // The card renders "Your {garment}". A piece carrying neither a title nor a
    // category cannot finish that sentence, so it is passed over rather than
    // rendered nameless.
    WardrobeItem? anchor;
    for (final item in closet) {
      if ((item.title ?? item.category ?? '').trim().isNotEmpty) {
        anchor = item;
        break;
      }
    }
    if (anchor == null) return null;

    final anchorCategory = (anchor.category ?? '').trim().toLowerCase();
    final matches = products
        .where((p) {
          final c = (p.category ?? '').trim().toLowerCase();
          return c.isNotEmpty && c != anchorCategory && !p.isOutOfStock;
        })
        .toList(growable: false);
    if (matches.length < minMatches) return null;

    final garment = (anchor.title ?? anchor.category)!.trim();
    return DiscoverStory(
      id: 'closet-${anchor.id}',
      type: DiscoverStoryType.closetMatch,
      category: category,
      title: title(garment),
      subtitle: subtitle(matches.length),
      // The user's own garment is the artwork — this card is about their
      // wardrobe, so a catalog photo would be the wrong picture entirely.
      imageUrl: anchor.cutoutUrl ?? anchor.imageUrl,
      destination: const DiscoverStoryDestination(route: AppRoute.wtmCloset),
      contentVersion: _versionOf([
        anchor.id,
        ...matches.take(8).map((p) => p.id),
      ]),
      trackingToken: 'story:closet:${matches.length}',
    );
  }

  /// `NEW FOR YOU` — the freshest slice of the personalized feed.
  ///
  /// Honest by construction: these ARE curated picks from the ranked feed, and
  /// the count is the real one. Nothing here claims an arrival date the catalog
  /// did not supply.
  static DiscoverStory? newForYou(
    List<Product> products, {
    required DateTime now,
    required String category,
    required String title,
    required String Function(int count) subtitle,
    int minProducts = 4,
  }) {
    // A genuine new-arrival flag wins where the catalog sets one; otherwise the
    // ranked feed itself is the curation, which is what the copy says.
    final flagged = products
        .where(
          (p) => p.matchReason == MatchReason.newArrival && !p.isOutOfStock,
        )
        .toList(growable: false);
    final pool = flagged.length >= minProducts
        ? flagged
        : products.where((p) => !p.isOutOfStock).toList(growable: false);
    if (pool.length < minProducts) return null;

    return DiscoverStory(
      id: 'new-for-you',
      type: DiscoverStoryType.newForYou,
      category: category,
      title: title,
      subtitle: subtitle(pool.length),
      imageUrl: pool.map((p) => p.imageUrl).nonNulls.firstOrNull,
      destination: const DiscoverStoryDestination(
        route: AppRoute.wtmShopSearch,
      ),
      contentVersion: _versionOf(pool.take(8).map((p) => p.id)),
      trackingToken: 'story:new:${pool.length}',
    );
  }

  /// Copy is passed in rather than read from `AppLocalizations`, because these
  /// are pure functions and every user-facing string still has to come from
  /// l10n at the call site (§34, CLAUDE.md §4.3).
  static DiscoverStory? giveaway(
    List<Giveaway> giveaways, {
    required DateTime now,
    required String category,
    required String title,
    required String Function(int count) subtitle,
    String? liveBadge,
  }) {
    // "Shown only when there is an active or relevant Giveaway" (§6.1).
    // Someone else's listing: your own giveaway is not a discovery.
    final live = giveaways
        .where((g) => g.isAvailable && !g.isMine)
        .toList(growable: false);
    if (live.isEmpty) return null;

    final cover = live.map((g) => g.coverImageUrl).nonNulls.firstOrNull;
    return DiscoverStory(
      id: 'giveaway-hub',
      type: DiscoverStoryType.giveaway,
      category: category,
      title: title,
      subtitle: subtitle(live.length),
      imageUrl: cover,
      badge: liveBadge,
      destination: const DiscoverStoryDestination(route: AppRoute.wtmGiveaways),
      // The rail goes fresh when the pool of live listings changes, not on
      // every refetch — a timestamp-only update is not new content (§33.3).
      contentVersion: _versionOf(live.map((g) => g.id)),
      trackingToken: 'story:giveaway:${live.length}',
    );
  }

  static DiscoverStory? offer(
    List<Offer> offers, {
    required DateTime now,
    required String category,
    required String fallbackTitle,
    String? priceDropBadge,
  }) {
    // "Shown only when there is a valid active offer" (§6.1). An offer with no
    // destination is not something to send a user at.
    final live = offers
        .where((o) => o.affiliateUrl.trim().isNotEmpty)
        .toList(growable: false);
    if (live.isEmpty) return null;

    final lead = live.first;
    return DiscoverStory(
      id: 'offer-hub',
      type: DiscoverStoryType.offer,
      category: category,
      // The lead offer's own title where it has one — real copy beats a
      // generic header, and the discount is REAL (never invented, §26.10).
      title: lead.title.trim().isEmpty ? fallbackTitle : lead.title.trim(),
      subtitle: lead.brand,
      imageUrl: live.map((o) => o.imageUrl).nonNulls.firstOrNull,
      badge: lead.discountLabel?.trim().isNotEmpty == true
          ? lead.discountLabel
          : priceDropBadge,
      destination: const DiscoverStoryDestination(route: AppRoute.wtmOffers),
      contentVersion: _versionOf(live.map((o) => o.id)),
      trackingToken: 'story:offer:${lead.id}',
    );
  }

  static DiscoverStory? newsroom(
    List<NewsItem> items, {
    required DateTime now,
    required String category,
    required String Function(String source) subtitle,
    String? newBadge,
    Duration freshWindow = const Duration(days: 3),
  }) {
    // "Shown when there is a new or relevant story" (§6.1).
    final live = items
        .where((n) => n.title.trim().isNotEmpty)
        .toList(growable: false);
    if (live.isEmpty) return null;

    final lead = live.first;
    final published = lead.publishedAt ?? lead.createdAt;
    final isFresh = now.difference(published) <= freshWindow;
    return DiscoverStory(
      id: 'newsroom-hub',
      type: DiscoverStoryType.newsroom,
      category: category,
      title: lead.title.trim(),
      subtitle: lead.source == null ? null : subtitle(lead.source!),
      imageUrl: live.map((n) => n.imageUrl).nonNulls.firstOrNull,
      // The badge is earned by an actually recent article, not stamped on
      // whatever happens to be at the top of the feed.
      badge: isFresh ? newBadge : null,
      destination: const DiscoverStoryDestination(route: AppRoute.wtmNewsroom),
      contentVersion: _versionOf(live.map((n) => n.id)),
      trackingToken: 'story:newsroom:${lead.id}',
    );
  }

  /// A content version derived from WHICH items are present, so it moves when
  /// the set changes and holds steady when the same items come back in a new
  /// response. Order-insensitive, because the server is free to reorder.
  ///
  /// Folded to a positive int: the value is only ever compared for equality
  /// and ordering against a previously stored one.
  static int _versionOf(Iterable<String> ids) {
    final sorted = ids.toList()..sort();
    var hash = 17;
    for (final id in sorted) {
      hash = 0x1fffffff & (hash * 31 + id.hashCode);
    }
    return hash;
  }
}
