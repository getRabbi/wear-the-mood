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
