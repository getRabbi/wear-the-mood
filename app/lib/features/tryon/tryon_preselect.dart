import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_item.dart';
import 'models/studio_models.dart';

/// Pieces queued for the Try-On Studio from elsewhere — a closet item
/// ("Try on me") or a community post's outfit ("Try this look"). The studio
/// consumes and clears it on open, seeding the outfit stack. Null = nothing
/// queued.
class TryOnPreselect extends Notifier<List<TryOnLayer>?> {
  @override
  List<TryOnLayer>? build() => null;

  /// Seed from a single owned closet item (prefers its cutout).
  void setItem(WardrobeItem item) {
    final url = item.cutoutUrl ?? item.imageUrl;
    if (url == null || url.isEmpty) return;
    state = [
      TryOnLayer.fromSource(
        imageUrl: url,
        category: item.category,
        wardrobeItemId: item.id,
      ),
    ];
  }

  /// Seed from several owned closet items at once — the Outfit Builder's
  /// "Try on full look" stacks the whole set (prefers each piece's cutout).
  void setItems(List<WardrobeItem> items) {
    final layers = <TryOnLayer>[];
    for (final item in items) {
      final url = item.cutoutUrl ?? item.imageUrl;
      if (url == null || url.isEmpty) continue;
      layers.add(
        TryOnLayer.fromSource(
          imageUrl: url,
          category: item.category,
          wardrobeItemId: item.id,
          zIndex: layers.length,
        ),
      );
    }
    if (layers.isNotEmpty) state = layers;
  }

  /// Seed from external images (e.g. a community post's look). These are
  /// reference layers — no wardrobe id.
  void setImages(List<String> urls) {
    final clean = [for (final u in urls) if (u.isNotEmpty) u];
    if (clean.isEmpty) return;
    state = [
      for (var i = 0; i < clean.length; i++)
        TryOnLayer.fromSource(imageUrl: clean[i], zIndex: i),
    ];
  }

  void clear() => state = null;
}

final tryOnPreselectProvider =
    NotifierProvider<TryOnPreselect, List<TryOnLayer>?>(TryOnPreselect.new);
