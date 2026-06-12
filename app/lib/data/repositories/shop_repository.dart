import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';

/// Builds shoppable (affiliate when configured) links (CLAUDE.md §18, §24). The
/// affiliate program/tag lives backend-only; the app just opens the returned URL
/// and logs affiliate_link_clicked.
class ShopRepository {
  ShopRepository(this._dio);

  final Dio _dio;

  /// Returns a shoppable URL for [query] (a trend, a wardrobe piece, an outfit).
  Future<String> shopLink(String query, {String label = 'Shop this look'}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/shop/link',
        queryParameters: {'q': query, 'label': label},
      );
      return res.data!['url'] as String;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  return ShopRepository(ref.watch(dioProvider));
});
