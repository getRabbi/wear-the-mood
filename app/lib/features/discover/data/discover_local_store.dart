import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device store for **non-sensitive** Discover state (DISCOVER spec §6.4,
/// §11.1, §23, §36).
///
/// What belongs here: which stories the user has already seen, recent search
/// terms, recently viewed product ids. All of it is small, reconstructible, and
/// harmless if read off a rooted device.
///
/// What must NEVER come here: auth tokens, body-photo or closet URLs, affiliate
/// secrets, or anything else the privacy rules cover. Those stay in
/// `flutter_secure_storage` (`core/auth/secure_local_storage.dart`). The
/// separation is the point of having two stores — keep it.
///
/// Two behaviours the callers depend on:
///
/// * **Never throws.** Disk can be full, the platform channel can be missing in
///   a unit test, a value can be corrupt. Discover is a browsing surface; it
///   must degrade to "nothing remembered" rather than fail to open (§24). Every
///   read falls back to an empty value and every write is best-effort.
/// * **Namespaced and versioned keys.** Everything is written under
///   `discover.v1.*`. When a shape has to change incompatibly, bump to `v2` and
///   the old rows are simply never read again — no migration, no crash on a
///   value written by a newer build.
abstract interface class DiscoverLocalStore {
  /// Story id → the `content_version` that was seen. A story is fresh again
  /// only when its version moves past the stored one (§6.4).
  Future<Map<String, int>> seenStoryVersions();

  /// Records [storyId] as seen at [contentVersion]. Call only after the viewer
  /// content actually loaded — a failed load must not mark a story seen (§6.5).
  Future<void> markStorySeen(String storyId, int contentVersion);

  /// Most-recent-first search terms, newest at index 0, capped at
  /// [maxRecentSearches].
  Future<List<String>> recentSearches();

  /// Adds [term] to the front, de-duplicated case-insensitively, trimming the
  /// tail past the cap. Blank terms are ignored.
  Future<void> addRecentSearch(String term);

  /// Clears recent searches — a required user control (§36).
  Future<void> clearRecentSearches();

  /// Most-recent-first product ids, capped at [maxRecentlyViewed]. Used to keep
  /// just-seen products out of the first feed positions (§33.3).
  Future<List<String>> recentlyViewedProductIds();

  /// Adds [productId] to the front, de-duplicated, trimming past the cap.
  Future<void> addRecentlyViewedProduct(String productId);

  /// Clears recently viewed products — a required user control (§36).
  Future<void> clearRecentlyViewed();

  /// The last shopping region and preference stamp the server reported, as
  /// `(country, currency, profileVersion)`.
  ///
  /// Persisted because the offline feed cache is keyed on it. On a cold start
  /// the app has not talked to the server yet, so without this the key it
  /// builds could never match the key the page was written under and the cache
  /// would never hit — which is precisely when it is needed.
  Future<(String?, String?, int)> shoppingScope();

  Future<void> setShoppingScope(
    String? country,
    String? currency,
    int profileVersion,
  );

  /// Drops every Discover key. For sign-out and "delete my data" (§10).
  Future<void> clearAll();
}

/// Key namespace. Bump the version segment to abandon an incompatible shape.
@visibleForTesting
const discoverStoreNamespace = 'discover.v1';

const _kSeenStories = '$discoverStoreNamespace.seen_stories';
const _kRecentSearches = '$discoverStoreNamespace.recent_searches';
const _kRecentlyViewed = '$discoverStoreNamespace.recently_viewed';
const _kShoppingScope = '$discoverStoreNamespace.shopping_scope';

/// Caps. Small on purpose: this is a convenience cache, not a history log, and
/// an unbounded list on disk is a slow leak.
const maxRecentSearches = 12;
const maxRecentlyViewed = 60;

/// [DiscoverLocalStore] on `SharedPreferencesAsync` — the modern API, which
/// talks to the platform on every call and so has no stale in-memory snapshot
/// to keep in sync (the legacy `SharedPreferences.getInstance()` cache is
/// deliberately not used).
class SharedPrefsDiscoverLocalStore implements DiscoverLocalStore {
  SharedPrefsDiscoverLocalStore([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  /// Runs [op], swallowing any failure and answering [fallback] instead.
  /// Reported in debug so a genuinely broken store is still visible in dev —
  /// message only, because a failing store repeats per operation and a stack
  /// per call buries the rest of the log.
  Future<T> _guard<T>(Future<T> Function() op, T fallback) async {
    try {
      return await op();
    } catch (error) {
      assert(() {
        debugPrint('[DiscoverLocalStore] $error');
        return true;
      }());
      return fallback;
    }
  }

  Future<List<String>> _readList(String key) => _guard(
    () async => await _prefs.getStringList(key) ?? const <String>[],
    const <String>[],
  );

  /// Puts [value] at the front, drops any case-insensitive duplicate, and
  /// trims to [cap].
  Future<void> _pushCapped(String key, String value, int cap) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    await _guard(() async {
      final current = await _prefs.getStringList(key) ?? const <String>[];
      final folded = trimmed.toLowerCase();
      final next = <String>[
        trimmed,
        ...current.where((e) => e.toLowerCase() != folded),
      ];
      await _prefs.setStringList(
        key,
        next.length > cap ? next.sublist(0, cap) : next,
      );
    }, null);
  }

  @override
  Future<Map<String, int>> seenStoryVersions() => _guard(() async {
    final raw = await _prefs.getString(_kSeenStories);
    if (raw == null || raw.isEmpty) return const <String, int>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const <String, int>{};
    // A value written by a newer build could be any shape; keep the entries
    // that still parse and ignore the rest rather than dropping the map.
    return <String, int>{
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is int)
          entry.key as String: entry.value as int,
    };
  }, const <String, int>{});

  @override
  Future<void> markStorySeen(String storyId, int contentVersion) async {
    if (storyId.isEmpty) return;
    await _guard(() async {
      final current = await seenStoryVersions();
      // Never move a story BACKWARDS: a late write from a stale in-flight
      // viewer must not make an already-seen story look fresh again.
      final known = current[storyId];
      if (known != null && known >= contentVersion) return;
      await _prefs.setString(
        _kSeenStories,
        jsonEncode({...current, storyId: contentVersion}),
      );
    }, null);
  }

  @override
  Future<List<String>> recentSearches() => _readList(_kRecentSearches);

  @override
  Future<void> addRecentSearch(String term) =>
      _pushCapped(_kRecentSearches, term, maxRecentSearches);

  @override
  Future<void> clearRecentSearches() =>
      _guard(() => _prefs.remove(_kRecentSearches), null);

  @override
  Future<List<String>> recentlyViewedProductIds() =>
      _readList(_kRecentlyViewed);

  @override
  Future<void> addRecentlyViewedProduct(String productId) =>
      _pushCapped(_kRecentlyViewed, productId, maxRecentlyViewed);

  @override
  Future<void> clearRecentlyViewed() =>
      _guard(() => _prefs.remove(_kRecentlyViewed), null);

  @override
  Future<(String?, String?, int)> shoppingScope() => _guard(() async {
    final raw = await _prefs.getString(_kShoppingScope);
    if (raw == null || raw.isEmpty) return (null, null, 0);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return (null, null, 0);
    return (
      decoded['country'] as String?,
      decoded['currency'] as String?,
      decoded['profile'] is int ? decoded['profile'] as int : 0,
    );
  }, (null, null, 0));

  @override
  Future<void> setShoppingScope(
    String? country,
    String? currency,
    int profileVersion,
  ) => _guard(
    () => _prefs.setString(
      _kShoppingScope,
      jsonEncode({
        'country': country,
        'currency': currency,
        'profile': profileVersion,
      }),
    ),
    null,
  );

  @override
  Future<void> clearAll() => _guard(() async {
    for (final key in const [
      _kSeenStories,
      _kRecentSearches,
      _kRecentlyViewed,
      _kShoppingScope,
    ]) {
      await _prefs.remove(key);
    }
  }, null);
}

/// The app-wide store. Overridden in tests with an in-memory fake.
final discoverLocalStoreProvider = Provider<DiscoverLocalStore>(
  (ref) => SharedPrefsDiscoverLocalStore(),
);
