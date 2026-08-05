import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/product.dart';
import '../../../data/repositories/discover_repository.dart';

/// Saved products, newest first (DISCOVER §11.3).
///
/// The server deliberately does NOT filter this list to currently-servable
/// products: something that sold out, or whose offer ended, has to show its
/// state rather than vanish without explanation.
final savedProductsProvider = FutureProvider.autoDispose<List<SavedProduct>>((
  ref,
) {
  return ref.watch(discoverRepositoryProvider).saved();
});

/// The single place a product is saved or unsaved, and the single answer to
/// "is this saved?" across every surface (§11.3, §31 "Save works").
///
/// This exists because the same product is on screen in more than one place at
/// once. Save from Product Details and the heart in the feed behind it has to
/// agree when the user comes back; unsave from the Saved screen and the feed
/// has to agree too. The obvious fix — reload the feed — is the one thing that
/// is not allowed: rebuilding page 1 would throw away the user's scroll
/// position and every page after it, which §33.2 forbids by name.
///
/// So the state here is an OVERRIDE LAYER, not a copy of the catalog: product
/// id → the value this session set. A product with no entry reports whatever
/// the server said. Overrides are dropped when a fresh page re-states the
/// truth for those ids, so this can never drift into contradicting the server
/// indefinitely.
final savedOverridesProvider =
    NotifierProvider<SavedOverrides, Map<String, bool>>(SavedOverrides.new);

/// Whether [product] is saved, and rebuilds when that changes.
///
/// Deliberately watches the MAP, not the notifier. `ref.watch(p.notifier)`
/// subscribes to the notifier instance being replaced, which never happens
/// here — so a heart built from it would go stale the moment another surface
/// changed the value, which is the whole thing this layer exists to prevent.
bool watchSaved(WidgetRef ref, Product product) =>
    ref.watch(savedOverridesProvider)[product.id] ?? product.saved;

class SavedOverrides extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  /// Whether [product] is saved, honouring anything this session changed.
  ///
  /// For a one-off read. Widgets that display the value want [watchSaved].
  bool isSaved(Product product) => state[product.id] ?? product.saved;

  /// Drops overrides for ids the server has just re-stated.
  ///
  /// A fresh page is authoritative — it already reflects every save this
  /// session made — so keeping the local value on top of it would only
  /// preserve a disagreement if one ever arose (a save from another device,
  /// say). Cheap, and it keeps the override layer honest.
  void reconcile(Iterable<String> serverKnownIds) {
    if (state.isEmpty) return;
    final ids = serverKnownIds.toSet();
    final next = {
      for (final entry in state.entries)
        if (!ids.contains(entry.key)) entry.key: entry.value,
    };
    if (next.length != state.length) state = next;
  }

  void _write(String productId, bool saved) {
    state = {...state, productId: saved};
  }

  /// Toggles [product] and persists it. Returns the new saved value.
  ///
  /// Optimistic, because a heart that waits on a round trip feels broken; the
  /// override is put back on failure rather than leaving the UI lying about
  /// what is stored.
  Future<bool> toggle(Product product) async {
    final next = !isSaved(product);
    _write(product.id, next);
    try {
      final repo = ref.read(discoverRepositoryProvider);
      if (next) {
        await repo.save(product.id);
      } else {
        await repo.unsave(product.id);
      }
      // The Saved screen is a server list, so it has to be re-read rather than
      // patched — but only after the write actually landed.
      ref.invalidate(savedProductsProvider);
      return next;
    } catch (error) {
      _write(product.id, !next);
      assert(() {
        debugPrint('[Discover] save failed: $error');
        return true;
      }());
      rethrow;
    }
  }
}
