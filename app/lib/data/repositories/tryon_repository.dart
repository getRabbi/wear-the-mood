import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../shared/utils/uuid.dart';
import '../models/tryon_job.dart';
import '../models/tryon_result.dart';

/// Talks to the async try-on endpoints (CLAUDE.md §7). All AI runs server-side;
/// the app only creates jobs and polls — it never touches a provider key (§11).
class TryOnRepository {
  TryOnRepository(this._dio);

  final Dio _dio;

  /// Creates a try-on job. Supply exactly one garment source. Sends a unique
  /// `Idempotency-Key` so a retry never double-charges (§9). Returns the queued
  /// job ({job_id, status: queued}).
  Future<TryOnJob> createTryOn({
    required String personImageUrl,
    String? garmentImageUrl,
    String? wardrobeItemId,
    String? idempotencyKey,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/tryon',
        data: {
          'person_image_url': personImageUrl,
          'garment_image_url': ?garmentImageUrl,
          'wardrobe_item_id': ?wardrobeItemId,
        },
        options: Options(
          headers: {'Idempotency-Key': idempotencyKey ?? uuidV4()},
        ),
      );
      return TryOnJob.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Fetches the current status (and result URL once done) of a job.
  Future<TryOnJob> getJob(String jobId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/tryon/$jobId');
      return TryOnJob.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// The user's saved try-on results, newest first (history view).
  Future<List<TryonResult>> listResults() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/tryon/results');
      return (res.data ?? [])
          .map((e) => TryonResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final tryOnRepositoryProvider = Provider<TryOnRepository>((ref) {
  return TryOnRepository(ref.watch(dioProvider));
});

/// The user's saved try-on results. Auto-disposes so it refreshes on reopen;
/// invalidate after a new try-on succeeds to show it.
final tryOnResultsProvider = FutureProvider.autoDispose<List<TryonResult>>((
  ref,
) {
  return ref.watch(tryOnRepositoryProvider).listResults();
});
