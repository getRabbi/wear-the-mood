import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'wardrobe_item.freezed.dart';
part 'wardrobe_item.g.dart';

/// A digitized piece the user owns (CLAUDE.md §5, "digital almira"). JSON keys
/// match the `wardrobe_items` table so this maps the future `GET /v1/wardrobe`
/// response directly. UI-only for now (a later phase wires the backend).
@freezed
abstract class WardrobeItem with _$WardrobeItem {
  const factory WardrobeItem({
    required String id,
    String? title,
    String? category,
    String? color, // free-text color from the vision tagger (e.g. "navy")
    @Default(<String>[]) List<String> tags,
    @JsonKey(name: 'image_url') String? imageUrl,
    @JsonKey(name: 'cutout_url') String? cutoutUrl,
    @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
    // AI Enhance (BUILD_PROMPT_PRO_PROMAX.md): a signed URL to the catalog-ready
    // cover once ready, plus the enhance job state for the "Enhancing…" badge.
    @JsonKey(name: 'cover_image_url') String? coverImageUrl,
    @JsonKey(name: 'ai_enhanced') @Default(false) bool aiEnhanced,
    @JsonKey(name: 'ai_status') String? aiStatus,
    @JsonKey(name: 'cutout_status') String? cutoutStatus,
    @JsonKey(name: 'wear_count') @Default(0) int wearCount,
    @JsonKey(name: 'last_worn_at') DateTime? lastWornAt,
    // Optimistic-add only: the locally-picked JPEG shown INSTANTLY in the closet
    // while the real upload + processing happen in the background. Never
    // (de)serialized — it lives only until the server-backed cutout is ready.
    @JsonKey(includeFromJson: false, includeToJson: false) Uint8List? localBytes,
    // Stable UI identity that survives the temp→real id swap on reconcile, so the
    // grid tile is never destroyed/recreated (which replayed the entrance
    // animation = the "vanishes then reappears" flicker). Transient.
    @JsonKey(includeFromJson: false, includeToJson: false) String? clientKey,
  }) = _WardrobeItem;

  const WardrobeItem._();

  factory WardrobeItem.fromJson(Map<String, dynamic> json) =>
      _$WardrobeItemFromJson(json);

  /// Best image to show in a grid/preview — the AI-enhanced cover once ready,
  /// else the background-removed cutout (§2.2), else the original.
  String? get displayImageUrl =>
      coverImageUrl ?? thumbnailUrl ?? cutoutUrl ?? imageUrl;

  /// The background-removal cutout is still being generated (§2.2).
  bool get isProcessingCutout =>
      cutoutStatus == 'queued' || cutoutStatus == 'processing';

  /// An AI Enhance job for this item is queued or running.
  bool get isEnhancing => aiStatus == 'queued' || aiStatus == 'processing';

  /// A background-removed / enhanced image is ready to display over the raw shot.
  String? get processedImageUrl => coverImageUrl ?? cutoutUrl;

  /// This piece is still uploading (optimistic add) — shown from local bytes,
  /// no server row yet.
  bool get isUploading => localBytes != null && (imageUrl == null || imageUrl!.isEmpty);

  /// Stable widget key for grids/lists — survives the temp→real id swap so the
  /// tile is preserved (no re-animation / image reload) across reconcile.
  String get gridKey => clientKey ?? id;
}
