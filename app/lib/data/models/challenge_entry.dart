import 'package:freezed_annotation/freezed_annotation.dart';

part 'challenge_entry.freezed.dart';
part 'challenge_entry.g.dart';

/// A post entered into a challenge, with its author (CLAUDE.md §1 pillar 4).
/// JSON keys match the `/v1/challenges/{id}/entries` response.
@freezed
abstract class ChallengeEntry with _$ChallengeEntry {
  const factory ChallengeEntry({
    required String id,
    @JsonKey(name: 'challenge_id') required String challengeId,
    @JsonKey(name: 'post_id') required String postId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'author_name') String? authorName,
    @JsonKey(name: 'image_url') String? imageUrl,
    String? caption,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _ChallengeEntry;

  factory ChallengeEntry.fromJson(Map<String, dynamic> json) =>
      _$ChallengeEntryFromJson(json);
}
