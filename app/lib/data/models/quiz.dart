import 'package:freezed_annotation/freezed_annotation.dart';

part 'quiz.freezed.dart';
part 'quiz.g.dart';

/// One selectable answer in a quiz question (FEATURES_COMMUNITY_PLUS · Style Quiz).
@freezed
abstract class QuizOption with _$QuizOption {
  const factory QuizOption({
    required String key,
    required String label,
    @JsonKey(name: 'image_url') String? imageUrl,
  }) = _QuizOption;

  factory QuizOption.fromJson(Map<String, dynamic> json) =>
      _$QuizOptionFromJson(json);
}

@freezed
abstract class QuizQuestion with _$QuizQuestion {
  const factory QuizQuestion({
    required String id,
    required String prompt,
    @Default(<QuizOption>[]) List<QuizOption> options,
  }) = _QuizQuestion;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) =>
      _$QuizQuestionFromJson(json);
}

@freezed
abstract class ActiveQuiz with _$ActiveQuiz {
  const factory ActiveQuiz({
    required String id,
    required String slug,
    required String title,
    String? description,
    @Default(<QuizQuestion>[]) List<QuizQuestion> questions,
  }) = _ActiveQuiz;

  factory ActiveQuiz.fromJson(Map<String, dynamic> json) =>
      _$ActiveQuizFromJson(json);
}

/// The computed "Style DNA" card.
@freezed
abstract class StyleResult with _$StyleResult {
  const factory StyleResult({
    required String title,
    @Default(<String>[]) List<String> keywords,
    @Default('') String description,
    @Default(<String>[]) List<String> palette,
  }) = _StyleResult;

  factory StyleResult.fromJson(Map<String, dynamic> json) =>
      _$StyleResultFromJson(json);
}

@freezed
abstract class QuizResult with _$QuizResult {
  const factory QuizResult({
    required String id,
    required StyleResult result,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _QuizResult;

  factory QuizResult.fromJson(Map<String, dynamic> json) =>
      _$QuizResultFromJson(json);
}
