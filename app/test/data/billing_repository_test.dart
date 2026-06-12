import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/billing_repository.dart';

import '../helpers/fake_dio.dart';

void main() {
  test('getEntitlement parses an active entitlement', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({
        'active': true,
        'product_id': 'annual',
        'store': 'play_store',
        'expires_at': '2026-07-01T00:00:00Z',
      }),
    );

    final ent = await BillingRepository(dio).getEntitlement();

    expect(ent.active, isTrue);
    expect(ent.productId, 'annual');
    expect(adapter.lastRequest!.path, '/v1/billing/entitlement');
  });

  test('getEntitlement defaults to inactive', () async {
    final (dio, _) = fakeDio((_) => jsonResponse({'active': false}));
    final ent = await BillingRepository(dio).getEntitlement();
    expect(ent.active, isFalse);
    expect(ent.productId, isNull);
  });

  test('maps an error envelope to ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {'code': 'UNAUTHENTICATED', 'message': 'no'},
      }, status: 401),
    );
    expect(
      () => BillingRepository(dio).getEntitlement(),
      throwsA(isA<ApiException>()),
    );
  });
}
