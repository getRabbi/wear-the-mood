import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/tryon_photo.dart';

/// Try-on photo gallery (CLAUDE.md §1). Own-row, server-scoped to the JWT (§11).
/// The selected photo is mirrored onto the profile's avatar_url server-side.
class TryonPhotosRepository {
  TryonPhotosRepository(this._dio);

  final Dio _dio;

  Future<List<TryonPhoto>> list() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/tryon-photos');
      return (res.data ?? [])
          .map((e) => TryonPhoto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<TryonPhoto> add({
    required String storagePath,
    int? qualityScore,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/tryon-photos',
        data: {'storage_path': storagePath, 'quality_score': ?qualityScore},
      );
      return TryonPhoto.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete<void>('/v1/tryon-photos/$id');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final tryonPhotosRepositoryProvider = Provider<TryonPhotosRepository>((ref) {
  return TryonPhotosRepository(ref.watch(dioProvider));
});

/// The user's saved try-on photos, newest first. Auto-disposes; invalidate after
/// add/delete/select to refresh the gallery.
final tryonPhotosProvider = FutureProvider.autoDispose<List<TryonPhoto>>((ref) {
  return ref.watch(tryonPhotosRepositoryProvider).list();
});
