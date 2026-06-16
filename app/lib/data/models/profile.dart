import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

/// Body info that drives try-on fit + the stylist (CLAUDE.md §1). Sensitive
/// (§10): captured only behind explicit biometric consent, every field optional.
/// `heightCm` is the single canonical unit — the UI offers a cm <-> ft/in toggle
/// but always stores centimetres.
@freezed
abstract class BodyData with _$BodyData {
  const factory BodyData({
    String? gender, // female | male | non_binary | prefer_not_to_say
    @JsonKey(name: 'height_cm') int? heightCm,
    @JsonKey(name: 'weight_kg') int? weightKg,
    @JsonKey(name: 'age_range') String? ageRange,
    @JsonKey(name: 'body_type') String? bodyType,
    @JsonKey(name: 'fit_preference') String? fitPreference,
    @JsonKey(name: 'skin_tone') String? skinTone,
  }) = _BodyData;

  factory BodyData.fromJson(Map<String, dynamic> json) =>
      _$BodyDataFromJson(json);
}

/// The user's profile (CLAUDE.md §1).
/// - `avatarUrl` is the PRIVATE full-body **try-on** photo path (validated).
/// - `profilePictureUrl` is the PRIVATE **display** photo path (any photo).
/// Both are storage paths; the app mints short-lived signed URLs to show them or
/// feed the try-on photo to the renderer.
@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required String id,
    @JsonKey(name: 'display_name') String? displayName,
    String? phone,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'profile_picture_url') String? profilePictureUrl,
    @JsonKey(name: 'body_data') BodyData? bodyData,
    String? timezone,
    @JsonKey(name: 'onboarding_completed')
    @Default(false)
    bool onboardingCompleted,
    @JsonKey(name: 'biometric_consent') @Default(false) bool biometricConsent,
    // Public-facing fields shown on the creator's public profile (§1 pillar 4).
    String? bio,
    @JsonKey(name: 'style_tags') @Default(<String>[]) List<String> styleTags,
    @JsonKey(name: 'is_public') @Default(true) bool isPublic,
  }) = _Profile;

  const Profile._();

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);

  /// Whether the user has a validated try-on body photo.
  bool get hasAvatar => (avatarUrl ?? '').isNotEmpty;

  /// Whether the user has set a decorative display picture.
  bool get hasProfilePicture => (profilePictureUrl ?? '').isNotEmpty;
}
