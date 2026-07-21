import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/auth/auth_providers.dart';

/// Device-local collections (CLAUDE.md guardrail — favorites & saved looks are
/// UI-only, no schema change). Persisted in encrypted storage so they survive
/// restarts, exposed as a plain `Set<String>` so widgets can read membership
/// synchronously (no AsyncValue ceremony for a toggle).
/// Injectable so tests can supply an in-memory / delayed fake (account-isolation
/// + async-race regression tests).
final collectionsStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

/// The device-storage namespace for the CURRENTLY authenticated user, or
/// `guest` when signed out. **Account isolation (§11):** every local-collection
/// key is prefixed with this, so one account's favorites / saved looks can NEVER
/// load under another account on the same phone. It changes on sign-in / out /
/// account switch, so every store below rebuilds and reloads under the new
/// namespace (empty until its own key is read).
String _scope(String? uid) => uid ?? 'guest';
String _scopedKey(String? uid, String name) => 'fashionos.${_scope(uid)}.$name';

/// The pre-namespacing GLOBAL keys. They caused the cross-account leak (Account
/// A's saved look surfaced in Account B's Today's Look). Nothing reads them
/// anymore; [purgeLegacyGlobalCollections] deletes them once so the leaked data
/// can never resurface. Ownership is unprovable, so they are NOT migrated.
const _legacyGlobalKeys = <String>[
  'fashionos.favorites',
  'fashionos.saved_looks',
  'fashionos.outfit_favorites',
  'fashionos.saved_look_records',
];

/// One-time removal of the legacy global collection keys (account-isolation
/// hardening). Idempotent + best-effort; guarded by a flag so it runs once.
Future<void> purgeLegacyGlobalCollections(FlutterSecureStorage storage) async {
  const purgedFlag = 'fashionos.legacy_collections_purged';
  try {
    if (await storage.read(key: purgedFlag) == '1') return;
    for (final key in _legacyGlobalKeys) {
      await storage.delete(key: key);
    }
    await storage.write(key: purgedFlag, value: '1');
  } catch (_) {
    // Best-effort; a failure just means we retry the purge next launch.
  }
}

/// Provider wrapper so the app can trigger the one-time purge at startup.
final purgeLegacyCollectionsProvider = Provider<Future<void> Function()>(
  (ref) => () => purgeLegacyGlobalCollections(ref.read(collectionsStorageProvider)),
);

class _StringSetStore extends Notifier<Set<String>> {
  _StringSetStore(this._name);

  /// The unqualified collection name (e.g. `favorites`); the full storage key is
  /// namespaced per user in [build].
  final String _name;
  String _key = '';

  @override
  Set<String> build() {
    // Rebuilds on sign-in/out/account switch → resets to empty, then reloads
    // THIS user's namespaced key. A guest and each user get separate storage.
    final uid = ref.watch(authUserIdProvider);
    _key = _scopedKey(uid, _name);
    _load(_scope(uid));
    return <String>{};
  }

  Future<void> _load(String forScope) async {
    try {
      final raw = await ref.read(collectionsStorageProvider).read(key: _key);
      // The account may have changed while we were reading — discard a stale
      // load so Account A's data can never land in Account B's state (§11 race).
      if (_scope(ref.read(authUserIdProvider)) != forScope) return;
      if (raw == null || raw.isEmpty) return;
      state = (jsonDecode(raw) as List).cast<String>().toSet();
    } catch (_) {
      // Best-effort; a missing/corrupt store just means "no items yet".
    }
  }

  void _persist() {
    ref
        .read(collectionsStorageProvider)
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

/// Favorited wardrobe item ids (per-user, §11).
final closetFavoritesProvider = NotifierProvider<_StringSetStore, Set<String>>(
  () => _StringSetStore('favorites'),
);

/// Saved look / post ids the user kept (per-user, §11).
final savedLooksProvider = NotifierProvider<_StringSetStore, Set<String>>(
  () => _StringSetStore('saved_looks'),
);

/// Favorited outfit ids — the Outfits tab heart (per-user, §11).
final outfitFavoritesProvider = NotifierProvider<_StringSetStore, Set<String>>(
  () => _StringSetStore('outfit_favorites'),
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
/// encrypted storage so they survive restarts. Namespaced per user (§11).
class _SavedLooksStore extends Notifier<List<SavedLook>> {
  String _key = '';

  @override
  List<SavedLook> build() {
    final uid = ref.watch(authUserIdProvider);
    _key = _scopedKey(uid, 'saved_look_records');
    _load(_scope(uid));
    return const [];
  }

  Future<void> _load(String forScope) async {
    try {
      final raw = await ref.read(collectionsStorageProvider).read(key: _key);
      if (_scope(ref.read(authUserIdProvider)) != forScope) return; // stale — discard
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      state = [for (final m in list) SavedLook.fromJson(m)];
    } catch (_) {
      // Best-effort; a missing/corrupt store just means "no saved looks yet".
    }
  }

  void _persist() {
    ref
        .read(collectionsStorageProvider)
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
