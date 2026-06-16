import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/features/wardrobe/closet_colors.dart';

void main() {
  group('resolveItemColor', () {
    test('uses the explicit color field first', () {
      const item = WardrobeItem(id: 'w1', color: 'Navy Blue');
      expect(resolveItemColor(item)?.key, 'blue');
    });

    test('falls back to tags / title / category when color is null', () {
      const byTag = WardrobeItem(id: 'w2', tags: ['olive', 'casual']);
      expect(resolveItemColor(byTag)?.key, 'green'); // olive -> green

      const byTitle = WardrobeItem(id: 'w3', title: 'Black hoodie');
      expect(resolveItemColor(byTitle)?.key, 'black');
    });

    test('returns null when no colour is detectable', () {
      const item = WardrobeItem(id: 'w4', title: 'My favourite piece');
      expect(resolveItemColor(item), isNull);
    });
  });

  group('closetColorCounts', () {
    test('counts only detectable colours, palette-ordered', () {
      const items = [
        WardrobeItem(id: '1', color: 'black'),
        WardrobeItem(id: '2', color: 'jet black'),
        WardrobeItem(id: '3', color: 'sky blue'),
        WardrobeItem(id: '4', title: 'mystery'), // undetectable -> excluded
      ];
      final counts = closetColorCounts(items);
      final map = {for (final e in counts) e.color.key: e.count};
      expect(map['black'], 2);
      expect(map['blue'], 1);
      expect(map.containsKey('green'), isFalse);
    });
  });

  group('itemMatchesColorFilter', () {
    test('null filter matches everything', () {
      const item = WardrobeItem(id: 'w1', color: 'red');
      expect(itemMatchesColorFilter(item, null), isTrue);
    });

    test('matches by resolved colour key', () {
      const red = WardrobeItem(id: 'w1', color: 'crimson');
      expect(itemMatchesColorFilter(red, 'red'), isTrue);
      expect(itemMatchesColorFilter(red, 'blue'), isFalse);
    });
  });
}
