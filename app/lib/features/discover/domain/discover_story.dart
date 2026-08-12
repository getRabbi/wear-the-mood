import 'package:flutter/foundation.dart';

/// The six Discover Story kinds (DISCOVER spec §6.1).
///
/// The first three are personalized and arrive with the catalog in Phase 3;
/// the last three are content destinations and are what Phase 2 actually
/// builds, adapted from the giveaway / offer / news repositories the app
/// already has.
///
/// [rank] fixes the rail order — Today's Edit is always first when it exists —
/// and is a property of the TYPE, not of anything a server sends as display
/// text. Nothing in the UI may infer a story's kind from its title (§16).
enum DiscoverStoryType {
  dailyEdit(rank: 0),
  closetMatch(rank: 1),
  newForYou(rank: 2),
  giveaway(rank: 3),
  offer(rank: 4),
  newsroom(rank: 5);

  const DiscoverStoryType({required this.rank});

  final int rank;

  /// Wire name. Kept as a string at the boundary so a kind introduced by a
  /// newer backend is unknown DATA, not a parse failure (§37.4).
  String get wireName => name;

  static DiscoverStoryType? fromWire(String? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return null; // unknown → caller skips it, never renders a blank card
  }
}

/// Where a story's primary action goes. An in-app route only — a story can
/// never point the router at a scheme or a host (§38, and the same rule
/// `isValidPushRoute` already enforces for pushes).
@immutable
class DiscoverStoryDestination {
  const DiscoverStoryDestination({required this.route, this.label});

  /// An absolute in-app route, e.g. `/wtm/giveaways`.
  final String route;

  /// Optional CTA override. Null → the viewer uses the type's default (§7.3).
  final String? label;

  /// Rejects anything that is not a plain in-app path.
  bool get isSafe =>
      route.startsWith('/') &&
      !route.startsWith('//') &&
      !route.contains('://');

  @override
  bool operator ==(Object other) =>
      other is DiscoverStoryDestination &&
      other.route == route &&
      other.label == label;

  @override
  int get hashCode => Object.hash(route, label);
}

/// One card in the Discover Stories rail (§6, §16).
///
/// Everything needed to render, rank, track and open a card lives here, so the
/// rail and the viewer never reach back into a repository or re-derive meaning
/// from copy.
@immutable
class DiscoverStory {
  const DiscoverStory({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.destination,
    this.subtitle,
    this.imageUrl,
    this.badge,
    this.contentVersion = 1,
    this.expiresAt,
    this.trackingToken,
    this.ordinal = 0,
  });

  /// Stable across refreshes for the same underlying content — the seen state
  /// is keyed on it, so a churning id would make a story permanently unseen.
  final String id;
  final DiscoverStoryType type;

  /// Small uppercase label on the card, e.g. `GIVEAWAY` (§6.3).
  final String category;

  /// Card title, rendered to a maximum of two lines (§6.3, §25).
  final String title;

  /// Optional one-line supporting text.
  final String? subtitle;

  /// Editorial image. Null is fine and common — the card falls back to its
  /// type's gradient artwork rather than showing a hole (§6.3).
  final String? imageUrl;

  /// At most ONE badge (`NEW` / `LIVE` / `PRICE DROP`) — never a stack (§26.11).
  final String? badge;

  final DiscoverStoryDestination destination;

  /// Bumped when the content meaningfully changes. A story goes fresh again
  /// only on a version move, never on a timestamp-only update (§6.4, §33.3).
  final int contentVersion;

  /// When set and in the past the story is ineligible (§19.1).
  final DateTime? expiresAt;

  /// Opaque analytics correlation id. Never a URL and never anything private.
  final String? trackingToken;

  /// Where this card sits among others of its OWN type.
  ///
  /// A source that has several real things to say — three live giveaways, four
  /// recent reads — contributes one card each, and this is what keeps them in
  /// the order the source meant rather than in id order, which for a UUID is
  /// arbitrary. Zero for the single-card kinds.
  final int ordinal;

  /// Rail ordering: by type rank, then by the source's own order within a type,
  /// then by id so a tie is stable across rebuilds. Session-stable ordering is
  /// a hard requirement (§33.2), and all three keys are properties of the
  /// content rather than of when it happened to load.
  static int compare(DiscoverStory a, DiscoverStory b) {
    final byRank = a.type.rank.compareTo(b.type.rank);
    if (byRank != 0) return byRank;
    final byOrdinal = a.ordinal.compareTo(b.ordinal);
    return byOrdinal != 0 ? byOrdinal : a.id.compareTo(b.id);
  }

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !now.isBefore(expiresAt!);

  /// A story is eligible when it has content to show, a safe destination, and
  /// has not expired. Anything failing this is dropped rather than rendered as
  /// an empty placeholder (§6.1 "do not render empty placeholder cards").
  bool isEligibleAt(DateTime now) =>
      id.isNotEmpty &&
      title.trim().isNotEmpty &&
      destination.isSafe &&
      !isExpiredAt(now);

  /// Whether [seenVersions] already covers this story at its current version.
  bool isSeenIn(Map<String, int> seenVersions) {
    final seen = seenVersions[id];
    return seen != null && seen >= contentVersion;
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoverStory &&
      other.id == id &&
      other.type == type &&
      other.category == category &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.imageUrl == imageUrl &&
      other.badge == badge &&
      other.destination == destination &&
      other.contentVersion == contentVersion &&
      other.expiresAt == expiresAt &&
      other.trackingToken == trackingToken &&
      other.ordinal == ordinal;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    category,
    title,
    subtitle,
    imageUrl,
    badge,
    destination,
    contentVersion,
    expiresAt,
    trackingToken,
    ordinal,
  );
}

/// Rail composition rules (§6.1).
abstract final class DiscoverRail {
  /// Hard ceiling on cards.
  static const maxCards = 6;

  /// Below this the rail is not worth its own row; the caller shows a compact
  /// fallback card instead of an awkward one-card scroller.
  static const minCards = 2;

  /// What a healthy candidate POOL looks like before the rail takes its six.
  ///
  /// Not a target for what is drawn — that is [maxCards] — but for what the
  /// adapters are asked to produce. The rail used to collapse to two cards on a
  /// perfectly stocked account because every adapter answered with exactly one
  /// card: no mood set and an empty closet removed three of the six outright,
  /// and a giveaway pool that was all the user's own listings removed a fourth,
  /// leaving `NEW FOR YOU` and a read. Sources that genuinely have several
  /// things to offer now offer several, so a missing kind is backfilled by a
  /// present one instead of leaving a hole.
  ///
  /// It is a target, never a quota: nothing is invented or repeated to reach it
  /// (§26.10). An account with three real candidates gets three.
  static const targetPool = 10;

  /// Filters to eligible stories, de-duplicates by id, orders by
  /// [DiscoverStory.compare] and caps at [maxCards].
  ///
  /// Returns whatever survives — including a list shorter than [minCards].
  /// Deciding between a rail and the compact fallback is the UI's call; this
  /// stays a pure function so it is testable without a widget.
  static List<DiscoverStory> compose(
    Iterable<DiscoverStory> candidates, {
    required DateTime now,
  }) => _eligible(candidates, now: now).take(maxCards).toList(growable: false);

  /// Every eligible candidate, ordered and de-duplicated, with NO cap.
  ///
  /// This is the pool [targetPool] talks about. The rail shows the first
  /// [maxCards]; the viewer pages through the whole thing, which is where the
  /// extra real content earns its keep rather than being thrown away.
  static List<DiscoverStory> pool(
    Iterable<DiscoverStory> candidates, {
    required DateTime now,
  }) => _eligible(candidates, now: now);

  static List<DiscoverStory> _eligible(
    Iterable<DiscoverStory> candidates, {
    required DateTime now,
  }) {
    final byId = <String, DiscoverStory>{};
    for (final story in candidates) {
      if (!story.isEligibleAt(now)) continue;
      // First writer wins: adapters are consulted in priority order, so an
      // earlier, better-ranked card should not be replaced by a later duplicate.
      byId.putIfAbsent(story.id, () => story);
    }
    return byId.values.toList()..sort(DiscoverStory.compare);
  }
}
