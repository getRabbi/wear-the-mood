import 'dart:async';

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

/// The full closet, from `GET /v1/wardrobe`. Auto-disposes so it refetches when
/// the tab re-opens; invalidate after a mutation (e.g. delete) to refresh.
///
/// Cutouts are generated server-side (§2.2), so a freshly added item lands as
/// `processing`. While any item is still processing we re-poll every few seconds
/// and stop once all are done — so the grid updates from the processing badge to
/// the finished cutout on its own, without a manual pull-to-refresh.
final wardrobeItemsProvider = FutureProvider.autoDispose<List<WardrobeItem>>((
  ref,
) async {
  final items = await ref.watch(wardrobeRepositoryProvider).getItems();
  if (items.any((i) => i.isProcessingCutout)) {
    final timer = Timer(const Duration(seconds: 4), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return items;
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
