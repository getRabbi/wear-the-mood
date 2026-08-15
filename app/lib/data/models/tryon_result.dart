import 'package:freezed_annotation/freezed_annotation.dart';

import 'tryon_source.dart';

part 'tryon_result.freezed.dart';
part 'tryon_result.g.dart';

/// One saved try-on result for the history view (CLAUDE.md §8). `resultImageUrl`
/// is a short-lived signed URL the backend mints from our private storage.
@freezed
abstract class TryonResult with _$TryonResult {
  const factory TryonResult({
    required String id,
    @JsonKey(name: 'result_image_url') String? resultImageUrl,
    // The 512px rendition for the history grid. Null for a render stored before
    // thumbnails were generated and not yet backfilled, and for a legacy
    // Supabase object — [cardImageUrl] then falls back to the full render.
    @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    // Carried into history so a shopping render reopened days later still
    // knows what it was of. Null for every ordinary look.
    TryOnSource? source,
  }) = _TryonResult;

  const TryonResult._();

  factory TryonResult.fromJson(Map<String, dynamic> json) =>
      _$TryonResultFromJson(json);

  /// What a three-across history tile should request.
  ///
  /// A try-on render is a full-frame image of a person — the largest thing the
  /// app stores per user — and the grid draws it at roughly a third of the
  /// screen width. Never a blank tile: without a rendition this is the render
  /// itself, exactly as before.
  String? get cardImageUrl => thumbnailUrl ?? resultImageUrl;
}
