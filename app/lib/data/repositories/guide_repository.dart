import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/daily_guide.dart';

/// Reads the Daily Guide (FEATURES_COMMUNITY_PLUS · Daily Guide).
class GuideRepository {
  GuideRepository(this._dio);

  final Dio _dio;

  /// Today's guide, or null when none is available yet.
  Future<DailyGuide?> getToday() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/guide/today');
      return DailyGuide.fromJson(res.data!);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDio(error);
    }
  }
}

final guideRepositoryProvider = Provider<GuideRepository>((ref) {
  return GuideRepository(ref.watch(dioProvider));
});

/// Today's guide (null if none). Drives the Home "Today" section.
final dailyGuideProvider = FutureProvider<DailyGuide?>((ref) {
  return ref.watch(guideRepositoryProvider).getToday();
});
