import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/repositories/notifications_repository.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _notif(String id, {bool read = false}) => {
  'id': id,
  'actor_id': 'u2',
  'type': 'follow',
  'title': 'Mim started following you',
  'is_read': read,
  'created_at': '2026-06-16T10:00:00Z',
};

void main() {
  test('getNotifications parses the feed', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse([_notif('n1'), _notif('n2', read: true)]),
    );
    final list = await NotificationsRepository(dio).getNotifications();
    expect(list, hasLength(2));
    expect(list.first.id, 'n1');
    expect(list.first.type, 'follow');
    expect(list.first.isRead, isFalse);
    expect(list[1].isRead, isTrue);
    expect(adapter.lastRequest!.path, '/v1/notifications');
  });

  test('markRead / markAllRead hit the right paths', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse(<String, Object>{}, status: 204),
    );
    final repo = NotificationsRepository(dio);

    await repo.markRead('n1');
    expect(adapter.lastRequest!.path, '/v1/notifications/n1/read');
    expect(adapter.lastRequest!.method, 'POST');

    await repo.markAllRead();
    expect(adapter.lastRequest!.path, '/v1/notifications/read-all');
  });
}
