import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/auth_interceptor.dart';

void main() {
  AuthInterceptor build({String? token}) => AuthInterceptor(
    dio: Dio(),
    accessToken: () => token,
    refreshToken: () async => null,
  );

  test('applyToken adds Authorization header when token present', () {
    final options = RequestOptions(path: '/x');
    build().applyToken(options, 'abc');
    expect(options.headers['Authorization'], 'Bearer abc');
  });

  test('applyToken adds nothing when token is null or empty', () {
    final options = RequestOptions(path: '/x');
    final interceptor = build();
    interceptor.applyToken(options, null);
    interceptor.applyToken(options, '');
    expect(options.headers.containsKey('Authorization'), isFalse);
  });

  test('shouldRefresh is true on a 401 not yet retried', () {
    final ro = RequestOptions(path: '/x');
    final err = DioException(
      requestOptions: ro,
      response: Response<dynamic>(requestOptions: ro, statusCode: 401),
    );
    expect(build().shouldRefresh(err), isTrue);
  });

  test('shouldRefresh is false when already retried', () {
    final ro = RequestOptions(path: '/x', extra: {'auth_retried': true});
    final err = DioException(
      requestOptions: ro,
      response: Response<dynamic>(requestOptions: ro, statusCode: 401),
    );
    expect(build().shouldRefresh(err), isFalse);
  });

  test('shouldRefresh is false on non-401 errors', () {
    final ro = RequestOptions(path: '/x');
    final err = DioException(
      requestOptions: ro,
      response: Response<dynamic>(requestOptions: ro, statusCode: 500),
    );
    expect(build().shouldRefresh(err), isFalse);
  });
}
