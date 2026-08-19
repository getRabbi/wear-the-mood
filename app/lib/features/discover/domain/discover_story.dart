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
  ///
  /// Note what this deliberately does NOT require: a picture. An article whose
  /// publisher exposes no image is still a perfectly good story and still
  /// belongs in the Newsroom. What it does not belong in is a full-bleed
  /// editorial card — see [isImageReady].
  bool isEligibleAt(DateTime now) =>
      id.isNotEmpty &&
      title.trim().isNotEmpty &&
      destination.isSafe &&
      !isExpiredAt(now);

  /// Eligible for an IMAGE-REQUIRED placement — the Discover feature card, the
  /// "A quick read" slot, a hero.
  ///
  /// Separate from [isEligibleAt] on purpose. Conflating the two is how the
  /// Newsroom card came to lead with whichever article happened to rank first
  /// even when its publisher had given us no picture, so a premium full-width
  /// slot rendered the gradient placeholder next to a rail of photographs.
  /// Eligibility to EXIST and eligibility to be the PICTURE are different
  /// questions.
  bool get isImageReady => (imageUrl ?? '').trim().isNotEmpty;

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
  ///
  /// Raised from six: at six the rail hit its cap while real editorial was still
  /// queued behind it, so a stocked account saw three news cards and no more —
  /// the ceiling, not the content, was the limit. Twelve leaves room for the
  /// round-robin to seat every source AND several articles.
  ///
  /// Still a ceiling and never a quota (§26.10): nothing is invented or repeated
  /// to reach it, so an account with four real candidates still gets four.
  static const maxCards = 12;

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
  static const targetPool = 16;

  /// Filters to eligible stories, de-duplicates by id, orders by
  /// [DiscoverStory.compare] and selects at most [maxCards] via [select].
  ///
  /// Returns whatever survives — including a list shorter than [minCards].
  /// Deciding between a rail and the compact fallback is the UI's call; this
  /// stays a pure function so it is testable without a widget.
  static List<DiscoverStory> compose(
    Iterable<DiscoverStory> candidates, {
    required DateTime now,
    Map<DiscoverStoryType, int> caps = const {},
  }) => select(_eligible(candidates, now: now), caps: caps);

  /// Chooses the VISIBLE rail out of an already-eligible, already-ordered
  /// [pool].
  ///
  /// Round-robin across kinds: every source with something to say gets its
  /// first card before any source gets its second, and so on. That single rule
  /// is what stops one table owning the surface.
  ///
  /// It replaces "take the first six in rank order", which was a bug the moment
  /// a source was allowed to contribute more than one card. Giveaways rank
  /// above the newsroom, so three live giveaways plus two offers filled five of
  /// the six slots and the sixth went to the third giveaway — an editorial
  /// surface with no editorial on it, on an account with a full news feed. The
  /// pool has not changed and neither has the ceiling; only which six are
  /// drawn.
  ///
  /// [caps] is a per-kind ceiling for the rail, on top of the fairness the
  /// round-robin already provides. It exists for the one kind the product caps
  /// deliberately (giveaways), and it is a ceiling over real items — nothing is
  /// invented to reach it.
  ///
  /// Deterministic: [pool] order decides everything, so re-entering Discover
  /// with the same content draws the same rail (§33.2).
  static List<DiscoverStory> select(
    List<DiscoverStory> pool, {
    int max = maxCards,
    Map<DiscoverStoryType, int> caps = const {},
  }) {
    if (max <= 0 || pool.isEmpty) return const [];

    final byKind = <DiscoverStoryType, List<DiscoverStory>>{};
    for (final story in pool) {
      (byKind[story.type] ??= <DiscoverStory>[]).add(story);
    }
    // Rank order, so a round always offers Today's Edit before a giveaway. The
    // pool is already sorted this way; sorting the keys keeps that true even if
    // a caller hands over something assembled differently.
    final kinds = byKind.keys.toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));

    final picked = <DiscoverStory>[];
    for (var round = 0; picked.length < max; round++) {
      var placed = false;
      for (final kind in kinds) {
        if (picked.length >= max) break;
        final cap = caps[kind];
        if (cap != null && round >= cap) continue;
        final cards = byKind[kind]!;
        if (round >= cards.length) continue;
        picked.add(cards[round]);
        placed = true;
      }
      // Every kind is exhausted or capped — the rail is as long as the content
      // honestly allows, which is shorter than the ceiling and correct.
      if (!placed) break;
    }
    return List.unmodifiable(picked);
  }

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
