import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/notification_prefs.dart';

/// Per-category push preferences (§20). Server-authoritative; the app reflects
/// and PATCHes it. The in-app center is unaffected by these — they gate push.
class NotificationPrefsRepository {
  NotificationPrefsRepository(this._dio);

  final Dio _dio;

  Future<NotificationPreferences> get() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/notifications/preferences',
      );
      return NotificationPreferences.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Update only the given categories (e.g. `{'social': false}`).
  Future<NotificationPreferences> update(Map<String, bool> changes) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/v1/notifications/preferences',
        data: changes,
      );
      return NotificationPreferences.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final notificationPrefsRepositoryProvider = Provider<NotificationPrefsRepository>(
  (ref) => NotificationPrefsRepository(ref.watch(dioProvider)),
);

/// The signed-in user's push preferences; auto-disposes so it refetches on open.
final notificationPrefsProvider =
    FutureProvider.autoDispose<NotificationPreferences>(
      (ref) => ref.watch(notificationPrefsRepositoryProvider).get(),
    );
