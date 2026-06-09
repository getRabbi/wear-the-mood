import 'package:freezed_annotation/freezed_annotation.dart';

part 'credits.freezed.dart';
part 'credits.g.dart';

/// User credit state from `GET /v1/credits` (CLAUDE.md §12).
@freezed
abstract class Credits with _$Credits {
  const factory Credits({
    required int balance,
    @JsonKey(name: 'daily_free_used') required int dailyFreeUsed,
    @JsonKey(name: 'daily_free_limit') required int dailyFreeLimit,
    @JsonKey(name: 'daily_free_remaining') required int dailyFreeRemaining,
  }) = _Credits;

  const Credits._();

  factory Credits.fromJson(Map<String, dynamic> json) =>
      _$CreditsFromJson(json);

  /// Whether the user can start another paid action right now.
  bool get canSpend => dailyFreeRemaining > 0 || balance > 0;
}
