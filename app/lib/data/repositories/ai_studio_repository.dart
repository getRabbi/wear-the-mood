import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../shared/utils/uuid.dart';
import '../models/ai_job.dart';
import '../models/generated_image.dart';
import '../models/studio_model_preset.dart';

/// Talks to the AI Studio endpoints (BUILD_PROMPT_PRO_PROMAX.md). All AI runs
/// server-side; the app only creates jobs + polls, and never holds a provider
/// key (§11). Paid actions send a unique `Idempotency-Key` so a retry never
/// double-charges (§9).
class AiStudioRepository {
  AiStudioRepository(this._dio);

  final Dio _dio;

  /// Active studio models for the try-on body picker (empty until the founder
  /// uploads preset images).
  Future<List<StudioModelPreset>> listStudioModels() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/studio/models');
      return (res.data ?? [])
          .map((e) => StudioModelPreset.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Starts an AI Enhance on an owned closet item (Pro/Pro Max, 4 credits).
  Future<AiJob> enhanceItem(String wardrobeItemId, {String? idempotencyKey}) {
    return _createJob(
      '/v1/ai/enhance',
      {'wardrobe_item_id': wardrobeItemId},
      idempotencyKey,
    );
  }

  /// Generates a catalog model shot of an owned item (Pro = 1 credit, Pro Max HD
  /// = 4 credits).
  Future<AiJob> catalogModel(
    String wardrobeItemId, {
    required String style,
    bool hd = false,
    String? idempotencyKey,
  }) {
    return _createJob(
      '/v1/ai/catalog-model',
      {'wardrobe_item_id': wardrobeItemId, 'style': style, 'hd': hd},
      idempotencyKey,
    );
  }

  Future<AiJob> _createJob(
    String path,
    Map<String, dynamic> data,
    String? idempotencyKey,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(
          headers: {'Idempotency-Key': idempotencyKey ?? uuidV4()},
        ),
      );
      return AiJob.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Polls a job's status (and signed output URL once completed).
  Future<AiJob> getJob(String jobId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/ai/jobs/$jobId');
      return AiJob.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// The user's saved AI Looks (enhanced items + catalog shots), newest first.
  Future<List<GeneratedImage>> listGenerated() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/ai/generated');
      return (res.data ?? [])
          .map((e) => GeneratedImage.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deleteGenerated(String id) async {
    try {
      await _dio.delete<void>('/v1/ai/generated/$id');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> reportGenerated(String id) async {
    try {
      await _dio.post<void>('/v1/ai/generated/$id/report');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final aiStudioRepositoryProvider = Provider<AiStudioRepository>((ref) {
  return AiStudioRepository(ref.watch(dioProvider));
});

/// Active studio models for the try-on body picker. Auto-disposes so it refreshes
/// on reopen.
final studioModelsProvider =
    FutureProvider.autoDispose<List<StudioModelPreset>>((ref) {
      return ref.watch(aiStudioRepositoryProvider).listStudioModels();
    });

/// The user's saved AI Looks. Invalidate after a new generation / delete.
final generatedImagesProvider =
    FutureProvider.autoDispose<List<GeneratedImage>>((ref) {
      return ref.watch(aiStudioRepositoryProvider).listGenerated();
    });
