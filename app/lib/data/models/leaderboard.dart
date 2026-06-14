import 'package:freezed_annotation/freezed_annotation.dart';

part 'leaderboard.freezed.dart';
part 'leaderboard.g.dart';

/// Monthly community Style-Score leaderboard (CLAUDE.md §1 pillar 4, §24).
@freezed
abstract class LeaderboardEntry with _$LeaderboardEntry {
  const factory LeaderboardEntry({
    required int rank,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'display_name') String? displayName,
    required int score,
    @JsonKey(name: 'is_me') @Default(false) bool isMe,
  }) = _LeaderboardEntry;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      _$LeaderboardEntryFromJson(json);
}

@freezed
abstract class PastWinner with _$PastWinner {
  const factory PastWinner({
    required String month,
    @JsonKey(name: 'display_name') String? displayName,
    required int score,
  }) = _PastWinner;

  factory PastWinner.fromJson(Map<String, dynamic> json) =>
      _$PastWinnerFromJson(json);
}

@freezed
abstract class Leaderboard with _$Leaderboard {
  const factory Leaderboard({
    required String month, // "YYYY-MM"
    @Default(<LeaderboardEntry>[]) List<LeaderboardEntry> entries,
    @JsonKey(name: 'my_rank') int? myRank,
    @JsonKey(name: 'my_score') @Default(0) int myScore,
    @JsonKey(name: 'recent_winners')
    @Default(<PastWinner>[])
    List<PastWinner> recentWinners,
  }) = _Leaderboard;

  factory Leaderboard.fromJson(Map<String, dynamic> json) =>
      _$LeaderboardFromJson(json);
}
