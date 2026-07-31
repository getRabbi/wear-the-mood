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

  static const pageSize = 30;

  /// One page, newest first. [before]/[beforeId] are the `createdAt`/`id` of the
  /// LAST row already held — the server pages on `(created_at, id)`, a total
  /// order, so rows sharing a timestamp are neither repeated nor skipped.
  Future<List<AppNotification>> getNotifications({
    int limit = pageSize,
    DateTime? before,
    String? beforeId,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/notifications',
        queryParameters: {
          'limit': limit,
          if (before != null) 'before': before.toUtc().toIso8601String(),
          'before_id': ?beforeId,
        },
      );
      return (res.data ?? const [])
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// The server-authoritative unread count — NOT derived from the loaded page,
  /// which under-counts the moment the feed is longer than one page.
  Future<int> unreadCount() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/notifications/unread-count',
      );
      return (res.data?['unread_count'] as num?)?.toInt() ?? 0;
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

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository(ref.watch(dioProvider));
});

/// One page of the feed plus whether more remain.
class NotificationFeed {
  const NotificationFeed({
    required this.items,
    this.hasMore = false,
    this.loadingMore = false,
  });

  final List<AppNotification> items;
  final bool hasMore;
  final bool loadingMore;

  NotificationFeed copyWith({
    List<AppNotification>? items,
    bool? hasMore,
    bool? loadingMore,
  }) {
    return NotificationFeed(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
    );
  }
}

/// The caller's notifications, newest first, paginated.
///
/// A notifier rather than a bare [FutureProvider] so paging, an optimistic
/// mark-as-read and a push-triggered refresh all mutate ONE list. Appends are
/// de-duplicated by id: a row that arrives between two page fetches would
/// otherwise be rendered twice.
class NotificationsNotifier extends AsyncNotifier<NotificationFeed> {
  NotificationsRepository get _repo =>
      ref.read(notificationsRepositoryProvider);

  @override
  Future<NotificationFeed> build() async {
    final items = await _repo.getNotifications();
    return NotificationFeed(
      items: items,
      hasMore: items.length >= NotificationsRepository.pageSize,
    );
  }

  /// Re-fetch the first page. Used by pull-to-refresh, on app resume, and when a
  /// push arrives while the app is open — so a new notification shows up without
  /// a restart.
  Future<void> refresh() async {
    try {
      final items = await _repo.getNotifications();
      state = AsyncData(
        NotificationFeed(
          items: items,
          hasMore: items.length >= NotificationsRepository.pageSize,
        ),
      );
    } catch (error, stack) {
      // Only surface the failure when there is nothing to show; an established
      // list must not be replaced by an error because one refresh blipped.
      if (state.asData?.value == null) state = AsyncError(error, stack);
    }
    ref.invalidate(unreadNotificationsProvider);
  }

  /// Append the next page. No-op while one is in flight or the last page was
  /// short (meaning there is nothing older to fetch).
  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null ||
        !current.hasMore ||
        current.loadingMore ||
        current.items.isEmpty) {
      return;
    }
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final last = current.items.last;
      final next = await _repo.getNotifications(
        before: last.createdAt,
        beforeId: last.id,
      );
      final seen = {for (final n in current.items) n.id};
      state = AsyncData(
        NotificationFeed(
          items: [
            ...current.items,
            for (final n in next)
              if (seen.add(n.id)) n,
          ],
          hasMore: next.length >= NotificationsRepository.pageSize,
        ),
      );
    } catch (_) {
      // Keep what we have and let the user try again — a paging failure must not
      // discard the page they are already reading.
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }

  /// Mark one read. The row flips immediately, then reconciles with the server;
  /// a failure rolls the optimistic change back rather than leaving the UI
  /// claiming something the server never recorded.
  Future<void> markRead(String id) async {
    final current = state.asData?.value;
    if (current == null) return;
    final index = current.items.indexWhere((n) => n.id == id);
    if (index < 0 || current.items[index].isRead) return;
    final optimistic = [...current.items];
    optimistic[index] = optimistic[index].copyWith(isRead: true);
    state = AsyncData(current.copyWith(items: optimistic));
    try {
      await _repo.markRead(id);
    } catch (_) {
      state = AsyncData(current);
    }
    ref.invalidate(unreadNotificationsProvider);
  }

  /// Mark everything read.
  Future<void> markAllRead() async {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        items: [for (final n in current.items) n.copyWith(isRead: true)],
      ),
    );
    try {
      await _repo.markAllRead();
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
    ref.invalidate(unreadNotificationsProvider);
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, NotificationFeed>(
      NotificationsNotifier.new,
    );

/// The unread badge count, straight from the server so it stays correct however
/// long the feed is. Falls back to 0 while loading or on error — a badge is not
/// worth an error state.
final unreadNotificationsProvider = FutureProvider<int>((ref) async {
  try {
    return await ref.watch(notificationsRepositoryProvider).unreadCount();
  } catch (_) {
    return 0;
  }
});

/// Convenience for widgets that only want the number.
final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(unreadNotificationsProvider).asData?.value ?? 0;
});
