import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/outfit.dart';
import '../../data/repositories/outfit_repository.dart';

/// The user's saved outfits, from `GET /v1/outfits`. Auto-disposes so the list
/// refetches when the screen re-opens; invalidate after a create/delete.
final outfitsProvider = FutureProvider.autoDispose<List<Outfit>>((ref) async {
  return ref.watch(outfitRepositoryProvider).getOutfits();
});
