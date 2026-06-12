import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/wardrobe_analytics.dart';
import '../models/wardrobe_item.dart';

/// The digital almira's data layer (CLAUDE.md §5). All calls hit own-row
/// endpoints scoped server-side to the JWT user (§11). Adding an item (with
/// image upload + background removal, §8/§2.2) is a later, gated step — this
/// covers list + remove.
class WardrobeRepository {
  WardrobeRepository(this._dio);

  final Dio _dio;

  /// The user's closet, newest first.
  Future<List<WardrobeItem>> getItems() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/wardrobe');
      return (res.data ?? const [])
          .map((e) => WardrobeItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Adds a piece to the closet. The image is already uploaded to storage (§8);
  /// only its URL is sent here. Background removal + tagging (§2.2) fill the rest
  /// server-side in a later step. Returns the created item.
  Future<WardrobeItem> addItem({
    String? title,
    String? category,
    required String imageUrl,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/wardrobe',
        data: {'title': ?title, 'category': ?category, 'image_url': imageUrl},
      );
      return WardrobeItem.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Semantic search over the closet (§2.1, §24). The backend embeds [query]
  /// and ranks by similarity, falling back to keyword match server-side.
  Future<List<WardrobeItem>> search({
    required String query,
    int limit = 20,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/wardrobe/search',
        queryParameters: {'q': query, 'limit': limit},
      );
      return (res.data ?? const [])
          .map((e) => WardrobeItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Removes one owned item. The backend 404s if it isn't the caller's (§11).
  Future<void> deleteItem(String id) async {
    try {
      await _dio.delete<void>('/v1/wardrobe/$id');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Cost-per-wear + ROI insights over the closet (§24).
  Future<WardrobeAnalytics> getAnalytics() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/wardrobe/analytics');
      return WardrobeAnalytics.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Logs a wear of [id] (+1 wear_count), feeding cost-per-wear (§24).
  Future<void> markWorn(String id) async {
    try {
      await _dio.post<void>('/v1/wardrobe/$id/wear');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final wardrobeRepositoryProvider = Provider<WardrobeRepository>((ref) {
  return WardrobeRepository(ref.watch(dioProvider));
});
