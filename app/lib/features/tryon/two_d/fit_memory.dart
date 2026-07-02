import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A remembered manual placement for one garment on one body (Phase 4 — fit
/// memory). Offsets are stored NORMALIZED (a fraction of the canvas width/height)
/// so a saved fit maps back sensibly even if the canvas size differs slightly
/// next time; [aspect] records the canvas aspect it was captured at. Everything
/// here is local + free — no backend, no credits.
class FitPlacement {
  const FitPlacement({
    required this.nx,
    required this.ny,
    required this.scale,
    required this.rotation,
    required this.opacity,
    required this.flipX,
    required this.zIndex,
    required this.aspect,
    required this.updatedAt,
  });

  /// Manual x offset (from the auto-placement centre) as a fraction of canvas width.
  final double nx;

  /// Manual y offset (from the auto-placement centre) as a fraction of canvas height.
  final double ny;
  final double scale;
  final double rotation;
  final double opacity;
  final bool flipX;

  /// Stacking position at save time (best-effort; the editor's smart auto-order
  /// still drives multi-piece stacking on load).
  final int zIndex;

  /// Canvas aspect (w/h) the fit was captured at.
  final double aspect;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'nx': nx,
        'ny': ny,
        's': scale,
        'r': rotation,
        'o': opacity,
        'f': flipX,
        'z': zIndex,
        'a': aspect,
        't': updatedAt.millisecondsSinceEpoch,
      };

  static FitPlacement? fromJson(Object? raw) {
    if (raw is! Map) return null;
    double d(Object? v, double fallback) =>
        v is num ? v.toDouble() : fallback;
    int i(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return FitPlacement(
      nx: d(raw['nx'], 0),
      ny: d(raw['ny'], 0),
      scale: d(raw['s'], 1),
      rotation: d(raw['r'], 0),
      opacity: d(raw['o'], 1),
      flipX: raw['f'] == true,
      zIndex: i(raw['z'], 0),
      aspect: d(raw['a'], 0),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(i(raw['t'], 0)),
    );
  }
}

/// Minimal single-slot key/value the fit-memory store needs. Abstracted so tests
/// can supply an in-memory implementation instead of platform secure storage.
abstract class FitMemoryStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// Default store: one encrypted key in [FlutterSecureStorage] holding the whole
/// fit-memory blob (small JSON, so a single slot is plenty).
class SecureFitMemoryStore implements FitMemoryStore {
  const SecureFitMemoryStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _key = 'fashionos.fit_memory.v1';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

/// Local, free store of remembered 2D placements (Phase 4). The whole map lives
/// in one JSON blob; [saveAll] merges + prunes so it can't grow without bound.
class FitMemoryService {
  FitMemoryService(this._store);

  final FitMemoryStore _store;

  /// Keep at most this many remembered fits (newest by [FitPlacement.updatedAt]).
  static const _maxEntries = 400;

  /// Composite key for one garment on one body for one user. [itemId] must be a
  /// STABLE id (the wardrobe item id) — never a per-session layer id.
  static String keyFor({
    String? userId,
    required String bodyId,
    required String itemId,
  }) =>
      '${userId ?? 'anon'}|$bodyId|$itemId';

  /// Stable id for a body source: the photo URL without its (expiring) query
  /// string, or `mannequin` when there's no photo.
  static String normalizeBodyId(String bodyImageUrl) {
    final url = bodyImageUrl.trim();
    if (url.isEmpty) return 'mannequin';
    final q = url.indexOf('?');
    return q >= 0 ? url.substring(0, q) : url;
  }

  Future<Map<String, FitPlacement>> loadAll() async {
    final raw = await _store.read();
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      final entries = decoded is Map ? decoded['e'] : null;
      if (entries is! Map) return {};
      final out = <String, FitPlacement>{};
      entries.forEach((k, v) {
        final p = FitPlacement.fromJson(v);
        if (k is String && p != null) out[k] = p;
      });
      return out;
    } catch (_) {
      return {}; // corrupt blob → start clean, never crash the editor
    }
  }

  /// Merge [entries] into the store (overwriting matching keys), then prune to
  /// [_maxEntries] keeping the most recently updated.
  Future<void> saveAll(Map<String, FitPlacement> entries) async {
    if (entries.isEmpty) return;
    final merged = await loadAll();
    merged.addAll(entries);
    await _writeMap(merged);
  }

  Future<void> removeAll(Iterable<String> keys) async {
    final keySet = keys.toSet();
    if (keySet.isEmpty) return;
    final map = await loadAll();
    var changed = false;
    for (final k in keySet) {
      if (map.remove(k) != null) changed = true;
    }
    if (changed) await _writeMap(map);
  }

  Future<void> remove(String key) => removeAll([key]);

  Future<void> _writeMap(Map<String, FitPlacement> map) async {
    var pruned = map;
    if (map.length > _maxEntries) {
      final sorted = map.entries.toList()
        ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
      pruned = {for (final e in sorted.take(_maxEntries)) e.key: e.value};
    }
    final payload = {
      'v': 1,
      'e': {for (final e in pruned.entries) e.key: e.value.toJson()},
    };
    await _store.write(jsonEncode(payload));
  }
}

/// Injectable so tests can swap in an in-memory store (Phase 4).
final fitMemoryServiceProvider = Provider<FitMemoryService>(
  (_) => FitMemoryService(const SecureFitMemoryStore()),
);
