import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/models/product.dart';

/// Offline cache for the UNFILTERED FIRST PAGE of the Discover product feed
/// (DISCOVER spec §23 "cache first feed page", §24 offline).
///
/// Deliberately narrow. A filtered page or a page 2 is a transient view of a
/// query, not something the app should promise offline, and caching them would
/// multiply the invalidation problem for no user benefit.
///
/// **What is stored:** the validated raw response envelope — the exact JSON map
/// the API returned, kept only after it parsed cleanly into a [ProductPage].
/// Not `Product.toJson()`: this project generates serializers with
/// `explicit_to_json` off, so a nested `Money` or `MerchantSummary` would be
/// written as an object rather than a map and would fail to read back. Storing
/// what the server actually said sidesteps that entirely and keeps the cache
/// forward-compatible with fields this build does not know about.
///
/// **What is never stored:** auth tokens, body-photo or closet imagery,
/// affiliate references, or any private user content. The product feed is
/// public catalog data; that is the only reason it is safe to write to disk at
/// all (§36).

/// Cache format. Bump to abandon an incompatible envelope — an older file then
/// simply fails identity and is ignored, with no migration to write.
const discoverFeedCacheSchema = 1;

/// How long a cached page is treated as current.
const discoverFeedFreshTtl = Duration(hours: 6);

/// The outer limit for offline use. Past this the page is not a product feed
/// any more — prices and availability have had too long to move — so it is
/// dropped rather than shown with a caveat.
const discoverFeedMaxStale = Duration(hours: 72);

/// Ceiling on the file. A page is ~20 products; anything approaching this is a
/// server bug or a tampered file, and either way is not worth parsing.
const discoverFeedCacheMaxBytes = 512 * 1024;

/// Identity of a cached page. A cache entry is only usable when EVERY field
/// matches the current request context.
///
/// The user scope is what stops one account being served another's feed — the
/// most important field here, because saved flags and match reasons are
/// per-user. Country and currency are included because they change which
/// products are servable at all; the profile version because a preference
/// change re-ranks everything.
@immutable
class DiscoverFeedCacheKey {
  const DiscoverFeedCacheKey({
    required this.userScope,
    this.country,
    this.currency,
    this.profileVersion = 0,
    this.schema = discoverFeedCacheSchema,
  });

  /// Stable per-account identifier. Signed out is its own scope, so a
  /// signed-out browse never reads a signed-in cache.
  final String userScope;
  final String? country;
  final String? currency;

  /// Bumped by the app whenever shopping preferences change.
  final int profileVersion;
  final int schema;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'user': userScope,
    'country': country,
    'currency': currency,
    'profile': profileVersion,
  };

  static DiscoverFeedCacheKey? fromJson(Object? json) {
    if (json is! Map) return null;
    final user = json['user'];
    final schema = json['schema'];
    if (user is! String || schema is! int) return null;
    return DiscoverFeedCacheKey(
      userScope: user,
      country: json['country'] as String?,
      currency: json['currency'] as String?,
      profileVersion: json['profile'] is int ? json['profile'] as int : 0,
      schema: schema,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoverFeedCacheKey &&
      other.userScope == userScope &&
      other.country == country &&
      other.currency == currency &&
      other.profileVersion == profileVersion &&
      other.schema == schema;

  @override
  int get hashCode =>
      Object.hash(userScope, country, currency, profileVersion, schema);
}

/// How current a cache hit is.
enum DiscoverCacheFreshness {
  /// Within [discoverFeedFreshTtl] — safe to show immediately, refresh behind.
  fresh,

  /// Past the TTL but within [discoverFeedMaxStale] — offline fallback only,
  /// and the UI must say so.
  stale,
}

@immutable
class DiscoverFeedCacheEntry {
  const DiscoverFeedCacheEntry({
    required this.page,
    required this.cachedAt,
    required this.freshness,
  });

  final ProductPage page;
  final DateTime cachedAt;
  final DiscoverCacheFreshness freshness;

  bool get isFresh => freshness == DiscoverCacheFreshness.fresh;
}

/// The cache contract. Injectable so the feed can be tested without a disk.
abstract interface class DiscoverFeedCache {
  /// The cached page for [key], or null when there is nothing usable —
  /// missing, corrupt, wrong identity, or older than [discoverFeedMaxStale].
  Future<DiscoverFeedCacheEntry?> read(DiscoverFeedCacheKey key);

  /// Stores [response] — the RAW, already-validated API map.
  Future<void> write(DiscoverFeedCacheKey key, Map<String, dynamic> response);

  /// Drops the cache. Called on logout and account switch.
  Future<void> clear();
}

/// A single JSON file in the app-private support directory.
///
/// Support rather than the temporary directory: the OS may evict a cache dir
/// whenever it likes, and losing this file exactly when the user is offline
/// would defeat its only purpose.
class FileDiscoverFeedCache implements DiscoverFeedCache {
  FileDiscoverFeedCache({
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _now = clock ?? DateTime.now;

  final Future<Directory> Function() _directory;
  final DateTime Function() _now;

  static const fileName = 'discover_feed_page1.v1.json';

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$fileName');

  /// Every entry point is wrapped: the cache is an optimization, and an
  /// optimization that can take down a browsing surface is a liability. A
  /// failure answers [fallback] and is reported only in debug.
  Future<T> _guard<T>(Future<T> Function() op, T fallback, String what) async {
    try {
      return await op();
    } catch (error) {
      assert(() {
        debugPrint('[DiscoverFeedCache] $what failed: $error');
        return true;
      }());
      return fallback;
    }
  }

  @override
  Future<DiscoverFeedCacheEntry?> read(DiscoverFeedCacheKey key) => _guard(
    () async {
      final file = await _file();
      if (!await file.exists()) return null;

      // Check the size before reading: a huge or tampered file should not be
      // pulled into memory just to be rejected.
      if (await file.length() > discoverFeedCacheMaxBytes) {
        await _delete(file);
        return null;
      }

      // Anything unreadable from here on DELETES the file rather than just
      // returning a miss. A corrupt or truncated file that is merely skipped
      // is re-read and re-fails on every launch, and the cache never heals
      // itself; removing it means the next successful fetch repairs it.
      final Object? decoded;
      try {
        decoded = jsonDecode(await file.readAsString());
      } catch (_) {
        await _delete(file);
        return null;
      }
      if (decoded is! Map<String, dynamic>) {
        await _delete(file);
        return null;
      }

      // Identity first. A cache written for another account, country,
      // currency, profile version or schema is not a miss to be repaired —
      // it is data that must never be shown here.
      if (DiscoverFeedCacheKey.fromJson(decoded['key']) != key) return null;

      final cachedAt = DateTime.tryParse('${decoded['cached_at']}');
      final payload = decoded['payload'];
      if (cachedAt == null || payload is! Map<String, dynamic>) {
        await _delete(file);
        return null;
      }

      final age = _now().difference(cachedAt);
      // A negative age means the clock moved backwards (timezone change,
      // manual clock set). Treat it as unusable rather than infinitely
      // fresh.
      if (age.isNegative || age > discoverFeedMaxStale) {
        await _delete(file);
        return null;
      }

      // Parsed last, so a payload this build cannot read is discarded rather
      // than thrown at the feed — and removed, so it is not re-parsed and
      // re-rejected on every launch.
      final ProductPage page;
      try {
        page = ProductPage.fromJson(payload);
      } catch (_) {
        await _delete(file);
        return null;
      }
      return DiscoverFeedCacheEntry(
        page: page,
        cachedAt: cachedAt,
        freshness: age <= discoverFeedFreshTtl
            ? DiscoverCacheFreshness.fresh
            : DiscoverCacheFreshness.stale,
      );
    },
    null,
    'read',
  );

  @override
  Future<void> write(
    DiscoverFeedCacheKey key,
    Map<String, dynamic> response,
  ) => _guard(
    () async {
      final body = jsonEncode({
        'key': key.toJson(),
        'cached_at': _now().toIso8601String(),
        'payload': response,
      });
      // Refuse to write something we would refuse to read.
      if (body.length > discoverFeedCacheMaxBytes) return;

      final file = await _file();
      await file.parent.create(recursive: true);

      // Atomic: write a temp file, then rename over the target. A rename is
      // atomic on both platforms, so a crash or a kill mid-write leaves either
      // the previous good file or no file — never a half-written one that would
      // read back as corrupt.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(body, flush: true);
      await temp.rename(file.path);
    },
    null,
    'write',
  );

  @override
  Future<void> clear() =>
      _guard(() async => _delete(await _file()), null, 'clear');

  Future<void> _delete(File file) async {
    if (await file.exists()) await file.delete();
  }
}

final discoverFeedCacheProvider = Provider<DiscoverFeedCache>(
  (ref) => FileDiscoverFeedCache(),
);
