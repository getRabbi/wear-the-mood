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
    @JsonKey(name: 'cutout_status') String? cutoutStatus,
    @JsonKey(name: 'wear_count') @Default(0) int wearCount,
    @JsonKey(name: 'last_worn_at') DateTime? lastWornAt,
  }) = _WardrobeItem;

  const WardrobeItem._();

  factory WardrobeItem.fromJson(Map<String, dynamic> json) =>
      _$WardrobeItemFromJson(json);

  /// Best image to show in a grid/preview — the background-removed cutout once
  /// ready (§2.2), else the original.
  String? get displayImageUrl => thumbnailUrl ?? cutoutUrl ?? imageUrl;

  /// The background-removal cutout is still being generated (§2.2).
  bool get isProcessingCutout =>
      cutoutStatus == 'queued' || cutoutStatus == 'processing';
}
