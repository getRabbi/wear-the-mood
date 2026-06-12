import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/calendar_event_plan.dart';

/// Calendar autopilot (CLAUDE.md §24). Sends event titles only (no other
/// calendar data, §10); the backend suggests an outfit per event server-side.
class CalendarRepository {
  CalendarRepository(this._dio);

  final Dio _dio;

  Future<List<CalendarEventPlan>> plan(List<String> eventTitles) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/calendar/plan',
        data: {
          'events': [for (final t in eventTitles) {'title': t}],
        },
      );
      final plans = (res.data?['plans'] as List<dynamic>?) ?? const [];
      return plans
          .map((e) => CalendarEventPlan.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return CalendarRepository(ref.watch(dioProvider));
});
