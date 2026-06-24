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

/// Serves a scripted sequence of `getItems()` responses; a `null` step throws to
/// simulate a transient fetch error. After the script is exhausted it repeats the
/// last step.
class _SeqRepo extends WardrobeRepository {
  _SeqRepo(this._steps) : super(Dio());

  final List<List<WardrobeItem>?> _steps;
  int calls = 0;

  @override
  Future<List<WardrobeItem>> getItems() async {
    final step = _steps[calls < _steps.length ? calls : _steps.length - 1];
    calls++;
    if (step == null) throw Exception('transient network error');
    return step;
  }
}

ProviderContainer _container(_SeqRepo repo) {
  final c = ProviderContainer(
    overrides: [
      wardrobeRepositoryProvider.overrideWithValue(repo),
      // Poll fast so the test doesn't wait real seconds.
      wardrobeCutoutPollIntervalProvider.overrideWithValue(
        const Duration(milliseconds: 10),
      ),
    ],
  );
  // Keep the auto-dispose provider alive for the duration of the test.
  c.listen(wardrobeItemsProvider, (_, _) {});
  return c;
}

bool _isProcessing(ProviderContainer c) =>
    c.read(wardrobeItemsProvider).value!.single.isProcessingCutout;

void main() {
  test('live-polls a processing cutout to done, then stops polling', () async {
    final repo = _SeqRepo([
      [_processing],
      [_done],
    ]);
    final c = _container(repo);
    addTearDown(c.dispose);

    // First load: still processing (the scrim would show).
    await c.read(wardrobeItemsProvider.future);
    expect(_isProcessing(c), isTrue);

    // Without leaving/re-entering, the poll flips it to done.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(_isProcessing(c), isFalse);
    expect(c.read(wardrobeItemsProvider).value!.single.cutoutUrl, 'cutout.png');

    // Everything is done → polling stops (no further fetches).
    final settled = repo.calls;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(repo.calls, settled);
  });

  test('tolerates a transient fetch error and keeps polling to done', () async {
    final repo = _SeqRepo([
      [_processing], // initial load
      null, // a poll throws — must NOT get stuck or surface an error
      [_done], // next poll recovers
    ]);
    final c = _container(repo);
    addTearDown(c.dispose);

    await c.read(wardrobeItemsProvider.future);
    expect(_isProcessing(c), isTrue);

    // Across the error tick the grid keeps its last good data (never errors)...
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(c.read(wardrobeItemsProvider).hasError, isFalse);
    // ...and the subsequent poll resolves to done.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(_isProcessing(c), isFalse);
  });

  test('does not poll at all when nothing is processing', () async {
    final repo = _SeqRepo([
      [_done],
    ]);
    final c = _container(repo);
    addTearDown(c.dispose);

    await c.read(wardrobeItemsProvider.future);
    final settled = repo.calls;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(repo.calls, settled); // no timer armed for an all-done closet
  });

  test('refresh() re-queries immediately and clears a stale processing row',
      () async {
    final repo = _SeqRepo([
      [_processing],
      [_done],
    ]);
    final c = _container(repo);
    addTearDown(c.dispose);

    await c.read(wardrobeItemsProvider.future);
    expect(_isProcessing(c), isTrue);

    await c.read(wardrobeItemsProvider.notifier).refresh();
    expect(_isProcessing(c), isFalse);
  });
}
