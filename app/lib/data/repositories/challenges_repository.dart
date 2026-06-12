import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/challenge.dart';
import '../models/challenge_entry.dart';

/// Talks to the challenges endpoints (CLAUDE.md §1 pillar 4). Challenges are
/// public to read; entering links one of the user's own posts and the backend
/// scopes the write to the JWT user (§11).
class ChallengesRepository {
  ChallengesRepository(this._dio);

  final Dio _dio;

  /// Active challenges, newest first.
  Future<List<Challenge>> listChallenges() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/challenges');
      return (res.data ?? const [])
          .map((e) => Challenge.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Challenge> getChallenge(String slug) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/challenges/$slug');
      return Challenge.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Enter a challenge by linking one of the user's own posts. Returns the
  /// challenge with the updated counts.
  Future<Challenge> join(String challengeId, String postId) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/challenges/$challengeId/join',
        data: {'post_id': postId},
      );
      return Challenge.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Withdraw one of the user's posts from a challenge.
  Future<void> leave(String challengeId, String postId) async {
    try {
      await _dio.delete<void>('/v1/challenges/$challengeId/entries/$postId');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Newest-first entries for a challenge.
  Future<List<ChallengeEntry>> getEntries(
    String challengeId, {
    int limit = 20,
    DateTime? before,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/challenges/$challengeId/entries',
        queryParameters: {
          'limit': limit,
          if (before != null) 'before': before.toUtc().toIso8601String(),
        },
      );
      return (res.data ?? const [])
          .map((e) => ChallengeEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final challengesRepositoryProvider = Provider<ChallengesRepository>((ref) {
  return ChallengesRepository(ref.watch(dioProvider));
});
