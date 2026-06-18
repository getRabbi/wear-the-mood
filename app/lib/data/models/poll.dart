import 'package:freezed_annotation/freezed_annotation.dart';

part 'poll.freezed.dart';
part 'poll.g.dart';

/// One poll option with its aggregate vote count (FEATURES_COMMUNITY_PLUS · Poll).
@freezed
abstract class PollOption with _$PollOption {
  const factory PollOption({
    required int index,
    required String label,
    @Default(0) int votes,
  }) = _PollOption;

  factory PollOption.fromJson(Map<String, dynamic> json) =>
      _$PollOptionFromJson(json);
}

/// A poll attached to a post. Counts are aggregate; [myChoice] is the viewer's
/// own option index only (the API never exposes who voted what, §10).
@freezed
abstract class Poll with _$Poll {
  const factory Poll({
    required String id,
    required String question,
    @Default(<PollOption>[]) List<PollOption> options,
    @JsonKey(name: 'total_votes') @Default(0) int totalVotes,
    @JsonKey(name: 'my_choice') int? myChoice,
    @JsonKey(name: 'closes_at') DateTime? closesAt,
    @JsonKey(name: 'is_closed') @Default(false) bool isClosed,
  }) = _Poll;

  const Poll._();

  factory Poll.fromJson(Map<String, dynamic> json) => _$PollFromJson(json);

  /// The viewer has cast a vote.
  bool get hasVoted => myChoice != null;

  /// Show results (bars) instead of tappable options once voted or closed.
  bool get showResults => hasVoted || isClosed;
}
