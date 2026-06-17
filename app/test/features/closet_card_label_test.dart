import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/features/wardrobe/closet_category.dart';
import 'package:app/l10n/app_localizations.dart';

/// Unit coverage for the shared item-card label fallback chain (the source of
/// the Home "Uncategorized after categorizing" bug): smart name → drawer →
/// "Needs category", never a plain "Uncategorized".
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('uses the item title when present', () {
    const item = WardrobeItem(id: '1', title: 'White linen shirt');
    expect(closetCardLabel(l10n, item), 'White linen shirt');
  });

  test('falls back to the capitalized category when there is no title', () {
    const item = WardrobeItem(id: '1', category: 'tops');
    expect(closetCardLabel(l10n, item), 'Tops');
    expect(closetCardLabel(l10n, item), isNot('Uncategorized'));
  });

  test('title wins over category', () {
    const item = WardrobeItem(id: '1', title: 'Fav tee', category: 'tops');
    expect(closetCardLabel(l10n, item), 'Fav tee');
  });

  test('falls back to the drawer name when title and category are missing', () {
    const item = WardrobeItem(id: '1');
    expect(closetCardLabel(l10n, item, drawerName: 'Hijab'), 'Hijab');
  });

  test('shows "Needs category" when nothing is known', () {
    const item = WardrobeItem(id: '1');
    expect(closetCardLabel(l10n, item), l10n.closetNeedsCategory);
    expect(closetCardLabel(l10n, item), isNot('Uncategorized'));
  });

  test('blank title/category are treated as missing', () {
    const item = WardrobeItem(id: '1', title: '  ', category: '  ');
    expect(closetCardLabel(l10n, item, drawerName: 'Pants'), 'Pants');
  });
}
