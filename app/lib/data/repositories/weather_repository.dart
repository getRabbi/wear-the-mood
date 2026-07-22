import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/weather.dart';

/// Fetches real weather (CLAUDE.md §2) from the backend, which wraps the free,
/// keyless Open-Meteo provider — so no weather key ever ships in the app (§11).
/// The app only sends a coordinate (device location) or a city name (the manual
/// fallback); it never invents weather when the provider is unavailable.
class WeatherRepository {
  WeatherRepository(this._dio);

  final Dio _dio;

  /// Current + today's weather for a coordinate. Throws [ApiException] on a
  /// provider/network failure so the caller can show a real "unavailable" state.
  Future<WeatherSnapshot> current({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/weather/current',
        queryParameters: {'latitude': latitude, 'longitude': longitude},
      );
      return WeatherSnapshot.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Resolve a city name to candidate places (manual-city fallback, §20).
  Future<List<GeoPlace>> search(String query) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/weather/geocode',
        queryParameters: {'q': query},
      );
      return (res.data ?? const [])
          .map((e) => GeoPlace.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository(ref.watch(dioProvider));
});
