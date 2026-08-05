import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../data/models/product.dart';
import '../../../data/repositories/discover_repository.dart';
import '../data/discover_feed_cache.dart';
import '../data/discover_local_store.dart';
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
    this.fromCache = false,
    this.cachedAt,
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

  /// These items came from the offline cache after the network failed. The UI
  /// says so, non-blockingly — a stale price presented as current is worse
  /// than no feed (§24, §35).
  final bool fromCache;

  /// When the cached page was stored. Null when this is live data.
  final DateTime? cachedAt;

  bool get hasMore => (cursor ?? '').isNotEmpty;
  bool get isEmpty => items.isEmpty;

  ProductFeedState copyWith({
    List<Product>? items,
    String? cursor,
    bool clearCursor = false,
    bool? loadingMore,
    bool? regionEmpty,
    bool? loadMoreFailed,
    bool? fromCache,
    DateTime? cachedAt,
  }) => ProductFeedState(
    items: items ?? this.items,
    cursor: clearCursor ? null : (cursor ?? this.cursor),
    loadingMore: loadingMore ?? this.loadingMore,
    regionEmpty: regionEmpty ?? this.regionEmpty,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    fromCache: fromCache ?? this.fromCache,
    cachedAt: cachedAt ?? this.cachedAt,
  );
}

/// The identity the offline cache is keyed on, for the CURRENT session.
///
/// Derived from the signed-in account plus the last region the server resolved
/// for it. Signed out is its own scope, so a signed-out browse can never read
/// a signed-in cache and a logout leaves nothing readable behind.
final discoverCacheKeyProvider = Provider<DiscoverFeedCacheKey>((ref) {
  final userId = ref.watch(authUserIdProvider);
  final scope = ref.watch(discoverShoppingScopeProvider);
  return DiscoverFeedCacheKey(
    userScope: userId ?? 'anonymous',
    country: scope.country,
    currency: scope.currency,
    profileVersion: scope.profileVersion,
  );
});

/// The last region and preference stamp the server reported.
///
/// Held in memory and refreshed from every successful page. It seeds the cache
/// key, so when the account's country, currency or shopping preferences change
/// the key changes with them and the previous cache stops being readable —
/// which is the invalidation §34 asks for.
@immutable
class DiscoverShoppingScope {
  const DiscoverShoppingScope({
    this.country,
    this.currency,
    this.profileVersion = 0,
  });

  final String? country;
  final String? currency;
  final int profileVersion;

  @override
  bool operator ==(Object other) =>
      other is DiscoverShoppingScope &&
      other.country == country &&
      other.currency == currency &&
      other.profileVersion == profileVersion;

  @override
  int get hashCode => Object.hash(country, currency, profileVersion);
}

final discoverShoppingScopeProvider =
    NotifierProvider<DiscoverShoppingScopeNotifier, DiscoverShoppingScope>(
      DiscoverShoppingScopeNotifier.new,
    );

class DiscoverShoppingScopeNotifier extends Notifier<DiscoverShoppingScope> {
  bool _restored = false;

  @override
  DiscoverShoppingScope build() => const DiscoverShoppingScope();

  /// Loads the persisted scope once per session. Idempotent, so the feed can
  /// call it on every rebuild without re-reading disk.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final (country, currency, profile) = await ref
          .read(discoverLocalStoreProvider)
          .shoppingScope();
      final restored = DiscoverShoppingScope(
        country: country,
        currency: currency,
        profileVersion: profile,
      );
      if (restored != state) state = restored;
    } catch (error) {
      // A store that cannot answer means "region unknown", which costs a cache
      // miss — not a feed that fails to load. The feed awaits this before
      // building its cache key, so an unguarded throw here would take Discover
      // down over a persistence detail.
      assert(() {
        debugPrint('[Discover] scope restore failed: $error');
        return true;
      }());
    }
  }

  /// Takes the region and profile stamp from a server response, and persists
  /// them so the next cold start builds the same cache key.
  Future<void> adopt(ProductPage page) async {
    _restored = true;
    final next = DiscoverShoppingScope(
      country: page.country,
      currency: page.currency,
      profileVersion: page.profileVersion,
    );
    if (next == state) return;
    state = next;
    try {
      await ref
          .read(discoverLocalStoreProvider)
          .setShoppingScope(next.country, next.currency, next.profileVersion);
    } catch (error) {
      // Not persisting the scope only costs the NEXT cold start a cache miss.
      assert(() {
        debugPrint('[Discover] scope persist failed: $error');
        return true;
      }());
    }
  }
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

  /// Cache access, defensively. The file implementation already swallows its
  /// own failures, but the feed must not DEPEND on that: the cache is behind an
  /// interface, and a browsing surface that dies because a disk said no would
  /// be a bad trade for an optimization. A failed read is simply a miss and a
  /// failed write is simply not cached.
  Future<DiscoverFeedCacheEntry?> _readCache(DiscoverFeedCacheKey key) async {
    try {
      return await ref.read(discoverFeedCacheProvider).read(key);
    } catch (error) {
      assert(() {
        debugPrint('[Discover] cache read failed: $error');
        return true;
      }());
      return null;
    }
  }

  Future<void> _writeCache(
    DiscoverFeedCacheKey key,
    Map<String, dynamic> raw,
  ) async {
    try {
      await ref.read(discoverFeedCacheProvider).write(key, raw);
    } catch (error) {
      assert(() {
        debugPrint('[Discover] cache write failed: $error');
        return true;
      }());
    }
  }

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

    // Only the UNFILTERED first page is cacheable. A filtered page is a
    // transient view of a query, not something to promise offline.
    final cacheable = !filters.hasAny;
    // Restore the last known region/profile from disk BEFORE building the key.
    // On a cold start the app has not talked to the server yet, so a key built
    // from in-memory defaults could never match the key the cached page was
    // written under — and the cache would miss exactly when it is needed.
    await ref.read(discoverShoppingScopeProvider.notifier).restore();
    final key = ref.read(discoverCacheKeyProvider);

    if (cacheable) {
      final cached = await _readCache(key);
      if (cached != null && cached.isFresh) {
        // Cached-first: show it now and revalidate behind, so opening Discover
        // on a warm cache never waits on the network (§23, §33.4).
        unawaited(_revalidate(filters, key));
        return ProductFeedState(
          items: cached.page.items,
          cursor: cached.page.nextCursor,
          regionEmpty: cached.page.regionEmpty,
          cachedAt: cached.cachedAt,
        );
      }
    }

    try {
      final result = await _fetch(filters, token: token);
      await ref.read(discoverShoppingScopeProvider.notifier).adopt(result.page);
      if (cacheable) {
        // The key is re-read AFTER the response, because the response is what
        // tells us the region the server actually resolved. Writing under the
        // pre-request key would file the page under the wrong identity.
        await _writeCache(ref.read(discoverCacheKeyProvider), result.raw);
      }
      return ProductFeedState(
        items: result.page.items,
        cursor: result.page.nextCursor,
        regionEmpty: result.page.regionEmpty,
      );
    } catch (error) {
      // Offline. A cache inside the stale window is better than an error
      // screen — but it is labelled, never passed off as current (§24).
      if (cacheable) {
        final cached = await _readCache(key);
        if (cached != null) {
          return ProductFeedState(
            items: cached.page.items,
            cursor: cached.page.nextCursor,
            regionEmpty: cached.page.regionEmpty,
            fromCache: true,
            cachedAt: cached.cachedAt,
          );
        }
      }
      // Nothing usable cached, or the cache is past 72h and no longer a
      // product feed. Surface the failure honestly.
      rethrow;
    }
  }

  Future<ProductPageResult> _fetch(
    ProductFilters filters, {
    String? cursor,
    CancelToken? token,
  }) => ref
      .read(discoverRepositoryProvider)
      .products(
        cursor: cursor,
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

  /// Background refresh behind a fresh cache hit.
  ///
  /// Failure is silent by design: the user already has a good page on screen,
  /// and an error toast over content that is fine would be noise.
  Future<void> _revalidate(
    ProductFilters filters,
    DiscoverFeedCacheKey key,
  ) async {
    try {
      final result = await _fetch(filters);
      await ref.read(discoverShoppingScopeProvider.notifier).adopt(result.page);
      await _writeCache(ref.read(discoverCacheKeyProvider), result.raw);
      final current = state.asData?.value;
      if (current == null) return;
      state = AsyncData(
        current.copyWith(
          items: result.page.items,
          cursor: result.page.nextCursor,
          clearCursor: result.page.nextCursor == null,
          regionEmpty: result.page.regionEmpty,
          fromCache: false,
        ),
      );
    } catch (error) {
      assert(() {
        debugPrint('[Discover] background revalidate failed: $error');
        return true;
      }());
    }
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
      final page = (await _fetch(filters, cursor: current.cursor)).page;

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
