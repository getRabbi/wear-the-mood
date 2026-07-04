import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/outfit.dart';

/// The Outfit Maker's working draft (board §3.19). Held in a keep-alive
/// provider (not widget state) so it survives tab switches and — critically —
/// so the outfit detail's "Edit" can seed it before routing to the composer.
///
/// Four positional slots (Top · Bottom · Layer · Extra) each hold one owned
/// wardrobe item id; the saved outfit is the non-empty ids in slot order.
class WtmComposerState {
  const WtmComposerState({
    this.editingId,
    this.name = '',
    this.slots = const [null, null, null, null],
  });

  /// Non-null when editing an existing outfit (Save → update, not create).
  final String? editingId;
  final String name;
  final List<String?> slots;

  static const slotCount = 4;

  List<String> get itemIds =>
      [for (final s in slots) if (s != null && s.isNotEmpty) s];

  bool get isEmpty => slots.every((s) => s == null);
  bool get isEditing => editingId != null;

  WtmComposerState copyWith({String? name, List<String?>? slots}) =>
      WtmComposerState(
        editingId: editingId,
        name: name ?? this.name,
        slots: slots ?? this.slots,
      );
}

class WtmComposerController extends Notifier<WtmComposerState> {
  @override
  WtmComposerState build() => const WtmComposerState();

  /// Fill [slot] with [itemId] — or clear it when the same piece is tapped again.
  void setSlot(int slot, String itemId) {
    final next = [...state.slots];
    next[slot] = next[slot] == itemId ? null : itemId;
    state = state.copyWith(slots: next);
  }

  void clearSlot(int slot) {
    final next = [...state.slots];
    next[slot] = null;
    state = state.copyWith(slots: next);
  }

  void setName(String name) => state = state.copyWith(name: name);

  /// Seed the composer from an existing outfit (the detail's "Edit").
  void loadForEdit(Outfit outfit) {
    final ids = outfit.itemIds.take(WtmComposerState.slotCount).toList();
    state = WtmComposerState(
      editingId: outfit.id,
      name: outfit.name ?? '',
      slots: [
        for (var i = 0; i < WtmComposerState.slotCount; i++)
          i < ids.length ? ids[i] : null,
      ],
    );
  }

  void reset() => state = const WtmComposerState();
}

final wtmOutfitComposerProvider =
    NotifierProvider<WtmComposerController, WtmComposerState>(
  WtmComposerController.new,
);
