import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local collections (CLAUDE.md guardrail — favorites & saved looks are
/// UI-only, no schema change). Persisted in encrypted storage so they survive
/// restarts, exposed as a plain `Set<String>` so widgets can read membership
/// synchronously (no AsyncValue ceremony for a toggle).
final _collectionsStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

class _StringSetStore extends Notifier<Set<String>> {
  _StringSetStore(this._key);

  final String _key;

  @override
  Set<String> build() {
    _load();
    return <String>{};
  }

  Future<void> _load() async {
    try {
      final raw = await ref.read(_collectionsStorageProvider).read(key: _key);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<String>();
      state = list.toSet();
    } catch (_) {
      // Best-effort; a missing/corrupt store just means "no items yet".
    }
  }

  void _persist() {
    ref
        .read(_collectionsStorageProvider)
        .write(key: _key, value: jsonEncode(state.toList()))
        .ignore();
  }

  bool contains(String id) => state.contains(id);

  void toggle(String id) {
    final next = {...state};
    if (!next.add(id)) next.remove(id);
    state = next;
    _persist();
  }

  void add(String id) {
    if (state.contains(id)) return;
    state = {...state, id};
    _persist();
  }

  void remove(String id) {
    if (!state.contains(id)) return;
    state = {...state}..remove(id);
    _persist();
  }
}

/// Favorited wardrobe item ids.
final closetFavoritesProvider = NotifierProvider<_StringSetStore, Set<String>>(
  () => _StringSetStore('fashionos.favorites'),
);

/// Saved look / post ids (try-on results + community looks the user kept).
final savedLooksProvider = NotifierProvider<_StringSetStore, Set<String>>(
  () => _StringSetStore('fashionos.saved_looks'),
);

/// Favorited outfit ids (the Outfits tab heart) — local, no schema change.
final outfitFavoritesProvider = NotifierProvider<_StringSetStore, Set<String>>(
  () => _StringSetStore('fashionos.outfit_favorites'),
);

/// A try-on result the user saved to their Looks (local, UI-only — same
/// guardrail as [savedLooksProvider]). Stores a **durable, publicly-readable**
/// image URL: the result is re-uploaded to durable storage before saving, never
/// an expiring signed URL (§8), so it renders in Looks across restarts.
class SavedLook {
  const SavedLook({
    required this.id,
    required this.imageUrl,
    required this.createdAt,
  });

  final String id;
  final String imageUrl;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'image_url': imageUrl,
    'created_at': createdAt.toIso8601String(),
  };

  factory SavedLook.fromJson(Map<String, dynamic> json) => SavedLook(
    id: json['id'] as String,
    imageUrl: json['image_url'] as String,
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
  );
}

/// Persisted list of saved try-on looks (newest first). Backs the Looks/Saved
/// tab alongside saved community posts. Records are kept as a JSON list in
/// encrypted storage so they survive restarts.
class _SavedLooksStore extends Notifier<List<SavedLook>> {
  static const _key = 'fashionos.saved_look_records';

  @override
  List<SavedLook> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final raw = await ref.read(_collectionsStorageProvider).read(key: _key);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      state = [for (final m in list) SavedLook.fromJson(m)];
    } catch (_) {
      // Best-effort; a missing/corrupt store just means "no saved looks yet".
    }
  }

  void _persist() {
    ref
        .read(_collectionsStorageProvider)
        .write(key: _key, value: jsonEncode([for (final l in state) l.toJson()]))
        .ignore();
  }

  bool contains(String id) => state.any((l) => l.id == id);

  /// Idempotent (§9): adding an already-saved id is a no-op, so a double-tap /
  /// retry never duplicates a look.
  void add(SavedLook look) {
    if (contains(look.id)) return;
    state = [look, ...state]; // newest first
    _persist();
  }

  void remove(String id) {
    if (!contains(id)) return;
    state = [for (final l in state) if (l.id != id) l];
    _persist();
  }
}

/// Saved try-on looks (durable URLs) — see [SavedLook].
final savedLookRecordsProvider =
    NotifierProvider<_SavedLooksStore, List<SavedLook>>(_SavedLooksStore.new);
