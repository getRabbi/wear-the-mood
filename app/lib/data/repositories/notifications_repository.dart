import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/app_notification.dart';

/// The in-app notifications feed (CLAUDE.md §1 pillar 4). Own-row, server-scoped
/// to the JWT (§11). Notifications are created server-side by the social/try-on
/// flows — the client only reads and marks them read.
class NotificationsRepository {
  NotificationsRepository(this._dio);

  final Dio _dio;

  Future<List<AppNotification>> getNotifications({int limit = 50}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/notifications',
        queryParameters: {'limit': limit},
      );
      return (res.data ?? const [])
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _dio.post<void>('/v1/notifications/$id/read');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> markAllRead() async {
    try {
      await _dio.post<void>('/v1/notifications/read-all');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(ref.watch(dioProvider));
});

/// The caller's notifications, newest first. Auto-disposes so it refetches when
/// the screen reopens; invalidate after mark-read/mark-all.
final notificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) {
      return ref.watch(notificationsRepositoryProvider).getNotifications();
    });

/// Unread count, derived from the loaded feed (0 while loading / on error).
final unreadNotificationsProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(notificationsProvider).asData?.value
          .where((n) => !n.isRead)
          .length ??
      0;
});
