import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/wardrobe_analytics.dart';
import '../models/wardrobe_gap.dart';
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

  /// Adds a piece to the closet. The image is already uploaded to storage (§8):
  /// send its R2 [objectKey] (private, write-gate on) OR the legacy [imageUrl] —
  /// exactly one. Background removal + tagging (§2.2) fill the rest server-side.
  Future<WardrobeItem> addItem({
    String? title,
    String? category,
    String? imageUrl,
    String? objectKey,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/wardrobe',
        data: {
          'title': ?title,
          'category': ?category,
          if (objectKey != null)
            'object_key': objectKey
          else
            'image_url': imageUrl,
        },
      );
      return WardrobeItem.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Edits/categorizes an owned item — name, category, subcategory, color
  /// (real-device polish). Sends the fields the categorize flow manages; a null
  /// value clears that field server-side. Returns the updated item.
  Future<WardrobeItem> updateItem(
    String id, {
    required String? title,
    required String? category,
    required String? color,
    String? subcategory,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/v1/wardrobe/$id',
        data: {
          'title': title,
          'category': category,
          'color': color,
          'subcategory': ?subcategory,
        },
      );
      return WardrobeItem.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Uploads a hand-edited cutout mask (PNG whose alpha channel is the corrected
  /// mask) for item [id] and returns the item with its freshly re-composited
  /// cutout (§ BG upgrade Phase 7). FREE — spends no credits and runs no AI. The
  /// backend 404s when the editor is disabled and 503s when private storage is
  /// unavailable; both surface as an [ApiException].
  Future<WardrobeItem> uploadCutoutMask(String id, Uint8List maskPng) async {
    try {
      final form = FormData.fromMap({
        'mask': MultipartFile.fromBytes(maskPng, filename: 'mask.png'),
      });
      final res = await _dio.put<Map<String, dynamic>>(
        '/v1/wardrobe/$id/cutout-mask',
        data: form,
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
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/wardrobe/analytics',
      );
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

  /// Closet-gap analysis: essentials the user is missing (§24).
  Future<List<WardrobeGap>> getGaps() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/wardrobe/gaps');
      return (res.data ?? const [])
          .map((e) => WardrobeGap.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final wardrobeRepositoryProvider = Provider<WardrobeRepository>((ref) {
  return WardrobeRepository(ref.watch(dioProvider));
});
