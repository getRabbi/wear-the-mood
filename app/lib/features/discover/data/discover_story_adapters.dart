import '../../../core/router/routes.dart';
import '../../../data/models/giveaway.dart';
import '../../../data/models/news_item.dart';
import '../../../data/models/offer.dart';
import '../domain/discover_story.dart';

/// Builds Discover Stories out of the content the app already serves.
///
/// Phase 2 deliberately ships NO new tables. The three destination stories —
/// Giveaways, Offers, Newsroom — are adapted from the giveaway, offer and news
/// repositories, which is what the spec's Phase 2 asks for ("use initial
/// adapters for existing Giveaway/Offer/Newsroom content").
///
/// The three personalized stories (Today's Edit, Closet Match, New for You)
/// are intentionally absent. They need the product catalog and the ranking
/// rules that arrive in Phase 3, and inventing them now would mean shipping a
/// card with nothing real behind it — which §6.1 forbids and §26.10 calls out
/// by name. [DiscoverStoryType] already covers them, so Phase 3 adds content,
/// not plumbing.
///
/// Every function here is pure: content in, stories out. No providers, no
/// clock of its own, no I/O — so the eligibility rules are testable directly.
abstract final class DiscoverStoryAdapters {
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
