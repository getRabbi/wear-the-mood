import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/outfit.dart';

/// Saved outfits — combinations of owned wardrobe items (CLAUDE.md §5). All
/// calls hit own-row endpoints; the backend re-checks item ownership on create
/// (§11).
class OutfitRepository {
  OutfitRepository(this._dio);

  final Dio _dio;

  /// The user's saved outfits, newest first.
  Future<List<Outfit>> getOutfits() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/outfits');
      return (res.data ?? const [])
          .map((e) => Outfit.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Saves a new outfit from owned items. Returns the created outfit.
  Future<Outfit> createOutfit({
    String? name,
    required List<String> itemIds,
    String? coverImageUrl,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/outfits',
        data: {
          'name': ?name,
          'item_ids': itemIds,
          'cover_image_url': ?coverImageUrl,
        },
      );
      return Outfit.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Removes one outfit. The backend 404s if it isn't the caller's (§11).
  Future<void> deleteOutfit(String id) async {
    try {
      await _dio.delete<void>('/v1/outfits/$id');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final outfitRepositoryProvider = Provider<OutfitRepository>((ref) {
  return OutfitRepository(ref.watch(dioProvider));
});
