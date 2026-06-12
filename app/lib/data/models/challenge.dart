import 'package:freezed_annotation/freezed_annotation.dart';

part 'challenge.freezed.dart';
part 'challenge.g.dart';

/// A style challenge (CLAUDE.md §1 pillar 4). JSON keys match the
/// `/v1/challenges` response (the challenge + entry count + the viewer's
/// entered state).
@freezed
abstract class Challenge with _$Challenge {
  const factory Challenge({
    required String id,
    required String slug,
    required String title,
    String? prompt,
    @JsonKey(name: 'cover_url') String? coverUrl,
    @JsonKey(name: 'starts_at') required DateTime startsAt,
    @JsonKey(name: 'ends_at') DateTime? endsAt,
    @JsonKey(name: 'entry_count') @Default(0) int entryCount,
    @JsonKey(name: 'joined_by_me') @Default(false) bool joinedByMe,
  }) = _Challenge;

  factory Challenge.fromJson(Map<String, dynamic> json) =>
      _$ChallengeFromJson(json);
}
