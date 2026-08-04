import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/product.dart';
import '../../../data/repositories/discover_repository.dart';
import '../domain/product_filters.dart';

/// The paginated "Picked for You" feed (DISCOVER §8, §23, §33.2).
@immutable
class ProductFeedState {
  const ProductFeedState({
    this.items = const [],
    this.cursor,
    this.loadingMore = false,
    this.regionEmpty = false,
    this.loadMoreFailed = false,
  });

  final List<Product> items;

  /// Position of the next page, or null when the feed is exhausted.
  final String? cursor;
  final bool loadingMore;

  /// The region has no catalog at all, as opposed to nothing matching the
  /// current filters — a different empty state (§24).
  final bool regionEmpty;

  /// The last "load more" failed. Kept separate from the screen's error state:
  /// a failed page-2 must not blank out a page-1 the user is reading (§24).
  final bool loadMoreFailed;

  bool get hasMore => (cursor ?? '').isNotEmpty;
  bool get isEmpty => items.isEmpty;

  ProductFeedState copyWith({
    List<Product>? items,
    String? cursor,
    bool clearCursor = false,
    bool? loadingMore,
    bool? regionEmpty,
    bool? loadMoreFailed,
  }) => ProductFeedState(
    items: items ?? this.items,
    cursor: clearCursor ? null : (cursor ?? this.cursor),
    loadingMore: loadingMore ?? this.loadingMore,
    regionEmpty: regionEmpty ?? this.regionEmpty,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
}

/// The active filter/search state. Changing it restarts the feed; it is kept
/// separate from the feed itself so returning from a product does NOT reset it
/// (§11.2 "persist the active filter/search state").
final productFiltersProvider =
    NotifierProvider<ProductFiltersNotifier, ProductFilters>(
      ProductFiltersNotifier.new,
    );

class ProductFiltersNotifier extends Notifier<ProductFilters> {
  @override
  ProductFilters build() => const ProductFilters();

  void apply(ProductFilters filters) => state = filters;

  /// A new explicit search starts from clean filters rather than silently
  /// carrying the previous ones (§11.2).
  void search(String? query) => state = ProductFilters(
    query: (query ?? '').trim().isEmpty ? null : query,
  );

  void reset() => state = const ProductFilters();
}

/// The feed itself, rebuilt whenever the filters change.
///
/// Session-stable by construction: pages are APPENDED and never re-sorted, and
/// the server's keyset cursor guarantees the next page starts strictly after
/// the last row already shown. The list a user has scrolled through cannot
/// reshuffle underneath them, and pagination cannot produce a duplicate — the
/// two failures §23 and §33.2 call out by name.
final productFeedProvider =
    AsyncNotifierProvider<ProductFeed, ProductFeedState>(ProductFeed.new);

class ProductFeed extends AsyncNotifier<ProductFeedState> {
  CancelToken? _inFlight;

  @override
  Future<ProductFeedState> build() async {
    final filters = ref.watch(productFiltersProvider);

    // A superseded request must never land on top of a newer one. Filters
    // changing while page 1 is in flight would otherwise show the OLD results
    // for the NEW filters (§23 "cancel stale requests").
    _inFlight?.cancel('filters changed');
    final token = CancelToken();
    _inFlight = token;
    ref.onDispose(() => token.cancel('disposed'));

    final page = await ref
        .read(discoverRepositoryProvider)
        .products(
          country: filters.country,
          currency: filters.currency,
          category: filters.category,
          subcategory: filters.subcategory,
          audience: filters.audience,
          colors: filters.colors,
          sizes: filters.sizes,
          brands: filters.brands,
          minPriceMinor: filters.minPriceMinor,
          maxPriceMinor: filters.maxPriceMinor,
          tryOnReady: filters.tryOnReady,
          discounted: filters.discounted,
          query: filters.query,
          cancelToken: token,
        );

    return ProductFeedState(
      items: page.items,
      cursor: page.nextCursor,
      regionEmpty: page.regionEmpty,
    );
  }

  /// Fetches the next page and appends it.
  ///
  /// Safe to call repeatedly from a scroll listener: it is a no-op while a
  /// page is already in flight, when the feed is exhausted, or before the
  /// first page has arrived.
  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || current.loadingMore || !current.hasMore) return;

    state = AsyncData(
      current.copyWith(loadingMore: true, loadMoreFailed: false),
    );
    try {
      final filters = ref.read(productFiltersProvider);
      final page = await ref
          .read(discoverRepositoryProvider)
          .products(
            cursor: current.cursor,
            country: filters.country,
            currency: filters.currency,
            category: filters.category,
            subcategory: filters.subcategory,
            audience: filters.audience,
            colors: filters.colors,
            sizes: filters.sizes,
            brands: filters.brands,
            minPriceMinor: filters.minPriceMinor,
            maxPriceMinor: filters.maxPriceMinor,
            tryOnReady: filters.tryOnReady,
            discounted: filters.discounted,
            query: filters.query,
          );

      // The filters may have changed while this page was in flight; dropping
      // it is correct, because build() has already started a fresh feed.
      final latest = state.asData?.value;
      if (latest == null) return;

      // Belt and braces against a duplicate id: the keyset cursor should make
      // this impossible, but a duplicate KEY in a ListView is a hard crash, so
      // it is filtered rather than trusted.
      final known = latest.items.map((p) => p.id).toSet();
      final fresh = page.items.where((p) => !known.contains(p.id)).toList();

      state = AsyncData(
        latest.copyWith(
          items: [...latest.items, ...fresh],
          cursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          loadingMore: false,
        ),
      );
    } catch (error) {
      // A failed page 2 must not blank the page 1 the user is reading.
      final latest = state.asData?.value;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(loadingMore: false, loadMoreFailed: true),
      );
      assert(() {
        debugPrint('[Discover] load more failed: $error');
        return true;
      }());
    }
  }

  /// Pull-to-refresh: back to page 1 with the same filters.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Optimistically flips the saved flag on a product, then persists it.
  ///
  /// Optimistic because a heart that waits on a round trip feels broken. Only
  /// the one product's row changes, so the grid does not rebuild wholesale on
  /// a save (§23 "avoid rebuilding the entire grid on one save action").
  Future<void> toggleSave(Product product) async {
    final current = state.asData?.value;
    if (current == null) return;
    final next = !product.saved;

    void write(bool value) {
      final latest = state.asData?.value;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(
          items: [
            for (final p in latest.items)
              if (p.id == product.id) p.copyWith(saved: value) else p,
          ],
        ),
      );
    }

    write(next);
    try {
      final repo = ref.read(discoverRepositoryProvider);
      if (next) {
        await repo.save(product.id);
      } else {
        await repo.unsave(product.id);
      }
    } catch (_) {
      write(!next); // put the heart back rather than lying about the state
      rethrow;
    }
  }
}
