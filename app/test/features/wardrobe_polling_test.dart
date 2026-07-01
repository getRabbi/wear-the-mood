import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';

const _processing = WardrobeItem(id: 'w1', cutoutStatus: 'processing');
const _done = WardrobeItem(
  id: 'w1',
  cutoutStatus: 'done',
  cutoutUrl: 'cutout.png',
);

/// Serves a scripted sequence of `getItems()` responses.
class _SeqRepo extends WardrobeRepository {
  _SeqRepo(this._steps) : super(Dio());

  final List<List<WardrobeItem>> _steps;
  int calls = 0;

  @override
  Future<List<WardrobeItem>> getItems() async {
    final step = _steps[calls < _steps.length ? calls : _steps.length - 1];
    calls++;
    return step;
  }
}

ProviderContainer _container(_SeqRepo repo) {
  final c = ProviderContainer(
    overrides: [wardrobeRepositoryProvider.overrideWithValue(repo)],
  );
  // Keep the auto-dispose provider alive for the duration of the test.
  c.listen(wardrobeItemsProvider, (_, _) {});
  return c;
}

void main() {
  // The closet no longer polls: pieces only ever land here already finished
  // (background removal + enhance run behind the add flow's progress sheet). So
  // the notifier just fetches and can be explicitly refreshed.
  test('build() fetches the closet once, no background polling', () async {
    final repo = _SeqRepo([
      [_processing],
    ]);
    final c = _container(repo);
    addTearDown(c.dispose);

    final items = await c.read(wardrobeItemsProvider.future);
    expect(items.single.id, 'w1');

    // No timer is armed — the call count stays put on its own.
    final settled = repo.calls;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(repo.calls, settled);
  });

  test('refresh() re-queries and swaps in the finished row', () async {
    final repo = _SeqRepo([
      [_processing],
      [_done],
    ]);
    final c = _container(repo);
    addTearDown(c.dispose);

    await c.read(wardrobeItemsProvider.future);
    expect(c.read(wardrobeItemsProvider).value!.single.cutoutUrl, isNull);

    await c.read(wardrobeItemsProvider.notifier).refresh();
    expect(c.read(wardrobeItemsProvider).value!.single.cutoutUrl, 'cutout.png');
  });
}
