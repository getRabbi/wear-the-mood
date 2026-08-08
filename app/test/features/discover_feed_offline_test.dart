import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/data/models/product.dart';
import 'package:app/data/repositories/discover_repository.dart';
import 'package:app/features/discover/application/product_feed.dart';
import 'package:app/features/discover/data/discover_feed_cache.dart';
import 'package:app/features/discover/data/discover_local_store.dart';
import 'package:app/features/discover/domain/product_filters.dart';

/// How the feed USES the cache: cached-first when warm, offline fallback when
/// the network is gone, and nothing cached at all for a filtered page.

Map<String, dynamic> rawPage({String id = 'p1', String? cursor}) => {
  'schema_version': 1,
  'server_time': '2026-08-05T00:00:00Z',
  'country': 'BD',
  'currency': 'BDT',
  'profile_version': 7,
  'items': [
    {
      'id': id,
      'merchant': {'id': 'm1', 'name': 'Atelier Noir'},
      'title': 'Dress $id',
      'price': {'amount_minor': 1000, 'currency': 'BDT'},
    },
  ],
  'next_cursor': cursor,
  'region_empty': false,
};

/// An in-memory [DiscoverFeedCache] with the same identity and freshness rules
/// as the file one, so feed behaviour can be driven without a disk.
class _MemCache implements DiscoverFeedCache {
  DateTime Function()? clock;

  DiscoverFeedCacheKey? key;
  Map<String, dynamic>? payload;
  DateTime? cachedAt;
  int writes = 0;
  int clears = 0;

  void seed(
    DiscoverFeedCacheKey k,
    Map<String, dynamic> p, {
    required Duration age,
  }) {
    key = k;
    payload = p;
    cachedAt = (clock ?? DateTime.now)().subtract(age);
  }

  @override
  Future<DiscoverFeedCacheEntry?> read(DiscoverFeedCacheKey k) async {
    if (key != k || payload == null || cachedAt == null) return null;
    final age = (clock ?? DateTime.now)().difference(cachedAt!);
    if (age > discoverFeedMaxStale) return null;
    return DiscoverFeedCacheEntry(
      page: ProductPage.fromJson(payload!),
      cachedAt: cachedAt!,
      freshness: age <= discoverFeedFreshTtl
          ? DiscoverCacheFreshness.fresh
          : DiscoverCacheFreshness.stale,
    );
  }

  @override
  Future<void> write(DiscoverFeedCacheKey k, Map<String, dynamic> p) async {
    writes++;
    key = k;
    payload = p;
    cachedAt = (clock ?? DateTime.now)();
  }

  @override
  Future<void> clear() async {
    clears++;
    key = null;
    payload = null;
    cachedAt = null;
  }
}

/// A local store that remembers only the shopping scope — the one piece the
/// cache key needs to survive a restart.
class _ScopeStore implements DiscoverLocalStore {
  _ScopeStore([this._scope = (null, null, 0)]);
  (String?, String?, int) _scope;

  @override
  Future<(String?, String?, int)> shoppingScope() async => _scope;

  @override
  Future<void> setShoppingScope(String? c, String? cur, int v) async =>
      _scope = (c, cur, v);

  @override
  Future<void> clearAll() async => _scope = (null, null, 0);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeRepo implements DiscoverRepository {
  _FakeRepo({this.offline = false, this.hang = false, this.page});
  bool offline;

  /// Never completes — stands for a slow or dead network.
  bool hang;
  Map<String, dynamic>? page;
  int calls = 0;
  String? lastCursor;

  @override
  Future<ProductPageResult> products({
    String? cursor,
    int? limit,
    String? country,
    String? currency,
    String? category,
    String? subcategory,
    String? audience,
    List<String> colors = const [],
    List<String> sizes = const [],
    List<String> brands = const [],
    int? minPriceMinor,
    int? maxPriceMinor,
    bool tryOnReady = false,
    bool discounted = false,
    String? query,
    CancelToken? cancelToken,
  }) async {
    calls++;
    lastCursor = cursor;
    if (hang) return Completer<ProductPageResult>().future;
    if (offline) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(),
        reason: 'no network',
      );
    }
    final raw = page ?? rawPage(id: 'live');
    return ProductPageResult(page: ProductPage.fromJson(raw), raw: raw);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

void main() {
  const key = DiscoverFeedCacheKey(
    userScope: 'user-a',
    country: 'BD',
    currency: 'BDT',
    profileVersion: 7,
  );

  /// [knownScope] stands for a device that has talked to the server before —
  /// the persisted region a cold start restores before building its cache key.
  ProviderContainer boot(
    _FakeRepo repo,
    DiscoverFeedCache cache, {
    String user = 'user-a',
    (String?, String?, int) knownScope = ('BD', 'BDT', 7),
  }) {
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        authUserIdProvider.overrideWithValue(user),
        discoverRepositoryProvider.overrideWithValue(repo),
        discoverFeedCacheProvider.overrideWithValue(cache),
        discoverLocalStoreProvider.overrideWithValue(_ScopeStore(knownScope)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a cold cache fetches and then stores the page', () async {
    final repo = _FakeRepo();
    final cache = _MemCache();
    final container = boot(repo, cache);

    final state = await container.read(productFeedProvider.future);
    expect(state.items.single.id, 'live');
    expect(state.fromCache, isFalse);
    expect(cache.writes, 1);
    // Stored under the region the SERVER resolved, not what we guessed.
    expect(cache.key?.country, 'BD');
    expect(cache.key?.profileVersion, 7);
  });

  test('a fresh cache is served without waiting on the network', () async {
    // The repo never answers. If the feed waited on it, this would time out —
    // so resolving at all IS the proof that the cache short-circuits the fetch
    // (§24 "do not display a blocking spinner when valid cache is available").
    final repo = _FakeRepo(hang: true);
    final cache = _MemCache()
      ..seed(key, rawPage(id: 'cached'), age: const Duration(hours: 1));
    final container = boot(repo, cache);

    final state = await container.read(productFeedProvider.future);
    expect(state.items.single.id, 'cached');
    // Not flagged offline: it is current, merely not re-fetched yet.
    expect(state.fromCache, isFalse);
    expect(state.cachedAt, isNotNull);
  });

  test('a fresh cache still revalidates in the background', () async {
    final repo = _FakeRepo();
    final cache = _MemCache()
      ..seed(key, rawPage(id: 'cached'), age: const Duration(hours: 1));
    final container = boot(repo, cache);

    await container.read(productFeedProvider.future);
    // Let the detached revalidation settle.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(repo.calls, 1, reason: 'refreshed behind the cached page');
    expect(
      container.read(productFeedProvider).asData?.value.items.single.id,
      'live',
      reason: 'the background refresh replaced the cached page',
    );
  });

  test('an expired TTL fetches rather than serving stale as current', () async {
    final repo = _FakeRepo();
    final cache = _MemCache()
      ..seed(key, rawPage(id: 'cached'), age: const Duration(hours: 8));
    final container = boot(repo, cache);

    final state = await container.read(productFeedProvider.future);
    expect(repo.calls, 1);
    expect(state.items.single.id, 'live');
    expect(state.fromCache, isFalse);
  });

  test(
    'offline with a stale cache under 72h serves it, clearly labelled',
    () async {
      final repo = _FakeRepo(offline: true);
      final cache = _MemCache()
        ..seed(key, rawPage(id: 'cached'), age: const Duration(hours: 40));
      final container = boot(repo, cache);

      final state = await container.read(productFeedProvider.future);
      expect(state.items.single.id, 'cached');
      // The flag the UI uses to say the prices are not current (§24, §35).
      expect(state.fromCache, isTrue);
      expect(state.cachedAt, isNotNull);
    },
  );

  test('offline with a cache older than 72h surfaces the failure', () async {
    // Past the window it is not a product feed any more, so an honest error
    // beats a convincing-looking page of prices nobody has confirmed.
    final repo = _FakeRepo(offline: true);
    final cache = _MemCache()
      ..seed(key, rawPage(id: 'ancient'), age: const Duration(hours: 80));
    final container = boot(repo, cache);

    await expectLater(
      container.read(productFeedProvider.future),
      throwsA(isA<Object>()),
    );
  });

  test('offline with no cache at all surfaces the failure', () async {
    final container = boot(_FakeRepo(offline: true), _MemCache());
    await expectLater(
      container.read(productFeedProvider.future),
      throwsA(isA<Object>()),
    );
  });

  test('another account cannot read the cache', () async {
    final repo = _FakeRepo();
    final cache = _MemCache()
      ..seed(key, rawPage(id: 'cached'), age: const Duration(hours: 1));
    final container = boot(repo, cache, user: 'user-b');

    final state = await container.read(productFeedProvider.future);
    expect(state.items.single.id, 'live', reason: 'user-b must not see user-a');
  });

  test('a signed-out session cannot read a signed-in cache', () async {
    final repo = _FakeRepo();
    final cache = _MemCache()
      ..seed(key, rawPage(id: 'cached'), age: const Duration(hours: 1));
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        authUserIdProvider.overrideWithValue(null),
        discoverRepositoryProvider.overrideWithValue(repo),
        discoverFeedCacheProvider.overrideWithValue(cache),
        discoverLocalStoreProvider.overrideWithValue(
          _ScopeStore(('BD', 'BDT', 7)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(productFeedProvider.future);
    expect(state.items.single.id, 'live');
  });

  test('a region change on another device invalidates the cache', () async {
    // The persisted scope says US; the cached page was written for BD.
    final repo = _FakeRepo();
    final cache = _MemCache()
      ..seed(key, rawPage(id: 'cached'), age: const Duration(hours: 1));
    final container = boot(repo, cache, knownScope: ('US', 'USD', 7));

    final state = await container.read(productFeedProvider.future);
    expect(state.items.single.id, 'live');
  });

  test('a profile change invalidates the cache', () async {
    final repo = _FakeRepo();
    final cache = _MemCache()
      ..seed(key, rawPage(id: 'cached'), age: const Duration(hours: 1));
    final container = boot(repo, cache, knownScope: ('BD', 'BDT', 9));

    final state = await container.read(productFeedProvider.future);
    expect(state.items.single.id, 'live');
  });

  test(
    'a cold start with no persisted scope still writes under the resolved one',
    () async {
      // First ever launch: nothing is known, so the fetch is the only option —
      // and what it writes must be keyed by the region the SERVER resolved, so
      // the NEXT cold start hits.
      final repo = _FakeRepo();
      final cache = _MemCache();
      final container = boot(repo, cache, knownScope: (null, null, 0));

      await container.read(productFeedProvider.future);
      expect(cache.key?.country, 'BD');
      expect(cache.key?.currency, 'BDT');
      expect(cache.key?.profileVersion, 7);
    },
  );

  test('a filtered page is never cached', () async {
    final repo = _FakeRepo();
    final cache = _MemCache();
    final container = boot(repo, cache);

    container
        .read(productFiltersProvider.notifier)
        .apply(const ProductFilters(category: 'dresses'));
    await container.read(productFeedProvider.future);

    expect(cache.writes, 0, reason: 'only the unfiltered first page is cached');
  });

  test('a filtered page does not READ the cache either', () async {
    final repo = _FakeRepo();
    final cache = _MemCache()
      ..seed(key, rawPage(id: 'cached'), age: const Duration(hours: 1));
    final container = boot(repo, cache);

    container
        .read(productFiltersProvider.notifier)
        .apply(const ProductFilters(category: 'dresses'));
    final state = await container.read(productFeedProvider.future);

    expect(state.items.single.id, 'live');
  });

  test('page two is never cached', () async {
    final repo = _FakeRepo(
      page: rawPage(id: 'p1', cursor: 'c2'),
    );
    final cache = _MemCache();
    final container = boot(repo, cache);

    await container.read(productFeedProvider.future);
    final writesAfterFirstPage = cache.writes;

    repo.page = rawPage(id: 'p2');
    await container.read(productFeedProvider.notifier).loadMore();

    expect(cache.writes, writesAfterFirstPage);
    expect(repo.lastCursor, 'c2');
  });

  test('a cache write failure does not break the feed', () async {
    final repo = _FakeRepo();
    final container = boot(repo, _ExplodingCache());

    final state = await container.read(productFeedProvider.future);
    expect(state.items.single.id, 'live');
  });
}

/// A cache whose every operation fails — a full disk, in effect.
class _ExplodingCache implements DiscoverFeedCache {
  @override
  Future<DiscoverFeedCacheEntry?> read(DiscoverFeedCacheKey key) async =>
      throw StateError('disk full');
  @override
  Future<void> write(DiscoverFeedCacheKey key, Map<String, dynamic> r) async =>
      throw StateError('disk full');
  @override
  Future<void> clear() async => throw StateError('disk full');
}
