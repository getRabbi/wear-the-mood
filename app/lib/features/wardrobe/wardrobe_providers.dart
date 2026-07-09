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
  @override
  Future<List<WardrobeItem>> build() {
    return ref.watch(wardrobeRepositoryProvider).getItems();
  }

  /// Re-fetch the closet (after a finished add / enhance, a delete, an edit, or
  /// pull-to-refresh / app resume).
  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(wardrobeRepositoryProvider).getItems(),
    );
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
    AsyncNotifierProvider.autoDispose<WardrobeItemsNotifier, List<WardrobeItem>>(
      WardrobeItemsNotifier.new,
    );

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
