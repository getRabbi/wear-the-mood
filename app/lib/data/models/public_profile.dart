import 'package:freezed_annotation/freezed_annotation.dart';

part 'public_profile.freezed.dart';
part 'public_profile.g.dart';

/// A creator's PUBLIC profile (CLAUDE.md §1 pillar 4) — the safe fields shown on
/// `PublicProfileScreen`. The backend serves ONLY these (never email, phone,
/// body data, or private photos, §10), so nothing sensitive can leak here.
@freezed
abstract class PublicProfile with _$PublicProfile {
  const factory PublicProfile({
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'display_name') String? displayName,
    String? username,
    String? bio,
    @JsonKey(name: 'style_tags') @Default(<String>[]) List<String> styleTags,
    @JsonKey(name: 'follower_count') @Default(0) int followerCount,
    @JsonKey(name: 'following_count') @Default(0) int followingCount,
    @JsonKey(name: 'post_count') @Default(0) int postCount,
    @JsonKey(name: 'is_following') @Default(false) bool isFollowing,
    @JsonKey(name: 'is_me') @Default(false) bool isMe,
    // Signed display URL of the creator's chosen public photo (never the
    // try-on/body photo, §10). Null when unset.
    @JsonKey(name: 'avatar_url') String? avatarUrl,
  }) = _PublicProfile;

  factory PublicProfile.fromJson(Map<String, dynamic> json) =>
      _$PublicProfileFromJson(json);
}

/// A creator in a followers / following list — the minimal public card.
@freezed
abstract class PublicUserCard with _$PublicUserCard {
  const factory PublicUserCard({
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'display_name') String? displayName,
    String? username,
    @JsonKey(name: 'style_tags') @Default(<String>[]) List<String> styleTags,
    @JsonKey(name: 'is_following') @Default(false) bool isFollowing,
    @JsonKey(name: 'is_me') @Default(false) bool isMe,
  }) = _PublicUserCard;

  factory PublicUserCard.fromJson(Map<String, dynamic> json) =>
      _$PublicUserCardFromJson(json);
}
