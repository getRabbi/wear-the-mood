import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
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

  /// Removes one owned item. The backend 404s if it isn't the caller's (§11).
  Future<void> deleteItem(String id) async {
    try {
      await _dio.delete<void>('/v1/wardrobe/$id');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final wardrobeRepositoryProvider = Provider<WardrobeRepository>((ref) {
  return WardrobeRepository(ref.watch(dioProvider));
});
