import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/shop_repository.dart';

import '../helpers/fake_dio.dart';

void main() {
  test('shopLink sends the query and returns the url', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({
        'url': 'https://www.google.com/search?q=trench+coat',
        'label': 'Shop this trend',
        'query': 'trench coat',
      }),
    );

    final url = await ShopRepository(
      dio,
    ).shopLink('trench coat', label: 'Shop this trend');

    expect(url, contains('trench+coat'));
    expect(adapter.lastRequest!.path, '/v1/shop/link');
    expect(adapter.lastRequest!.queryParameters['q'], 'trench coat');
    expect(adapter.lastRequest!.queryParameters['label'], 'Shop this trend');
  });

  test('maps an error envelope to ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {'code': 'INTERNAL_ERROR', 'message': 'boom'},
      }, status: 500),
    );

    expect(
      () => ShopRepository(dio).shopLink('x'),
      throwsA(isA<ApiException>()),
    );
  });
}
