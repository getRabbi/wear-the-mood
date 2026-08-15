import 'package:flutter/foundation.dart';

import '../../../shared/utils/uuid.dart';

/// Try-on session engine.
enum TryOnSessionMode { twoD, ai }

/// One positioned garment/accessory layer in a try-on (the unit of the 2D Outfit
/// Stack editor and the AI selection). Transforms are normalized: [x]/[y] are
/// offsets from the canvas centre, [scale]/[rotation]/[opacity] are applied about
/// the layer centre, [zIndex] is the stacking order.
@immutable
class TryOnLayer {
  const TryOnLayer({
    required this.id,
    required this.imageUrl,
    this.category,
    this.wardrobeItemId,
    this.productId,
    this.x = 0,
    this.y = 0,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,
    this.zIndex = 0,
    this.flipX = false,
  });

  factory TryOnLayer.fromSource({
    required String imageUrl,
    String? category,
    String? wardrobeItemId,
    String? productId,
    int zIndex = 0,
  }) => TryOnLayer(
    id: uuidV4(),
    imageUrl: imageUrl,
    category: category,
    wardrobeItemId: wardrobeItemId,
    productId: productId,
    zIndex: zIndex,
  );

  final String id;
  final String imageUrl;

  /// The piece's free-text category, carried from wherever it was picked. It is
  /// what the AI render sends to the server as a HINT for a piece the backend
  /// holds no row for; for an owned item or a catalog product the server reads
  /// the real row instead. It also drives 2D auto-placement.
  final String? category;
  final String? wardrobeItemId;

  /// Set when the layer came from the catalog, so the server can look the
  /// product up and use its real category rather than guessing from the image.
  final String? productId;
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final double opacity;
  final int zIndex;
  final bool flipX;

  TryOnLayer copyWith({
    double? x,
    double? y,
    double? scale,
    double? rotation,
    double? opacity,
    int? zIndex,
    bool? flipX,
  }) => TryOnLayer(
    id: id,
    imageUrl: imageUrl,
    category: category,
    wardrobeItemId: wardrobeItemId,
    productId: productId,
    x: x ?? this.x,
    y: y ?? this.y,
    scale: scale ?? this.scale,
    rotation: rotation ?? this.rotation,
    opacity: opacity ?? this.opacity,
    zIndex: zIndex ?? this.zIndex,
    flipX: flipX ?? this.flipX,
  );
}

/// A reusable set of pieces + style metadata (the "outfit" a try-on builds).
class OutfitStack {
  OutfitStack({
    String? id,
    required this.items,
    this.title,
    this.styleTags = const [],
  }) : id = id ?? uuidV4();

  final String id;
  final List<TryOnLayer> items;
  final String? title;
  final List<String> styleTags;
}

/// One try-on session — a base photo + a set of layers, in 2D or AI mode.
class TryOnSession {
  TryOnSession({
    String? id,
    required this.basePhotoUrl,
    required this.mode,
    required this.selectedItems,
    this.status = 'draft', // draft | pending | processing | done | failed
    this.resultImageUrl,
    DateTime? createdAt,
  }) : id = id ?? uuidV4(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String basePhotoUrl;
  final TryOnSessionMode mode;
  final List<TryOnLayer> selectedItems;
  final String status;
  final String? resultImageUrl;
  final DateTime createdAt;
}
