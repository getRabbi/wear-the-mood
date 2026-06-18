import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';

/// Reads the backend feature flags (CLAUDE.md §16) — the source of truth for
/// gradual rollout. The app never decides a flag locally; it asks `/v1/flags`.
class FeatureFlagsRepository {
  FeatureFlagsRepository(this._dio);

  final Dio _dio;

  /// The set of ENABLED flag keys. A flag absent from the response is OFF.
  Future<Set<String>> getEnabled() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/flags');
      final flags = (res.data?['flags'] as Map<String, dynamic>?) ?? const {};
      return {
        for (final e in flags.entries)
          if (e.value == true) e.key,
      };
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final featureFlagsRepositoryProvider = Provider<FeatureFlagsRepository>((ref) {
  return FeatureFlagsRepository(ref.watch(dioProvider));
});
