import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/repositories/wardrobe_repository.dart';

import '../helpers/fake_dio.dart';

void main() {
  test('getAnalytics parses the insights payload', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({
        'item_count': 3,
        'total_spend': 120.0,
        'total_wears': 8,
        'never_worn_count': 1,
        'avg_cost_per_wear': 15.0,
        'best_value': {
          'id': 'a',
          'title': 'Tee',
          'wear_count': 5,
          'cost_per_wear': 4.0,
        },
      }),
    );

    final a = await WardrobeRepository(dio).getAnalytics();

    expect(a.itemCount, 3);
    expect(a.totalSpend, 120.0);
    expect(a.bestValue!.costPerWear, 4.0);
    expect(adapter.lastRequest!.path, '/v1/wardrobe/analytics');
  });

  test('markWorn posts to the wear endpoint', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse(<String, Object>{}, status: 200),
    );

    await WardrobeRepository(dio).markWorn('w1');

    expect(adapter.lastRequest!.path, '/v1/wardrobe/w1/wear');
    expect(adapter.lastRequest!.method, 'POST');
  });
}
