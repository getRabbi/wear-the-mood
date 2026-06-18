import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/offer.dart';

/// Reads the Daily Offers (FEATURES_COMMUNITY_PLUS · Daily Offer). Affiliate
/// links arrive attribution-tagged; the app only opens them and logs the click.
class OffersRepository {
  OffersRepository(this._dio);

  final Dio _dio;

  Future<List<Offer>> getToday() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/offers/today');
      return (res.data ?? const [])
          .map((e) => Offer.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final offersRepositoryProvider = Provider<OffersRepository>((ref) {
  return OffersRepository(ref.watch(dioProvider));
});

/// Today's offers for the Newsroom strip. Auto-disposes so it refreshes on open.
final offersProvider = FutureProvider.autoDispose<List<Offer>>((ref) {
  return ref.watch(offersRepositoryProvider).getToday();
});
