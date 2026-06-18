import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../shared/utils/uuid.dart';
import '../models/quiz.dart';

/// Talks to the Style Quiz endpoints (FEATURES_COMMUNITY_PLUS · Style Quiz). All
/// scoring is server-side; submit is idempotent (a per-completion key, §9).
class QuizRepository {
  QuizRepository(this._dio);

  final Dio _dio;

  Future<ActiveQuiz> getActiveQuiz() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/quiz/active');
      return ActiveQuiz.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Submits answers ({question_id: option key}) and returns the Style DNA card.
  Future<QuizResult> submit(String quizId, Map<String, String> answers) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/quiz/$quizId/submit',
        data: {'answers': answers},
        options: Options(headers: {'Idempotency-Key': uuidV4()}),
      );
      return QuizResult.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// The user's latest result, or null if they haven't taken the quiz.
  Future<QuizResult?> latestResult() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/quiz/result/latest');
      return QuizResult.fromJson(res.data!);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDio(error);
    }
  }
}

final quizRepositoryProvider = Provider<QuizRepository>((ref) {
  return QuizRepository(ref.watch(dioProvider));
});

/// The active quiz (questions). Auto-disposes so it's fetched fresh on open.
final activeQuizProvider = FutureProvider.autoDispose<ActiveQuiz>((ref) {
  return ref.watch(quizRepositoryProvider).getActiveQuiz();
});

/// The user's latest Style DNA result (null if none). Invalidate after a submit.
final latestQuizResultProvider = FutureProvider<QuizResult?>((ref) {
  return ref.watch(quizRepositoryProvider).latestResult();
});
