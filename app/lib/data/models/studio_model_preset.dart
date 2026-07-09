import 'package:freezed_annotation/freezed_annotation.dart';

part 'studio_model_preset.freezed.dart';
part 'studio_model_preset.g.dart';

/// A curated studio model the user can try clothes on instead of their own photo
/// (Try-On Body System — BUILD_PROMPT_PRO_PROMAX.md). Only ACTIVE presets (with a
/// real hosted image) are returned by `GET /v1/studio/models`, so the picker is
/// empty until the founder uploads images — nothing broken ever shows.
@freezed
abstract class StudioModelPreset with _$StudioModelPreset {
  const factory StudioModelPreset({
    required String id,
    required String name,
    @JsonKey(name: 'image_url') String? imageUrl,
    String? style,
    @JsonKey(name: 'body_type') String? bodyType,
    @JsonKey(name: 'skin_tone') String? skinTone,
    @JsonKey(name: 'pose_type') String? poseType,
    @JsonKey(name: 'is_pro_only') @Default(true) bool isProOnly,
  }) = _StudioModelPreset;

  factory StudioModelPreset.fromJson(Map<String, dynamic> json) =>
      _$StudioModelPresetFromJson(json);
}
