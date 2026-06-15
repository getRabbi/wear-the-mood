import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../data/models/wardrobe_item.dart';
import '../../../shared/utils/uuid.dart';
import 'closet_drawer.dart';

/// Local, encrypted persistence for the digital wardrobe (CLAUDE.md guardrail —
/// no backend migration, fully backward compatible). Drawers + the
/// item→drawer assignment map live on-device; existing closet items keep working
/// and unassigned items fall into "Unsorted" (or auto-collect by category).
final _drawerStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

class ClosetDrawersStore extends Notifier<List<ClosetDrawer>> {
  static const _key = 'fashionos.drawers.v1';

  @override
  List<ClosetDrawer> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final raw = await ref.read(_drawerStorageProvider).read(key: _key);
      if (raw == null || raw.isEmpty) {
        // First run — seed the default wardrobe.
        state = defaultDrawers();
        _persist();
        return;
      }
      final list = (jsonDecode(raw) as List)
          .map((e) => ClosetDrawer.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      state = list;
    } catch (_) {
      state = defaultDrawers();
    }
  }

  void _persist() {
    ref
        .read(_drawerStorageProvider)
        .write(
          key: _key,
          value: jsonEncode(state.map((d) => d.toJson()).toList()),
        )
        .ignore();
  }

  int get _nextSort =>
      state.isEmpty ? 0 : state.map((d) => d.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

  ClosetDrawer create({
    required String name,
    required DrawerIconKind iconKind,
    required int accentValue,
    ClosetDrawerKind kind = ClosetDrawerKind.drawer,
  }) {
    final drawer = ClosetDrawer(
      id: uuidV4(),
      name: name,
      iconKind: iconKind,
      accentValue: accentValue,
      kind: kind,
      sortOrder: _nextSort,
    );
    state = [...state, drawer];
    _persist();
    return drawer;
  }

  void update(
    String id, {
    String? name,
    DrawerIconKind? iconKind,
    int? accentValue,
    ClosetDrawerKind? kind,
  }) {
    state = [
      for (final d in state)
        if (d.id == id)
          d.copyWith(
            name: name,
            iconKind: iconKind,
            accentValue: accentValue,
            kind: kind,
          )
        else
          d,
    ];
    _persist();
  }

  void delete(String id) {
    state = [for (final d in state) if (d.id != id) d];
    _persist();
    // Drop any assignments pointing at the removed drawer.
    ref.read(closetAssignmentsProvider.notifier).removeDrawer(id);
  }

  ClosetDrawer? byId(String id) {
    for (final d in state) {
      if (d.id == id) return d;
    }
    return null;
  }
}

final closetDrawersProvider =
    NotifierProvider<ClosetDrawersStore, List<ClosetDrawer>>(
  ClosetDrawersStore.new,
);

/// item id → drawer id. Explicit assignments override category auto-collection.
class ClosetAssignmentsStore extends Notifier<Map<String, String>> {
  static const _key = 'fashionos.drawer_assignments.v1';

  @override
  Map<String, String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final raw = await ref.read(_drawerStorageProvider).read(key: _key);
      if (raw == null || raw.isEmpty) return;
      state = (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      // best-effort
    }
  }

  void _persist() {
    ref
        .read(_drawerStorageProvider)
        .write(key: _key, value: jsonEncode(state))
        .ignore();
  }

  void assign(String itemId, String drawerId) {
    state = {...state, itemId: drawerId};
    _persist();
  }

  void unassign(String itemId) {
    if (!state.containsKey(itemId)) return;
    state = {...state}..remove(itemId);
    _persist();
  }

  /// Removes all assignments to a deleted drawer.
  void removeDrawer(String drawerId) {
    final next = {
      for (final e in state.entries)
        if (e.value != drawerId) e.key: e.value,
    };
    if (next.length != state.length) {
      state = next;
      _persist();
    }
  }

  String? drawerOf(String itemId) => state[itemId];
}

final closetAssignmentsProvider =
    NotifierProvider<ClosetAssignmentsStore, Map<String, String>>(
  ClosetAssignmentsStore.new,
);

// ───────────────────────────────────────────────── pure helpers ──────────────

/// Items that belong to [drawer]: explicitly assigned items, plus unassigned
/// items whose category matches the drawer's keywords (so existing closets
/// populate immediately without any manual sorting).
List<WardrobeItem> itemsInDrawer(
  ClosetDrawer drawer,
  List<WardrobeItem> items,
  Map<String, String> assignments,
) {
  return items.where((i) {
    final assigned = assignments[i.id];
    if (assigned != null) return assigned == drawer.id;
    if (drawer.keywords.isEmpty) return false;
    final c = (i.category ?? '').toLowerCase();
    return c.isNotEmpty && drawer.keywords.any(c.contains);
  }).toList();
}

/// Items with no drawer: not explicitly assigned and not matched by any drawer's
/// keywords (e.g. missing/odd categories). These surface in "Unsorted".
List<WardrobeItem> unsortedItems(
  List<WardrobeItem> items,
  List<ClosetDrawer> drawers,
  Map<String, String> assignments,
) {
  return items.where((i) {
    if (assignments[i.id] != null) return false;
    final c = (i.category ?? '').toLowerCase();
    if (c.isEmpty) return true;
    return !drawers.any((d) => d.keywords.any(c.contains));
  }).toList();
}

/// Best drawer for a new item, by category keyword or drawer name (used by
/// Add Item). Matches both "Tops"→Tops and "Bottoms"→Pants.
ClosetDrawer? suggestDrawer(String? category, List<ClosetDrawer> drawers) {
  final c = (category ?? '').toLowerCase();
  if (c.isEmpty) return null;
  for (final d in drawers) {
    if (d.keywords.any(c.contains)) return d;
    final n = d.name.toLowerCase();
    if (n == c || c.contains(n) || n.contains(c)) return d;
  }
  return null;
}
