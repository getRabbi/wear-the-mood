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
  }) = _WardrobeItem;

  const WardrobeItem._();

  factory WardrobeItem.fromJson(Map<String, dynamic> json) =>
      _$WardrobeItemFromJson(json);

  /// Best image to show in a grid/preview — the AI-enhanced cover once ready,
  /// else the background-removed cutout (§2.2), else the original.
  String? get displayImageUrl =>
      coverImageUrl ?? thumbnailUrl ?? cutoutUrl ?? imageUrl;

  /// True when [displayImageUrl] resolves to a background-removed, ALPHA-BEARING
  /// image rather than an ordinary photograph.
  ///
  /// This is the authoritative rule for cutout presentation — the single place
  /// that decides it. Derived only from model state: never from the URL text, a
  /// file extension, the storage host, a path name, or transparency guessed at
  /// runtime. Those all break the moment a signed URL or bucket layout changes.
  ///
  /// It mirrors [displayImageUrl] precedence exactly, because what matters is not
  /// "does a cutout exist" but "is the image we are about to draw a cutout":
  ///
  ///  * a user-chosen AI-enhanced cover wins in [displayImageUrl], and it is a
  ///    full photographic composition — NOT a cutout — so it keeps the decorative
  ///    tile face;
  ///  * anything other than `done` means the cutout is queued, processing or
  ///    failed, so [displayImageUrl] is still showing the ORIGINAL photo;
  ///  * `done` with neither a thumbnail nor a cutout URL is a legacy/incomplete
  ///    row whose [displayImageUrl] falls through to [imageUrl] — again the
  ///    original photo.
  ///
  /// Both candidates are safe to treat as transparent: the cutout itself is PNG
  /// RGBA, and the server thumbnail is WebP encoded from it with RGBA preserved
  /// (`make_thumbnail_webp`), so neither has been flattened onto a background.
  bool get displaysCutout {
    if (coverImageUrl != null) return false;
    if (cutoutStatus != 'done') return false;
    return thumbnailUrl != null || cutoutUrl != null;
  }

  /// The background-removal cutout is still being generated (§2.2).
  bool get isProcessingCutout =>
      cutoutStatus == 'queued' || cutoutStatus == 'processing';

  /// An AI Enhance job for this item is queued or running.
  bool get isEnhancing => aiStatus == 'queued' || aiStatus == 'processing';
}
