import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/packing_repository.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _body(dynamic data) =>
    (data is String ? jsonDecode(data) : data) as Map<String, dynamic>;

void main() {
  test('plan posts days/occasion and parses the list', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({
        'title': 'Packing for 3 days',
        'notes': '8 pieces for your trip.',
        'items': [
          {'id': 't1', 'title': 'Tee', 'image_url': 't1.jpg'},
          {'id': 'b1', 'title': 'Jeans', 'image_url': 'b1.jpg'},
        ],
      }),
    );

    final plan = await PackingRepository(dio).plan(days: 3, occasion: 'beach');

    expect(plan.title, 'Packing for 3 days');
    expect(plan.items, hasLength(2));
    expect(plan.items.first.id, 't1');
    expect(adapter.lastRequest!.path, '/v1/packing/plan');
    final body = _body(adapter.lastRequest!.data);
    expect(body['days'], 3);
    expect(body['occasion'], 'beach');
  });

  test('plan omits a null occasion', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({'title': 'T', 'notes': '', 'items': <Object>[]}),
    );
    await PackingRepository(dio).plan(days: 5);
    final body = _body(adapter.lastRequest!.data);
    expect(body['days'], 5);
    expect(body.containsKey('occasion'), isFalse);
  });

  test('maps an error envelope to ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {'code': 'UNAUTHENTICATED', 'message': 'no'},
      }, status: 401),
    );
    expect(
      () => PackingRepository(dio).plan(days: 3),
      throwsA(isA<ApiException>()),
    );
  });
}
