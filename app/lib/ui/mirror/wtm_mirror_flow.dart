import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/credits.dart';
import '../../data/models/wardrobe_item.dart';
import '../../features/tryon/models/studio_models.dart';
import '../../features/tryon/sample_garments.dart';

/// The three MoodMirror modes (board 05) mapped onto the REAL engines:
/// - [twoD] → the free on-device 2D outfit stack (no backend, no credits);
/// - [aiCouture] → the server AI render, standard quality (`stdCost` credits);
/// - [fullLook] → the server AI render in HD / Try-On Max (`hdCost` credits,
///   Pro Max — server-gated, mirrored client-side via [Credits.hdAllowed]).
enum WtmMirrorMode {
  twoD,
  aiCouture,
  fullLook;

  bool get isTwoD => this == WtmMirrorMode.twoD;
  bool get isAi => this != WtmMirrorMode.twoD;
  bool get hd => this == WtmMirrorMode.fullLook;

  /// Credits this mode spends (0 for 2D).
  int cost(Credits? credits) => switch (this) {
        twoD => 0,
        aiCouture => credits?.stdCost ?? 1,
        fullLook => credits?.hdCost ?? 4,
      };

  /// Whether the plan allows this mode at all (credits aside).
  bool allowed(Credits? credits) =>
      this != WtmMirrorMode.fullLook || (credits?.hdAllowed ?? false);
}

/// What the user has assembled across the three steps: the outfit stack (in
/// render order) and the chosen mode. Step 1's body photo comes from the
/// try-on photo gallery providers, not from here.
class WtmMirrorDraft {
  const WtmMirrorDraft({
    this.layers = const <TryOnLayer>[],
    this.mode = WtmMirrorMode.twoD,
  });

  final List<TryOnLayer> layers;
  final WtmMirrorMode mode;

  bool containsUrl(String url) => layers.any((l) => l.imageUrl == url);

  WtmMirrorDraft copyWith({List<TryOnLayer>? layers, WtmMirrorMode? mode}) =>
      WtmMirrorDraft(layers: layers ?? this.layers, mode: mode ?? this.mode);
}

/// Flow state shared by the MoodMirror steps. Kept (not autoDispose) so the
/// selection survives step navigation; [reset] clears it after a completed or
/// abandoned run re-enters step 1.
class WtmMirrorFlow extends Notifier<WtmMirrorDraft> {
  /// Matches the shipped studio's outfit-stack ceiling.
  static const maxGarments = 6;

  @override
  WtmMirrorDraft build() => const WtmMirrorDraft();

  /// Toggle an owned piece (prefers its cutout like the shipped preselect).
  /// Returns false when the piece has no usable image yet OR the stack is full
  /// — so the caller can explain why the tap did nothing (the max-pieces note).
  bool toggleItem(WardrobeItem item) {
    final url = item.cutoutUrl ?? item.imageUrl;
    if (url == null || url.isEmpty) return false;
    return _toggleUrl(url, category: item.category, wardrobeItemId: item.id);
  }

  /// Toggle a sample piece (activation path for an empty closet). Its category
  /// drives the 2D editor's auto-placement so pieces spread by type.
  bool toggleSample(SampleGarment garment) =>
      _toggleUrl(garment.imageUrl,
          category: garment.category, wardrobeItemId: null);

  /// Applies the toggle and reports whether the stack actually changed:
  /// removals always succeed; an add is refused (returns false) once the stack
  /// is at [maxGarments], leaving the current selection untouched.
  bool _toggleUrl(String url, {String? category, String? wardrobeItemId}) {
    final layers = [...state.layers];
    final index = layers.indexWhere((l) => l.imageUrl == url);
    if (index >= 0) {
      layers.removeAt(index);
    } else {
      if (layers.length >= maxGarments) return false;
      layers.add(TryOnLayer.fromSource(
        imageUrl: url,
        category: category,
        wardrobeItemId: wardrobeItemId,
        zIndex: layers.length,
      ));
    }
    state = state.copyWith(layers: layers);
    return true;
  }

  /// Seed the whole stack (preselect handoff — closet "Try It On", stylist P5).
  void setLayers(List<TryOnLayer> layers) =>
      state = state.copyWith(layers: layers.take(maxGarments).toList());

  void setMode(WtmMirrorMode mode) => state = state.copyWith(mode: mode);

  void reset() => state = const WtmMirrorDraft();
}

final wtmMirrorFlowProvider =
    NotifierProvider<WtmMirrorFlow, WtmMirrorDraft>(WtmMirrorFlow.new);
