import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/auth_interceptor.dart';

/// Returns a fixed HTTP status for every request, so we can drive the
/// interceptor's error path without real network.
class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);
  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('{}', status);

  @override
  void close({bool force = false}) {}
}

void main() {
  AuthInterceptor build({String? token}) => AuthInterceptor(
    dio: Dio(),
    accessToken: () => token,
    refreshToken: () async => null,
  );

  /// A Dio wired with the interceptor and a canned-status adapter.
  Dio dioReturning(int status, {required AuthInterceptor Function(Dio) make}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StatusAdapter(status);
    dio.interceptors.add(make(dio));
    return dio;
  }

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

  test('signs out when a 401 cannot be refreshed (dead session)', () async {
    var signedOut = false;
    final dio = dioReturning(
      401,
      make: (dio) => AuthInterceptor(
        dio: dio,
        accessToken: () => 'expired',
        refreshToken: () async => null, // refresh fails → session is dead
        onAuthFailure: () async => signedOut = true,
      ),
    );

    await expectLater(
      dio.get<dynamic>('/protected'),
      throwsA(isA<DioException>()),
    );
    expect(signedOut, isTrue);
  });

  test('does not sign out on a non-401 error', () async {
    var signedOut = false;
    final dio = dioReturning(
      500,
      make: (dio) => AuthInterceptor(
        dio: dio,
        accessToken: () => 'token',
        refreshToken: () async => null,
        onAuthFailure: () async => signedOut = true,
      ),
    );

    await expectLater(
      dio.get<dynamic>('/boom'),
      throwsA(isA<DioException>()),
    );
    expect(signedOut, isFalse);
  });
}
