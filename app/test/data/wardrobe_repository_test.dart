import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';

import '../helpers/fake_dio.dart';

void main() {
  test(
    'uploadCutoutMask PUTs one multipart mask and parses the item',
    () async {
      final (dio, adapter) = fakeDio(
        (_) => jsonResponse({
          'id': 'w1',
          'cutout_status': 'done',
          'cutout_url': 'https://cdn/c.png',
        }),
      );

      final item = await WardrobeRepository(
        dio,
      ).uploadCutoutMask('w1', Uint8List.fromList([1, 2, 3, 4]));

      expect(item.id, 'w1');
      expect(item.cutoutUrl, 'https://cdn/c.png');
      final req = adapter.lastRequest!;
      expect(req.method, 'PUT');
      expect(req.path, '/v1/wardrobe/w1/cutout-mask');
      // Exactly one multipart file, field name "mask".
      final form = req.data as FormData;
      expect(form.files, hasLength(1));
      expect(form.files.first.key, 'mask');
    },
  );

  test('uploadCutoutMask surfaces a backend error as ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {'code': 'NOT_FOUND', 'message': 'Not found.'},
      }, status: 404),
    );

    expect(
      () => WardrobeRepository(dio).uploadCutoutMask('w1', Uint8List(4)),
      throwsA(isA<ApiException>()),
    );
  });

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

  test('getGaps parses missing essentials', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse([
        {
          'category': 'Shoes',
          'title': 'Neutral shoes',
          'suggestion': 'versatile neutral shoes',
          'owned_count': 0,
        },
      ]),
    );

    final gaps = await WardrobeRepository(dio).getGaps();

    expect(gaps, hasLength(1));
    expect(gaps.first.title, 'Neutral shoes');
    expect(gaps.first.suggestion, 'versatile neutral shoes');
    expect(adapter.lastRequest!.path, '/v1/wardrobe/gaps');
  });
}
