import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/packing_plan.dart';

/// Packing planner (CLAUDE.md §24). Builds a trip packing list from the user's
/// own closet server-side (stylist + weather); the app never holds keys (§11).
class PackingRepository {
  PackingRepository(this._dio);

  final Dio _dio;

  Future<PackingPlan> plan({
    required int days,
    String? occasion,
    String? note,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/packing/plan',
        data: {
          'days': days,
          'occasion': ?occasion,
          'note': ?note,
          'latitude': ?latitude,
          'longitude': ?longitude,
        },
      );
      return PackingPlan.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final packingRepositoryProvider = Provider<PackingRepository>((ref) {
  return PackingRepository(ref.watch(dioProvider));
});
