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
    @JsonKey(name: 'created_at') DateTime? createdAt,
    // Carried into history so a shopping render reopened days later still
    // knows what it was of. Null for every ordinary look.
    TryOnSource? source,
  }) = _TryonResult;

  factory TryonResult.fromJson(Map<String, dynamic> json) =>
      _$TryonResultFromJson(json);
}
