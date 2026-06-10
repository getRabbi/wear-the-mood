import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/wardrobe_repository.dart';

/// The user's wardrobe, fetched from `GET /v1/wardrobe`. Auto-disposes so the
/// closet refetches when the tab re-opens, and the screen wires all four states
/// (§4.3). Invalidate after a mutation (e.g. delete) to refresh.
final wardrobeItemsProvider = FutureProvider.autoDispose<List<WardrobeItem>>((
  ref,
) async {
  return ref.watch(wardrobeRepositoryProvider).getItems();
});
