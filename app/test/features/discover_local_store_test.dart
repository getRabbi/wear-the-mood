import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/features/discover/data/discover_local_store.dart';

/// Contract coverage for the Discover on-device store: what it remembers, the
/// caps, the user-facing clears, and — the property the UI actually leans on —
/// that a broken backing store degrades to "nothing remembered" instead of
/// throwing into a browsing surface.
///
/// Both doubles below are local rather than the plugin's own in-memory
/// platform, so the suite depends on nothing beyond the package the app
/// already declares.

/// An in-memory [SharedPreferencesAsync]. Only the operations the store uses
/// are implemented; anything else is a deliberate failure rather than a silent
/// no-op, so a future call that bypasses this fake is caught here.
class _FakePrefs implements SharedPreferencesAsync {
  final Map<String, Object> values = {};

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<List<String>?> getStringList(String key) async =>
      (values[key] as List<String>?)?.toList();

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      values[key] = value.toList();

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async =>
      values.keys.toSet();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

/// A store whose every operation fails, standing in for a full disk, a missing
/// platform channel, or a denied keystore.
class _ExplodingPrefs implements SharedPreferencesAsync {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('backing store unavailable'));
}

void main() {
  late _FakePrefs prefs;
  late SharedPrefsDiscoverLocalStore store;

  setUp(() {
    prefs = _FakePrefs();
    store = SharedPrefsDiscoverLocalStore(prefs);
  });

  group('story seen state', () {
    test(
      'starts empty and records a seen story at its content version',
      () async {
        expect(await store.seenStoryVersions(), isEmpty);

        await store.markStorySeen('story-a', 3);
        expect(await store.seenStoryVersions(), {'story-a': 3});
      },
    );

    test('a newer content version makes a seen story fresh again', () async {
      await store.markStorySeen('story-a', 1);
      await store.markStorySeen('story-a', 2);
      expect(await store.seenStoryVersions(), {'story-a': 2});
    });

    test('never moves a story backwards', () async {
      // A stale in-flight viewer writing an old version must not resurrect a
      // story the user has already seen at a newer one.
      await store.markStorySeen('story-a', 5);
      await store.markStorySeen('story-a', 2);
      expect(await store.seenStoryVersions(), {'story-a': 5});
    });

    test('tracks stories independently', () async {
      await store.markStorySeen('story-a', 1);
      await store.markStorySeen('story-b', 7);
      expect(await store.seenStoryVersions(), {'story-a': 1, 'story-b': 7});
    });

    test('ignores a blank story id', () async {
      await store.markStorySeen('', 1);
      expect(await store.seenStoryVersions(), isEmpty);
    });

    test('survives a corrupt value instead of throwing', () async {
      prefs.values['$discoverStoreNamespace.seen_stories'] = 'not json at all';
      expect(await store.seenStoryVersions(), isEmpty);
    });

    test('keeps the entries it understands from a mixed-shape value', () async {
      // A newer build could write a richer value. Drop what does not parse,
      // keep what does — never discard the whole map.
      prefs.values['$discoverStoreNamespace.seen_stories'] =
          '{"story-a":2,"story-b":{"v":3},"story-c":4}';
      expect(await store.seenStoryVersions(), {'story-a': 2, 'story-c': 4});
    });
  });

  group('recent searches', () {
    test('newest first, case-insensitively de-duplicated', () async {
      await store.addRecentSearch('black dress');
      await store.addRecentSearch('office outfit');
      await store.addRecentSearch('Black Dress');

      // The re-search moves to the front and keeps the newer casing; the older
      // spelling does not linger as a second row.
      expect(await store.recentSearches(), ['Black Dress', 'office outfit']);
    });

    test('trims whitespace and ignores blank terms', () async {
      await store.addRecentSearch('   ');
      await store.addRecentSearch('  wedding guest  ');
      expect(await store.recentSearches(), ['wedding guest']);
    });

    test('caps the list at maxRecentSearches, dropping the oldest', () async {
      for (var i = 0; i <= maxRecentSearches; i++) {
        await store.addRecentSearch('term $i');
      }
      final recents = await store.recentSearches();
      expect(recents, hasLength(maxRecentSearches));
      expect(recents.first, 'term $maxRecentSearches');
      expect(recents, isNot(contains('term 0')));
    });

    test('clear empties them', () async {
      await store.addRecentSearch('summer tops');
      await store.clearRecentSearches();
      expect(await store.recentSearches(), isEmpty);
    });
  });

  group('recently viewed products', () {
    test('newest first and de-duplicated', () async {
      await store.addRecentlyViewedProduct('p1');
      await store.addRecentlyViewedProduct('p2');
      await store.addRecentlyViewedProduct('p1');
      expect(await store.recentlyViewedProductIds(), ['p1', 'p2']);
    });

    test('caps at maxRecentlyViewed', () async {
      for (var i = 0; i < maxRecentlyViewed + 5; i++) {
        await store.addRecentlyViewedProduct('bulk-$i');
      }
      expect(
        await store.recentlyViewedProductIds(),
        hasLength(maxRecentlyViewed),
      );
    });

    test('clear empties them', () async {
      await store.addRecentlyViewedProduct('p1');
      await store.clearRecentlyViewed();
      expect(await store.recentlyViewedProductIds(), isEmpty);
    });
  });

  test('clearAll drops every Discover key', () async {
    await store.markStorySeen('story-a', 1);
    await store.addRecentSearch('denim');
    await store.addRecentlyViewedProduct('p1');

    await store.clearAll();

    expect(await store.seenStoryVersions(), isEmpty);
    expect(await store.recentSearches(), isEmpty);
    expect(await store.recentlyViewedProductIds(), isEmpty);
    expect(prefs.values, isEmpty);
  });

  test('every key is namespaced under the versioned prefix', () async {
    // Bumping the namespace must be enough to abandon an incompatible shape,
    // which only holds if nothing writes outside it.
    await store.markStorySeen('story-a', 1);
    await store.addRecentSearch('denim');
    await store.addRecentlyViewedProduct('p1');

    expect(prefs.values.keys, hasLength(3));
    expect(
      prefs.values.keys.every((k) => k.startsWith('$discoverStoreNamespace.')),
      isTrue,
      reason: 'unexpected key outside the namespace: ${prefs.values.keys}',
    );
  });

  group('a broken backing store degrades, never throws', () {
    late SharedPrefsDiscoverLocalStore broken;
    setUp(() => broken = SharedPrefsDiscoverLocalStore(_ExplodingPrefs()));

    test('reads answer empty', () async {
      expect(await broken.seenStoryVersions(), isEmpty);
      expect(await broken.recentSearches(), isEmpty);
      expect(await broken.recentlyViewedProductIds(), isEmpty);
    });

    test('writes and clears complete silently', () async {
      // No expect() beyond "these futures complete" — that IS the contract.
      // Discover must open on a device where persistence is unavailable.
      await broken.markStorySeen('story-a', 1);
      await broken.addRecentSearch('denim');
      await broken.addRecentlyViewedProduct('p1');
      await broken.clearRecentSearches();
      await broken.clearRecentlyViewed();
      await broken.clearAll();
    });
  });
}
