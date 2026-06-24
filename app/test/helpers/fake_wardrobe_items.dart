import 'dart:async';

import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';

/// Stub for [wardrobeItemsProvider] returning a fixed closet with NO live polling
/// — for widget tests that just need wardrobe data. Use as:
///   wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(items))
class FakeWardrobeItemsNotifier extends WardrobeItemsNotifier {
  FakeWardrobeItemsNotifier(this._items);

  final List<WardrobeItem> _items;

  @override
  Future<List<WardrobeItem>> build() async => _items;
}

/// Stub whose load never completes — for loading-state tests.
class LoadingWardrobeItemsNotifier extends WardrobeItemsNotifier {
  @override
  Future<List<WardrobeItem>> build() => Completer<List<WardrobeItem>>().future;
}
