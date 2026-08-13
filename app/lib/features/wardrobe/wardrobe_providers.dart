import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_analytics.dart';
import '../../data/models/wardrobe_gap.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/wardrobe_repository.dart';

/// Cost-per-wear + ROI insights (§24). Auto-disposes so it refreshes on reopen;
/// invalidate after a wear is logged.
final wardrobeAnalyticsProvider = FutureProvider.autoDispose<WardrobeAnalytics>(
  (ref) {
    return ref.watch(wardrobeRepositoryProvider).getAnalytics();
  },
);

/// Closet-gap analysis — missing essentials, shoppable (§24).
final wardrobeGapsProvider = FutureProvider.autoDispose<List<WardrobeGap>>((
  ref,
) {
  return ref.watch(wardrobeRepositoryProvider).getGaps();
});

/// The full closet (`GET /v1/wardrobe`). Items only ever land here already
/// FINISHED — background removal + AI enhance run inside a blocking progress
/// sheet in the add flow (see `wardrobe_add_processing.dart`), never as an
/// in-closet "processing" state. That keeps the grid static and flicker-free:
/// this notifier just fetches and can be refreshed after an add / edit / delete.
class WardrobeItemsNotifier extends AsyncNotifier<List<WardrobeItem>> {
  /// False once a page comes back short — there is nothing older to ask for.
  bool _hasMore = true;
  bool _loadingMore = false;

  /// Whether [loadMore] has anything left to fetch.
  bool get hasMore => _hasMore;

  @override
  Future<List<WardrobeItem>> build() async {
    final first = await ref
        .watch(wardrobeRepositoryProvider)
        .getItems(limit: WardrobeRepository.pageSize);
    _hasMore = first.length >= WardrobeRepository.pageSize;
    return first;
  }

  /// Re-fetch the closet (after a finished add / enhance, a delete, an edit, or
  /// pull-to-refresh / app resume).
  ///
  /// Refreshes the FIRST page only and keeps what is already on screen until it
  /// lands, so a refresh never blanks the grid. Anything paged in beyond the
  /// first page is re-earned by scrolling, which is what the user was doing
  /// anyway.
  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final first = await ref
          .read(wardrobeRepositoryProvider)
          .getItems(limit: WardrobeRepository.pageSize);
      _hasMore = first.length >= WardrobeRepository.pageSize;
      return first;
    });
  }

  /// Append the next page.
  ///
  /// Idempotent while in flight and a no-op once the closet is exhausted, so a
  /// scroll listener can call it freely without firing duplicate requests.
  /// Failure is deliberately swallowed: the grid keeps what it has and the next
  /// scroll tries again — losing a page is not worth blanking the closet.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final current = state.asData?.value;
    if (current == null || current.isEmpty) return;
    _loadingMore = true;
    try {
      final next = await ref
          .read(wardrobeRepositoryProvider)
          .getItems(
            limit: WardrobeRepository.pageSize,
            before: current.last.createdAt,
          );
      _hasMore = next.length >= WardrobeRepository.pageSize;
      if (next.isEmpty) return;
      // Dedupe on id: two pieces can share a created_at, and the cursor is
      // time-based, so an overlap is cheaper to tolerate than to prevent.
      final seen = {for (final item in current) item.id};
      final merged = [
        ...current,
        for (final item in next)
          if (seen.add(item.id)) item,
      ];
      if (merged.length != current.length) state = AsyncData(merged);
    } on Object {
      // Keep the page we have; the next scroll retries.
    } finally {
      _loadingMore = false;
    }
  }

  /// Drop a just-deleted item from the in-memory closet so the grid updates
  /// instantly — no slow full refetch round-trip (mobile QA #3). The server
  /// DELETE is the source of truth; call this only after it succeeds.
  void removeItem(String id) {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData([
      for (final item in current)
        if (item.id != id) item,
    ]);
  }
}

final wardrobeItemsProvider =
    AsyncNotifierProvider.autoDispose<
      WardrobeItemsNotifier,
      List<WardrobeItem>
    >(WardrobeItemsNotifier.new);

/// Current closet search query (empty = browse the whole closet). Set on submit.
class WardrobeSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query.trim();
}

final wardrobeSearchQueryProvider =
    NotifierProvider<WardrobeSearchQuery, String>(WardrobeSearchQuery.new);

/// Semantic search results — only fetched while a query is active.
final wardrobeSearchResultsProvider =
    FutureProvider.autoDispose<List<WardrobeItem>>((ref) {
      final query = ref.watch(wardrobeSearchQueryProvider).trim();
      if (query.isEmpty) return Future.value(const []);
      return ref.watch(wardrobeRepositoryProvider).search(query: query);
    });

/// What the wardrobe screen renders. Browsing (no query) mirrors the closet's
/// AsyncValue directly; a query shows semantic search results (§2.1).
final wardrobeViewProvider =
    Provider.autoDispose<AsyncValue<List<WardrobeItem>>>((ref) {
      final query = ref.watch(wardrobeSearchQueryProvider).trim();
      if (query.isEmpty) return ref.watch(wardrobeItemsProvider);
      return ref.watch(wardrobeSearchResultsProvider);
    });
