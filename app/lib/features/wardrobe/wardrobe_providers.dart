import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_analytics.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/wardrobe_repository.dart';

/// Cost-per-wear + ROI insights (§24). Auto-disposes so it refreshes on reopen;
/// invalidate after a wear is logged.
final wardrobeAnalyticsProvider = FutureProvider.autoDispose<WardrobeAnalytics>(
  (ref) {
    return ref.watch(wardrobeRepositoryProvider).getAnalytics();
  },
);

/// The full closet, from `GET /v1/wardrobe`. Auto-disposes so it refetches when
/// the tab re-opens; invalidate after a mutation (e.g. delete) to refresh.
final wardrobeItemsProvider = FutureProvider.autoDispose<List<WardrobeItem>>((
  ref,
) async {
  return ref.watch(wardrobeRepositoryProvider).getItems();
});

/// Current closet search query (empty = browse the whole closet). Set on submit.
class WardrobeSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query.trim();
}

final wardrobeSearchQueryProvider =
    NotifierProvider<WardrobeSearchQuery, String>(WardrobeSearchQuery.new);

/// What the wardrobe screen renders: the full closet when the query is empty,
/// otherwise semantic search results (§2.1).
final wardrobeViewProvider = FutureProvider.autoDispose<List<WardrobeItem>>((
  ref,
) async {
  final query = ref.watch(wardrobeSearchQueryProvider).trim();
  if (query.isEmpty) {
    return ref.watch(wardrobeItemsProvider.future);
  }
  return ref.watch(wardrobeRepositoryProvider).search(query: query);
});
