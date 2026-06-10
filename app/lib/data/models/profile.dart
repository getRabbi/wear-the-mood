import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

/// Optional body info for fit/styling (CLAUDE.md §1, §10 — minimized).
@freezed
abstract class BodyData with _$BodyData {
  const factory BodyData({
    @JsonKey(name: 'height_cm') int? heightCm,
    @JsonKey(name: 'body_type') String? bodyType,
  }) = _BodyData;

  factory BodyData.fromJson(Map<String, dynamic> json) =>
      _$BodyDataFromJson(json);
}

/// The user's profile (CLAUDE.md §1). `avatarUrl` is a PRIVATE storage path —
/// the app mints a short-lived signed URL to display it or feed it to try-on.
@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required String id,
    @JsonKey(name: 'display_name') String? displayName,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'body_data') BodyData? bodyData,
    String? timezone,
    @JsonKey(name: 'onboarding_completed')
    @Default(false)
    bool onboardingCompleted,
    @JsonKey(name: 'biometric_consent') @Default(false) bool biometricConsent,
  }) = _Profile;

  const Profile._();

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);

  bool get hasAvatar => (avatarUrl ?? '').isNotEmpty;
}
