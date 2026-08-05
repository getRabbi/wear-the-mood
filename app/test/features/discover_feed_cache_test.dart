import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/discover/data/discover_feed_cache.dart';

/// The offline feed cache contract (DISCOVER §23, §24, §34).
///
/// Every case here is one the cache will actually meet on a device: a clock
/// that has moved, a file half-written when the app was killed, a user who
/// signed into a second account, a region change, and a disk that says no.
/// The rule throughout is that the cache is an optimization — it may return
/// nothing, but it may never throw into a browsing surface, and it may never
/// hand one account's feed to another.

/// A payload shaped like a real API response, so it round-trips through
/// `ProductPage.fromJson` exactly as the live one does.
Map<String, dynamic> payload({String id = 'p1', String country = 'BD'}) => {
  'schema_version': 1,
  'server_time': '2026-08-05T00:00:00Z',
  'country': country,
  'currency': 'BDT',
  'profile_version': 7,
  'items': [
    {
      'id': id,
      'merchant': {'id': 'm1', 'name': 'Atelier Noir'},
      'title': 'Black silk slip dress',
      'price': {'amount_minor': 349900, 'currency': 'BDT'},
      'image_urls': ['https://cdn.example.test/d1.jpg'],
      'stock_status': 'in_stock',
      'try_on_status': 'ready',
    },
  ],
  'next_cursor': 'cursor-2',
  'region_empty': false,
};

const keyA = DiscoverFeedCacheKey(
  userScope: 'user-a',
  country: 'BD',
  currency: 'BDT',
  profileVersion: 7,
);

void main() {
  late Directory dir;
  late DateTime now;

  FileDiscoverFeedCache build() =>
      FileDiscoverFeedCache(directory: () async => dir, clock: () => now);

  File cacheFile() => File(
    '${dir.path}${Platform.pathSeparator}${FileDiscoverFeedCache.fileName}',
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wtm_discover_cache_test');
    now = DateTime(2026, 8, 5, 12);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('freshness', () {
    test('a page written now reads back fresh', () async {
      final cache = build();
      await cache.write(keyA, payload());

      final entry = await cache.read(keyA);
      expect(entry, isNotNull);
      expect(entry!.isFresh, isTrue);
      expect(entry.freshness, DiscoverCacheFreshness.fresh);
      expect(entry.page.items.single.id, 'p1');
      expect(entry.page.nextCursor, 'cursor-2');
    });

    test('inside the 6h TTL it is still fresh', () async {
      final cache = build();
      await cache.write(keyA, payload());

      now = now.add(const Duration(hours: 5, minutes: 59));
      expect((await build().read(keyA))!.isFresh, isTrue);
    });

    test('past the 6h TTL it is stale but still usable offline', () async {
      final cache = build();
      await cache.write(keyA, payload());

      now = now.add(const Duration(hours: 6, minutes: 1));
      final entry = await build().read(keyA);
      expect(entry, isNotNull);
      expect(entry!.isFresh, isFalse);
      expect(entry.freshness, DiscoverCacheFreshness.stale);
    });

    test('inside 72h it is still served', () async {
      final cache = build();
      await cache.write(keyA, payload());

      now = now.add(const Duration(hours: 71, minutes: 59));
      expect(await build().read(keyA), isNotNull);
    });

    test('past 72h it is dropped, not presented as a product feed', () async {
      // §35: a price nobody has confirmed in three days is not a current
      // price, and showing it with a caveat is still showing it.
      final cache = build();
      await cache.write(keyA, payload());

      now = now.add(const Duration(hours: 72, minutes: 1));
      expect(await build().read(keyA), isNull);
      expect(
        cacheFile().existsSync(),
        isFalse,
        reason: 'expired file is removed',
      );
    });

    test('a backwards clock is treated as unusable, not infinitely fresh', () {
      // A timezone change or a manual clock set must not make a cache
      // permanently "fresh".
      return () async {
        final cache = build();
        await cache.write(keyA, payload());
        now = now.subtract(const Duration(hours: 5));
        expect(await build().read(keyA), isNull);
      }();
    });
  });

  group('identity', () {
    test('a different account never reads the cache', () async {
      // The single most important property here.
      await build().write(keyA, payload());

      const other = DiscoverFeedCacheKey(
        userScope: 'user-b',
        country: 'BD',
        currency: 'BDT',
        profileVersion: 7,
      );
      expect(await build().read(other), isNull);
    });

    test('signed out is its own scope', () async {
      await build().write(keyA, payload());
      expect(
        await build().read(const DiscoverFeedCacheKey(userScope: 'anonymous')),
        isNull,
      );
    });

    test('a country change invalidates', () async {
      await build().write(keyA, payload());
      const moved = DiscoverFeedCacheKey(
        userScope: 'user-a',
        country: 'US',
        currency: 'BDT',
        profileVersion: 7,
      );
      expect(await build().read(moved), isNull);
    });

    test('a currency change invalidates', () async {
      await build().write(keyA, payload());
      const moved = DiscoverFeedCacheKey(
        userScope: 'user-a',
        country: 'BD',
        currency: 'USD',
        profileVersion: 7,
      );
      expect(await build().read(moved), isNull);
    });

    test('a shopping-profile change invalidates', () async {
      // Preferences changed, so the ranking behind this page is obsolete.
      await build().write(keyA, payload());
      const reprofiled = DiscoverFeedCacheKey(
        userScope: 'user-a',
        country: 'BD',
        currency: 'BDT',
        profileVersion: 8,
      );
      expect(await build().read(reprofiled), isNull);
    });

    test('an incompatible schema is ignored', () async {
      await build().write(keyA, payload());
      const newer = DiscoverFeedCacheKey(
        userScope: 'user-a',
        country: 'BD',
        currency: 'BDT',
        profileVersion: 7,
        schema: 99,
      );
      expect(await build().read(newer), isNull);
    });

    test('clear removes the file', () async {
      await build().write(keyA, payload());
      expect(cacheFile().existsSync(), isTrue);

      await build().clear();
      expect(cacheFile().existsSync(), isFalse);
      expect(await build().read(keyA), isNull);
    });
  });

  group('file safety', () {
    test('a missing file is simply a miss', () async {
      expect(await build().read(keyA), isNull);
    });

    test('corrupt JSON is discarded, not thrown', () async {
      cacheFile().writeAsStringSync('{not json at all');
      expect(await build().read(keyA), isNull);
      expect(cacheFile().existsSync(), isFalse);
    });

    test('a truncated file recovers', () async {
      // What a kill mid-write would look like without the atomic rename.
      final full = jsonEncode({
        'key': keyA.toJson(),
        'cached_at': now.toIso8601String(),
        'payload': payload(),
      });
      cacheFile().writeAsStringSync(full.substring(0, full.length ~/ 2));
      expect(await build().read(keyA), isNull);
    });

    test(
      'a structurally valid file with a junk payload is discarded',
      () async {
        cacheFile().writeAsStringSync(
          jsonEncode({
            'key': keyA.toJson(),
            'cached_at': now.toIso8601String(),
            'payload': 'not a map',
          }),
        );
        expect(await build().read(keyA), isNull);
      },
    );

    test('a missing timestamp is discarded', () async {
      cacheFile().writeAsStringSync(
        jsonEncode({'key': keyA.toJson(), 'payload': payload()}),
      );
      expect(await build().read(keyA), isNull);
    });

    test('an oversized file is rejected without being parsed', () async {
      cacheFile().writeAsStringSync('x' * (discoverFeedCacheMaxBytes + 1));
      expect(await build().read(keyA), isNull);
      expect(cacheFile().existsSync(), isFalse);
    });

    test('an oversized payload is never written', () async {
      final huge = payload();
      huge['items'] = [
        for (var i = 0; i < 5000; i++) ...(payload(id: 'p$i')['items'] as List),
      ];
      await build().write(keyA, huge);
      expect(cacheFile().existsSync(), isFalse);
    });

    test('the write is atomic — no temp file survives', () async {
      await build().write(keyA, payload());
      final leftovers = dir
          .listSync()
          .where((e) => e.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('an unwritable location fails silently', () async {
      // A disk that says no must not take Discover down with it.
      final cache = FileDiscoverFeedCache(
        directory: () async =>
            throw const FileSystemException('no such volume'),
        clock: () => now,
      );
      await cache.write(keyA, payload());
      expect(await cache.read(keyA), isNull);
      await cache.clear();
    });

    test('a read failure answers null rather than throwing', () async {
      final cache = FileDiscoverFeedCache(
        directory: () async => throw const FileSystemException('gone'),
        clock: () => now,
      );
      expect(await cache.read(keyA), isNull);
    });
  });

  test('a rewrite replaces rather than appends', () async {
    await build().write(keyA, payload(id: 'old'));
    await build().write(keyA, payload(id: 'new'));

    final entry = await build().read(keyA);
    expect(entry!.page.items.single.id, 'new');
  });

  test(
    'the payload is the server envelope, not a re-serialized model',
    () async {
      // The reason this cache stores raw JSON: Product.toJson() writes nested
      // objects as objects under this project's codegen settings and would not
      // read back. Storing what the server said also keeps fields this build
      // does not know about intact.
      final withUnknown = payload()..['some_future_field'] = {'a': 1};
      await build().write(keyA, withUnknown);

      final onDisk = jsonDecode(cacheFile().readAsStringSync()) as Map;
      expect(onDisk['payload'], containsPair('some_future_field', {'a': 1}));
      expect(await build().read(keyA), isNotNull);
    },
  );
}
