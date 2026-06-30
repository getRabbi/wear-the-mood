import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated_image.freezed.dart';
part 'generated_image.g.dart';

/// One saved AI output (AI Looks gallery) — an enhanced item, a catalog model
/// shot, or a try-on result (BUILD_PROMPT_PRO_PROMAX.md). `outputUrl` is a
/// short-lived signed URL minted by the backend.
@freezed
abstract class GeneratedImage with _$GeneratedImage {
  const factory GeneratedImage({
    required String id,
    required String type, // enhanced_item | catalog_model | tryon_result
    @JsonKey(name: 'output_url') String? outputUrl,
    @JsonKey(name: 'source_item_id') String? sourceItemId,
    @JsonKey(name: 'is_ai_generated') @Default(true) bool isAiGenerated,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _GeneratedImage;

  factory GeneratedImage.fromJson(Map<String, dynamic> json) =>
      _$GeneratedImageFromJson(json);
}
