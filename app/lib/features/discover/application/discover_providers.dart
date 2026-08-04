import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/giveaway.dart';
import '../../../data/models/news_item.dart';
import '../../../data/models/offer.dart';
import '../../../data/repositories/giveaway_repository.dart';
import '../../../data/repositories/offers_repository.dart';
import '../../news/news_providers.dart';
import '../data/discover_local_store.dart';
import '../domain/discover_story.dart';

/// The content the Phase 2 Stories rail is adapted from, plus which sources
/// failed to load.
///
/// Sources are kept SEPARATE rather than merged into one success/failure,
/// because a rail with two of three cards is a working rail. §24 requires the
/// rail stays usable when a story fails to load, so one dead endpoint must not
/// take the surface down with it.
@immutable
class DiscoverContent {
  const DiscoverContent({
    this.giveaways = const [],
    this.offers = const [],
    this.news = const [],
    this.failedSources = 0,
    this.totalSources = 3,
  });

  final List<Giveaway> giveaways;
  final List<Offer> offers;
  final List<NewsItem> news;

  /// How many of the content sources errored on this load.
  final int failedSources;
  final int totalSources;

  /// Every source failed — there is nothing to show and nothing to partially
  /// recover, so the screen shows its error face with a retry rather than a
  /// convincing-looking empty state (§24).
  bool get isTotalFailure => failedSources >= totalSources;

  /// Some content arrived and some did not. The rail renders what it has; the
  /// caller may surface a non-blocking note (§33.4).
  bool get isPartial => failedSources > 0 && !isTotalFailure;

  bool get isEmpty => giveaways.isEmpty && offers.isEmpty && news.isEmpty;
}

/// Loads all three Discover content sources concurrently, tolerating the
/// failure of any subset.
///
/// The three futures are created up front — before the first `await` — so the
/// requests overlap and so every `ref.watch` runs synchronously during build,
/// which is what keeps this provider correctly subscribed to its dependencies.
final discoverContentProvider = FutureProvider<DiscoverContent>((ref) async {
  final giveawaysFuture = ref.watch(giveawayBrowseProvider.future);
  final offersFuture = ref.watch(offersProvider.future);
  final newsFuture = ref.watch(newsProvider.future);

  var failed = 0;
  Future<List<T>> tolerate<T>(Future<List<T>> future, String source) async {
    try {
      return await future;
    } catch (error) {
      failed++;
      assert(() {
        debugPrint('[Discover] $source unavailable: $error');
        return true;
      }());
      return const [];
    }
  }

  final giveaways = await tolerate(giveawaysFuture, 'giveaways');
  final offers = await tolerate(offersFuture, 'offers');
  final news = await tolerate(newsFuture, 'news');

  return DiscoverContent(
    giveaways: giveaways,
    offers: offers,
    news: news,
    failedSources: failed,
  );
});

/// Story ids the user has already seen, mapped to the version they saw.
///
/// Read once per session from [DiscoverLocalStore] and then kept in memory, so
/// the rail's seen rings do not flicker on every rebuild. Marking a story seen
/// updates both.
final discoverSeenStoriesProvider =
    AsyncNotifierProvider<DiscoverSeenStories, Map<String, int>>(
      DiscoverSeenStories.new,
    );

class DiscoverSeenStories extends AsyncNotifier<Map<String, int>> {
  @override
  Future<Map<String, int>> build() =>
      ref.watch(discoverLocalStoreProvider).seenStoryVersions();

  /// Records [story] as seen at its current version.
  ///
  /// Call this only once the viewer's content has actually loaded — a failed
  /// load must never mark a story seen (§6.5, §24).
  Future<void> markSeen(DiscoverStory story) async {
    final current = state.asData?.value ?? const <String, int>{};
    // Already covered — no write, no rebuild.
    if (story.isSeenIn(current)) return;
    // Optimistic: the ring should dim the instant the viewer opens, not after
    // a disk round-trip. The store is best-effort anyway, so a failed write
    // simply means the ring re-lights next launch.
    state = AsyncData({...current, story.id: story.contentVersion});
    await ref
        .read(discoverLocalStoreProvider)
        .markStorySeen(story.id, story.contentVersion);
  }
}

/// Story ids whose impression has already been counted this session.
///
/// Session-scoped by construction: the provider holds it in memory and it dies
/// with the app, which is exactly the "deduplicate once per item per session"
/// rule. Never persisted — a fresh launch is a fresh session (§22).
final discoverImpressionsProvider =
    NotifierProvider<DiscoverImpressions, Set<String>>(DiscoverImpressions.new);

class DiscoverImpressions extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Marks [key] counted. Returns false when it was already counted, so the
  /// caller can skip the analytics call entirely.
  bool register(String key) {
    if (state.contains(key)) return false;
    state = {...state, key};
    return true;
  }
}
