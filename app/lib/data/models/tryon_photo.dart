import 'package:freezed_annotation/freezed_annotation.dart';

part 'tryon_photo.freezed.dart';
part 'tryon_photo.g.dart';

/// One saved full-body try-on photo (CLAUDE.md §1). `storagePath` is a private
/// path in the `avatars` bucket; the app signs it for display. `isSelected` is the
/// one mirrored onto the profile and fed to try-on. `qualityScore` (0–100) is the
/// on-device pose quality — shown as a badge so the user can pick the best shot.
@freezed
abstract class TryonPhoto with _$TryonPhoto {
  const factory TryonPhoto({
    required String id,
    @JsonKey(name: 'storage_path') required String storagePath,
    @JsonKey(name: 'quality_score') int? qualityScore,
    @JsonKey(name: 'is_selected') @Default(false) bool isSelected,
  }) = _TryonPhoto;

  factory TryonPhoto.fromJson(Map<String, dynamic> json) =>
      _$TryonPhotoFromJson(json);
}
