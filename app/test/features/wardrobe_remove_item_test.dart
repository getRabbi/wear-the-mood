import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';

import '../helpers/fake_wardrobe_items.dart';

/// Mobile QA #3: deleting a closet item drops it from the grid INSTANTLY via an
/// in-memory removal, instead of blocking on a full closet refetch.

const _a = WardrobeItem(id: 'a', title: 'Linen shirt');
const _b = WardrobeItem(id: 'b', title: 'Denim jacket');
const _c = WardrobeItem(id: 'c', title: 'Wool coat');

void main() {
  test('removeItem drops the item from state without a refetch', () async {
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(const [_a, _b, _c]),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Initial load.
    final loaded = await container.read(wardrobeItemsProvider.future);
    expect(loaded.map((i) => i.id).toList(), ['a', 'b', 'c']);

    container.read(wardrobeItemsProvider.notifier).removeItem('b');

    final after = container.read(wardrobeItemsProvider).asData!.value;
    expect(after.map((i) => i.id).toList(), ['a', 'c']);
  });

  test('removeItem is a no-op for an unknown id', () async {
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(const [_a, _b]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(wardrobeItemsProvider.future);
    container.read(wardrobeItemsProvider.notifier).removeItem('zzz');

    final after = container.read(wardrobeItemsProvider).asData!.value;
    expect(after.map((i) => i.id).toList(), ['a', 'b']);
  });
}
