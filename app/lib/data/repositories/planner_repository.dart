import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/planner.dart';

/// Mood Planner v2 + Event Planner (RETENTION spec §14, §15).
///
/// Neither costs a credit and neither can start a render. That is the point:
/// a reason to open WTM on a day the user has no intention of spending.
///
/// The server answers 404 for a write while the feature flag is off, so the
/// write paths surface that as null rather than as an error — the app simply
/// does not show these surfaces when the flag is off, and a 404 here means the
/// flag flipped mid-session.
class PlannerRepository {
  PlannerRepository(this._dio);

  final Dio _dio;

  /// Turn a mood (and optional occasion) into styling direction.
  Future<MoodPlan?> createMoodPlan({
    required PlannerMood mood,
    PlannerOccasion? occasion,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/plans/mood',
        data: {
          'mood': mood.wire,
          if (occasion != null) 'occasion': occasion.wire,
        },
      );
      return MoodPlan.fromJson(res.data!);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDio(error);
    }
  }

  /// The most recent plan, so "Continue your style" shows the SAME direction
  /// rather than silently re-rolling it. Null when there is none.
  Future<MoodPlan?> latestMoodPlan() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/plans/mood/latest');
      final data = res.data;
      if (data == null || data.isEmpty) return null;
      return MoodPlan.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDio(error);
    }
  }

  Future<StyleEventList> listEvents({bool includePast = false}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/events',
        queryParameters: {'include_past': includePast},
      );
      return StyleEventList.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<StyleEvent?> createEvent({
    required String name,
    required DateTime eventAt,
    String? occasion,
    String? lookRef,
    String? lookImageUrl,
    String? note,
    bool reminderOptIn = false,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/events',
        data: {
          'name': name,
          // Always UTC on the wire; the server stores an absolute instant and
          // the app renders it back in the device's zone.
          'event_at': eventAt.toUtc().toIso8601String(),
          'occasion': ?occasion,
          'look_ref': ?lookRef,
          'look_image_url': ?lookImageUrl,
          'note': ?note,
          'reminder_opt_in': reminderOptIn,
        },
      );
      return StyleEvent.fromJson(res.data!);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDio(error);
    }
  }

  Future<StyleEvent?> updateEvent({
    required String id,
    String? name,
    DateTime? eventAt,
    String? occasion,
    String? lookRef,
    String? lookImageUrl,
    String? note,
    bool? reminderOptIn,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/v1/events/$id',
        data: {
          'name': ?name,
          if (eventAt != null) 'event_at': eventAt.toUtc().toIso8601String(),
          'occasion': ?occasion,
          'look_ref': ?lookRef,
          'look_image_url': ?lookImageUrl,
          'note': ?note,
          'reminder_opt_in': ?reminderOptIn,
        },
      );
      return StyleEvent.fromJson(res.data!);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deleteEvent(String id) async {
    try {
      await _dio.delete<void>('/v1/events/$id');
    } on DioException catch (error) {
      // Already gone is the outcome the user asked for.
      if (error.response?.statusCode == 404) return;
      throw ApiException.fromDio(error);
    }
  }
}

final plannerRepositoryProvider = Provider<PlannerRepository>((ref) {
  return PlannerRepository(ref.watch(dioProvider));
});

/// The user's upcoming events, soonest first.
final upcomingEventsProvider = FutureProvider.autoDispose<StyleEventList>((
  ref,
) {
  return ref.watch(plannerRepositoryProvider).listEvents();
});

/// The user's most recent mood plan, or null when they have never made one.
final latestMoodPlanProvider = FutureProvider.autoDispose<MoodPlan?>((ref) {
  return ref.watch(plannerRepositoryProvider).latestMoodPlan();
});
