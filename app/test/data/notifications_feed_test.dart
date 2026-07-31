import 'package:app/data/models/app_notification.dart';
import 'package:app/data/repositories/notifications_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The paginated feed: keyset paging without duplicates, an accurate unread
/// count that comes from the SERVER rather than the loaded page, and optimistic
/// mark-as-read that rolls back when the server rejects it.
class _FakeRepo implements NotificationsRepository {
  _FakeRepo(this.pages);

  /// Pages, in the order they will be served.
  final List<List<AppNotification>> pages;
  final List<Map<String, Object?>> calls = [];
  final List<String> read = [];
  bool allRead = false;
  int unread = 0;
  bool failMarkRead = false;
  bool failNextPage = false;

  @override
  Future<List<AppNotification>> getNotifications({
    int limit = NotificationsRepository.pageSize,
    DateTime? before,
    String? beforeId,
  }) async {
    calls.add({'before': before, 'beforeId': beforeId});
    if (failNextPage && before != null) throw StateError('network');
    // Each call consumes the next scripted page, so a refresh sees fresh data
    // rather than replaying the first page.
    final index = calls.length - 1;
    return index < pages.length ? pages[index] : const [];
  }

  @override
  Future<int> unreadCount() async => unread;

  @override
  Future<void> markRead(String id) async {
    if (failMarkRead) throw StateError('server rejected');
    read.add(id);
  }

  @override
  Future<void> markAllRead() async => allRead = true;
}

AppNotification _n(String id, {bool isRead = false, int minute = 0}) {
  return AppNotification(
    id: id,
    type: 'like',
    title: id,
    isRead: isRead,
    createdAt: DateTime.utc(2026, 7, 31, 12, minute),
  );
}

ProviderContainer _container(_FakeRepo repo) {
  final container = ProviderContainer(
    overrides: [notificationsRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

/// A full page means "there may be more"; anything shorter ends the feed.
List<AppNotification> _fullPage(String prefix) => [
  for (var i = 0; i < NotificationsRepository.pageSize; i++)
    _n('$prefix$i', minute: i),
];

void main() {
  test('the first page loads and reports whether more remain', () async {
    final repo = _FakeRepo([_fullPage('a')]);
    final container = _container(repo);

    final feed = await container.read(notificationsProvider.future);
    expect(feed.items, hasLength(NotificationsRepository.pageSize));
    expect(feed.hasMore, isTrue);
    expect(repo.calls.single['before'], isNull); // first page carries no cursor
  });

  test('a short first page means there is nothing to page to', () async {
    final container = _container(
      _FakeRepo([
        [_n('a'), _n('b')],
      ]),
    );

    final feed = await container.read(notificationsProvider.future);
    expect(feed.hasMore, isFalse);
  });

  test('loadMore sends the keyset cursor and appends', () async {
    final repo = _FakeRepo([
      _fullPage('a'),
      [_n('b0', minute: 40), _n('b1', minute: 41)],
    ]);
    final container = _container(repo);
    await container.read(notificationsProvider.future);

    await container.read(notificationsProvider.notifier).loadMore();

    final feed = container.read(notificationsProvider).value!;
    expect(feed.items, hasLength(NotificationsRepository.pageSize + 2));
    expect(feed.hasMore, isFalse); // short page ends it
    // The cursor is the LAST row already held — both halves of it, so rows
    // sharing a timestamp cannot be skipped or repeated.
    expect(
      repo.calls.last['beforeId'],
      'a${NotificationsRepository.pageSize - 1}',
    );
    expect(repo.calls.last['before'], isNotNull);
  });

  test('a row repeated across pages is not rendered twice', () async {
    final first = _fullPage('a');
    final repo = _FakeRepo([
      first,
      // The server re-sends the boundary row (what a naive timestamp cursor
      // does when several rows share a timestamp).
      [first.last, _n('b1', minute: 90)],
    ]);
    final container = _container(repo);
    await container.read(notificationsProvider.future);

    await container.read(notificationsProvider.notifier).loadMore();

    final ids = container
        .read(notificationsProvider)
        .value!
        .items
        .map((n) => n.id)
        .toList();
    expect(ids.toSet(), hasLength(ids.length), reason: 'no duplicate ids');
  });

  test('a failed page keeps the page already being read', () async {
    final repo = _FakeRepo([_fullPage('a')])..failNextPage = true;
    final container = _container(repo);
    await container.read(notificationsProvider.future);

    await container.read(notificationsProvider.notifier).loadMore();

    final feed = container.read(notificationsProvider).value!;
    expect(feed.items, hasLength(NotificationsRepository.pageSize));
    expect(feed.loadingMore, isFalse); // available to retry
  });

  test('mark-as-read flips the row and refreshes the badge', () async {
    final repo = _FakeRepo([
      [_n('a'), _n('b')],
    ])..unread = 2;
    final container = _container(repo);
    await container.read(notificationsProvider.future);
    expect(await container.read(unreadNotificationsProvider.future), 2);

    repo.unread = 1;
    await container.read(notificationsProvider.notifier).markRead('a');

    final feed = container.read(notificationsProvider).value!;
    expect(feed.items.firstWhere((n) => n.id == 'a').isRead, isTrue);
    expect(feed.items.firstWhere((n) => n.id == 'b').isRead, isFalse);
    expect(repo.read, ['a']);
    expect(await container.read(unreadNotificationsProvider.future), 1);
  });

  test('a rejected mark-as-read rolls the row back', () async {
    final repo = _FakeRepo([
      [_n('a')],
    ])..failMarkRead = true;
    final container = _container(repo);
    await container.read(notificationsProvider.future);

    await container.read(notificationsProvider.notifier).markRead('a');

    // The UI must not claim something the server never recorded.
    expect(
      container.read(notificationsProvider).value!.items.single.isRead,
      isFalse,
    );
  });

  test('marking one already-read row is a no-op', () async {
    final repo = _FakeRepo([
      [_n('a', isRead: true)],
    ]);
    final container = _container(repo);
    await container.read(notificationsProvider.future);

    await container.read(notificationsProvider.notifier).markRead('a');
    expect(repo.read, isEmpty);
  });

  test('mark-all-read flips every row', () async {
    final repo = _FakeRepo([
      [_n('a'), _n('b')],
    ]);
    final container = _container(repo);
    await container.read(notificationsProvider.future);

    await container.read(notificationsProvider.notifier).markAllRead();

    expect(repo.allRead, isTrue);
    expect(
      container.read(notificationsProvider).value!.items.every((n) => n.isRead),
      isTrue,
    );
  });

  test('the unread count comes from the server, not the loaded page', () async {
    // One page loaded, but the account has far more unread than fit on it.
    final repo = _FakeRepo([
      [_n('a'), _n('b')],
    ])..unread = 137;
    final container = _container(repo);
    await container.read(notificationsProvider.future);

    expect(await container.read(unreadNotificationsProvider.future), 137);
  });

  test('refresh replaces the list without a restart', () async {
    final repo = _FakeRepo([
      [_n('a')],
      [_n('new'), _n('a')],
    ]);
    final container = _container(repo);
    await container.read(notificationsProvider.future);

    // What a foreground push triggers.
    await container.read(notificationsProvider.notifier).refresh();

    expect(container.read(notificationsProvider).value!.items.first.id, 'new');
  });
}
