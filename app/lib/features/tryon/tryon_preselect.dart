import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_item.dart';

/// A garment queued for try-on from elsewhere (closet item detail "Try on me",
/// or a future "Try this look"). The Try-On screen consumes and clears it on
/// open so it preselects the piece. Null = nothing queued.
class TryOnPreselect extends Notifier<WardrobeItem?> {
  @override
  WardrobeItem? build() => null;

  void set(WardrobeItem? item) => state = item;

  void clear() => state = null;
}

final tryOnPreselectProvider =
    NotifierProvider<TryOnPreselect, WardrobeItem?>(TryOnPreselect.new);
