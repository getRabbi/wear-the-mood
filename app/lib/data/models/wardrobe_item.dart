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
    // The cover's own 512px rendition. Null on a row whose cover predates
    // thumbnail generation (and on a legacy Supabase object), in which case
    // [cardImageUrl] falls back to the full cover.
    @JsonKey(name: 'cover_thumbnail_url') String? coverThumbnailUrl,
    @JsonKey(name: 'ai_enhanced') @Default(false) bool aiEnhanced,
    @JsonKey(name: 'ai_status') String? aiStatus,
    @JsonKey(name: 'cutout_status') String? cutoutStatus,
    // ── try-on eligibility, straight from the server ─────────────────────────
    // The canonical role the API resolved from this item's own category, the
    // verdict that came with it, and the single boolean a surface needs.
    //
    // Before these existed the app had no way to know a piece was unrenderable:
    // it found out from a 422 AFTER the person tapped Try On, which is a dead
    // end rather than a question. Nullable/defaulted so a cached payload from an
    // older build still deserializes — and so does a test fixture.
    @JsonKey(name: 'canonical_category') String? canonicalCategory,
    @JsonKey(name: 'classification_status') String? classificationStatus,
    @JsonKey(name: 'try_on_ready') @Default(false) bool tryOnReady,
    @JsonKey(name: 'wear_count') @Default(0) int wearCount,
    @JsonKey(name: 'last_worn_at') DateTime? lastWornAt,
    // The closet's paging cursor: `GET /v1/wardrobe` orders newest-first on
    // this, so the oldest item on screen is what asks for the next page. The
    // server has always returned it; it was simply not mapped. Nullable so an
    // older cached payload (or a test fixture) still deserializes.
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _WardrobeItem;

  const WardrobeItem._();

  factory WardrobeItem.fromJson(Map<String, dynamic> json) =>
      _$WardrobeItemFromJson(json);

  /// Whether this piece needs somebody to say what it is before it can be worn.
  ///
  /// Deliberately NOT `!tryOnReady`. A belt is perfectly well categorised and
  /// simply cannot be rendered by today's provider — asking its owner to
  /// "choose a category" would be asking them to fix something that is not
  /// broken. This is only the case a person can actually resolve: the server
  /// could not read a role from the category at all.
  ///
  /// `try_on_ready` defaults to false on a payload that predates the field, so
  /// this requires a POSITIVE `needs_review` verdict rather than the absence of
  /// a positive one — an old cached item must not suddenly start nagging.
  bool get needsCategory => classificationStatus == 'needs_review';

  /// Best image to show at FULL size — the AI-enhanced cover once ready, else
  /// the background-removed cutout (§2.2), else the original.
  ///
  /// This is the detail-view image. Anything drawing a card should use
  /// [cardImageUrl] instead.
  String? get displayImageUrl =>
      coverImageUrl ?? thumbnailUrl ?? cutoutUrl ?? imageUrl;

  /// The same picture as [displayImageUrl], at card size.
  ///
  /// Identical precedence — so [displaysCutout] describes both, and a card and
  /// its detail view never show two different images — with each candidate
  /// swapped for its 512px rendition where the server has one.
  ///
  /// Only the COVER branch actually differs. The rest of the chain already
  /// leads with `thumbnailUrl`, so a card on an ordinary item was always
  /// asking for the small object; a card on an AI-enhanced item was asking for
  /// a full-resolution generated composition to fill roughly 80 dp, because the
  /// cover outranks the cutout's thumbnail and had no rendition of its own.
  ///
  /// Falls back to the full cover when there is no rendition yet, which is
  /// exactly the behaviour before this existed — never a blank card.
  String? get cardImageUrl => coverImageUrl != null
      ? (coverThumbnailUrl ?? coverImageUrl)
      : displayImageUrl;

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
