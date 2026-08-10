import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';

/// Closet paging.
///
/// `GET /v1/wardrobe` used to hand back up to 500 items in one response — every
/// row resolved and every private URL signed — for a screen showing twelve
/// tiles. Paging is ADDITIVE on both sides, so a shipped client that sends no
/// parameters still gets what it always got; these cover the new client.
class _PagingRepo implements WardrobeRepository {
  _PagingRepo(this.total, {this.failAfterPage});

  final int total;

  /// Page index (0-based) whose fetch throws, to prove a lost page is survivable.
  final int? failAfterPage;

  final calls = <({int? limit, DateTime? before})>[];

  WardrobeItem _item(int i) => WardrobeItem(
    id: 'w$i',
    title: 'Piece $i',
    // Newest first: descending timestamps.
    createdAt: DateTime.utc(2026, 1, 1).subtract(Duration(minutes: i)),
  );

  @override
  Future<List<WardrobeItem>> getItems({int? limit, DateTime? before}) async {
    calls.add((limit: limit, before: before));
    if (failAfterPage != null && calls.length - 1 == failAfterPage) {
      throw StateError('page fetch failed');
    }
    final all = [for (var i = 0; i < total; i++) _item(i)];
    final page = before == null
        ? all
        : [
            for (final it in all)
              if (it.createdAt!.isBefore(before)) it,
          ];
    return page.take(limit ?? 500).toList();
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

ProviderContainer boot(WardrobeRepository repo) {
  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [wardrobeRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  const page = WardrobeRepository.pageSize;

  test('the first load asks for ONE page, not the whole closet', () async {
    final repo = _PagingRepo(page * 3);
    final container = boot(repo);

    final items = await container.read(wardrobeItemsProvider.future);

    expect(items.length, page);
    expect(repo.calls.single.limit, page);
    expect(
      repo.calls.single.before,
      isNull,
      reason: 'the first page has no cursor',
    );
  });

  test(
    'loadMore appends the next page using the oldest item as the cursor',
    () async {
      final repo = _PagingRepo(page * 3);
      final container = boot(repo);
      final first = await container.read(wardrobeItemsProvider.future);

      await container.read(wardrobeItemsProvider.notifier).loadMore();

      final items = container.read(wardrobeItemsProvider).requireValue;
      expect(items.length, page * 2);
      expect(repo.calls.last.before, first.last.createdAt);
      // Order is preserved and nothing is duplicated.
      expect(items.map((i) => i.id).toSet().length, items.length);
      expect(items.first.id, 'w0');
    },
  );

  test('paging stops once a short page comes back', () async {
    final repo = _PagingRepo(page + 5);
    final container = boot(repo);
    await container.read(wardrobeItemsProvider.future);
    final notifier = container.read(wardrobeItemsProvider.notifier);

    await notifier.loadMore();
    expect(container.read(wardrobeItemsProvider).requireValue.length, page + 5);
    expect(notifier.hasMore, isFalse);

    final before = repo.calls.length;
    await notifier.loadMore();
    expect(
      repo.calls.length,
      before,
      reason: 'an exhausted closet must stop asking',
    );
  });

  test('overlapping loadMore calls issue ONE request', () async {
    // A scroll notification fires constantly; duplicate pages would be free
    // network for nothing.
    final repo = _PagingRepo(page * 3);
    final container = boot(repo);
    await container.read(wardrobeItemsProvider.future);
    final notifier = container.read(wardrobeItemsProvider.notifier);

    await Future.wait([
      notifier.loadMore(),
      notifier.loadMore(),
      notifier.loadMore(),
    ]);

    expect(repo.calls.length, 2, reason: 'first page + exactly one more');
  });

  test('a failed page keeps what is on screen and can be retried', () async {
    final repo = _PagingRepo(page * 3, failAfterPage: 1);
    final container = boot(repo);
    await container.read(wardrobeItemsProvider.future);
    final notifier = container.read(wardrobeItemsProvider.notifier);

    await notifier.loadMore(); // throws internally

    final items = container.read(wardrobeItemsProvider);
    expect(
      items.hasError,
      isFalse,
      reason: 'never blank the closet over a page',
    );
    expect(items.requireValue.length, page);

    await notifier.loadMore(); // the next scroll tries again
    expect(container.read(wardrobeItemsProvider).requireValue.length, page * 2);
  });

  test('refresh returns to the first page without blanking the grid', () async {
    final repo = _PagingRepo(page * 3);
    final container = boot(repo);
    await container.read(wardrobeItemsProvider.future);
    final notifier = container.read(wardrobeItemsProvider.notifier);
    await notifier.loadMore();

    await notifier.refresh();

    final items = container.read(wardrobeItemsProvider).requireValue;
    expect(items.length, page);
    expect(repo.calls.last.before, isNull);
    expect(notifier.hasMore, isTrue);
  });

  test('an empty closet never pages', () async {
    final repo = _PagingRepo(0);
    final container = boot(repo);
    await container.read(wardrobeItemsProvider.future);

    await container.read(wardrobeItemsProvider.notifier).loadMore();

    expect(repo.calls.length, 1);
  });
}
