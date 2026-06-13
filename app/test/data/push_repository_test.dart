import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/push_repository.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _body(dynamic data) =>
    (data is String ? jsonDecode(data) : data) as Map<String, dynamic>;

void main() {
  test('registerToken PUTs the token + platform', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse(<String, Object>{}, status: 204),
    );

    await PushRepository(dio).registerToken('fcmtoken123');

    expect(adapter.lastRequest!.path, '/v1/profile/push-token');
    expect(adapter.lastRequest!.method, 'PUT');
    final body = _body(adapter.lastRequest!.data);
    expect(body['token'], 'fcmtoken123');
    expect(body['platform'], 'android');
  });

  test('deleteToken DELETEs with the token query', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse(<String, Object>{}, status: 204),
    );

    await PushRepository(dio).deleteToken('fcmtoken123');

    expect(adapter.lastRequest!.path, '/v1/profile/push-token');
    expect(adapter.lastRequest!.method, 'DELETE');
    expect(adapter.lastRequest!.queryParameters['token'], 'fcmtoken123');
  });

  test('maps an error envelope to ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {'code': 'UNAUTHENTICATED', 'message': 'no'},
      }, status: 401),
    );
    expect(
      () => PushRepository(dio).registerToken('x'),
      throwsA(isA<ApiException>()),
    );
  });
}
