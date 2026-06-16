import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/uuid.dart';
import '../tryon_mode.dart';

/// A locally-composited 2D try-on preview. Lives entirely on-device — no backend
/// call, no credits — and always carries mode `2d`.
class TwoDResult {
  TwoDResult({required this.bytes, DateTime? createdAt, String? id})
    : id = id ?? uuidV4(),
      createdAt = createdAt ?? DateTime.now();

  final String id;
  final Uint8List bytes;
  final DateTime createdAt;

  /// Result mode tag (always `2d`).
  String get mode => TryOnMode.twoD.id;
}

/// Session store of saved 2D previews (newest first). In-memory by design: 2D is
/// a free, instant preview engine — nothing is persisted server-side.
class TwoDResults extends Notifier<List<TwoDResult>> {
  @override
  List<TwoDResult> build() => const [];

  void add(TwoDResult result) => state = [result, ...state];

  void remove(String id) =>
      state = [for (final r in state) if (r.id != id) r];
}

final twoDResultsProvider =
    NotifierProvider<TwoDResults, List<TwoDResult>>(TwoDResults.new);

/// Initial placement of a garment over the body image, derived from its category
/// (the 2D engine's auto-placement). Returns the garment's width as a fraction of
/// the canvas width and the vertical centre as a fraction of the canvas height.
/// The user then fine-tunes with the manual editor.
({double widthFactor, double verticalCenter}) garmentPlacement(String? category) {
  final c = (category ?? '').toLowerCase();
  bool has(List<String> keys) => keys.any(c.contains);

  if (has(['glass', 'sunglass', 'eyewear'])) {
    return (widthFactor: 0.26, verticalCenter: 0.17); // near the eyes
  }
  // ── accessories (checked before garments so a scarf isn't treated as a top) ──
  if (has(['hijab', 'scarf', 'shawl', 'headscarf', 'veil'])) {
    return (widthFactor: 0.52, verticalCenter: 0.16); // head + shoulders
  }
  if (has(['hat', 'beanie', 'headband', 'turban'])) {
    return (widthFactor: 0.30, verticalCenter: 0.11); // crown of the head
  }
  if (has(['earring'])) {
    return (widthFactor: 0.10, verticalCenter: 0.18); // beside the face
  }
  if (has(['necklace', 'pendant', 'choker', 'chain'])) {
    return (widthFactor: 0.22, verticalCenter: 0.31); // upper chest
  }
  if (has(['watch', 'bracelet', 'wristband', 'cuff'])) {
    return (widthFactor: 0.12, verticalCenter: 0.62); // wrist
  }
  if (has(['belt'])) {
    return (widthFactor: 0.46, verticalCenter: 0.58); // waist
  }
  if (has(['shoe', 'sneaker', 'boot', 'heel', 'sandal', 'loafer', 'trainer'])) {
    return (widthFactor: 0.34, verticalCenter: 0.90); // near the feet
  }
  if (has(['bag', 'purse', 'tote', 'clutch', 'backpack', 'satchel'])) {
    return (widthFactor: 0.28, verticalCenter: 0.56); // at the side/hand
  }
  if (has(['pant', 'trouser', 'jean', 'short', 'skirt', 'legging', 'bottom',
        'chino', 'capri'])) {
    return (widthFactor: 0.46, verticalCenter: 0.68); // waist → legs
  }
  if (has(['dress', 'gown', 'jumpsuit', 'tunic', 'romper'])) {
    return (widthFactor: 0.56, verticalCenter: 0.54); // shoulders → lower
  }
  // Tops / unknown — shoulders / chest / torso.
  return (widthFactor: 0.56, verticalCenter: 0.40);
}
