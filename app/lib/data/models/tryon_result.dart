import 'package:freezed_annotation/freezed_annotation.dart';

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
  }) = _TryonResult;

  factory TryonResult.fromJson(Map<String, dynamic> json) =>
      _$TryonResultFromJson(json);
}
