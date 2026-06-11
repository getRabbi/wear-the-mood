import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/stylist_suggestion.dart';

/// Asks the backend stylist for today's outfit (CLAUDE.md §2.1). The LLM runs
/// server-side and degrades to a deterministic pick on failure; the app only
/// sends optional context and renders the result — it never holds an AI key (§11).
class StylistRepository {
  StylistRepository(this._dio);

  final Dio _dio;

  /// Requests a suggestion. Coordinates are optional — when supplied they add
  /// weather context (§2); omitted, the stylist works without it.
  Future<StylistSuggestion> suggest({
    double? latitude,
    double? longitude,
    String? occasion,
    String? note,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/stylist/suggest',
        data: {
          'latitude': ?latitude,
          'longitude': ?longitude,
          'occasion': ?occasion,
          'note': ?note,
        },
      );
      return StylistSuggestion.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final stylistRepositoryProvider = Provider<StylistRepository>((ref) {
  return StylistRepository(ref.watch(dioProvider));
});
