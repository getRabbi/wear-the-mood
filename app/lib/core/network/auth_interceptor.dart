import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Attaches the current access token to outgoing requests and, on a 401,
/// refreshes the session once and retries (CLAUDE.md §11).
///
/// Decoupled from Supabase via callbacks so the logic is unit-testable.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.accessToken,
    required this.refreshToken,
  });

  final Dio dio;
  final String? Function() accessToken;
  final Future<String?> Function() refreshToken;

  static const _retriedKey = 'auth_retried';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    applyToken(options, accessToken());
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!shouldRefresh(err)) {
      handler.next(err);
      return;
    }

    final newToken = await refreshToken();
    if (newToken == null || newToken.isEmpty) {
      handler.next(err);
      return;
    }

    final options = err.requestOptions
      ..headers['Authorization'] = 'Bearer $newToken'
      ..extra[_retriedKey] = true;
    try {
      final response = await dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  @visibleForTesting
  void applyToken(RequestOptions options, String? token) {
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
  }

  @visibleForTesting
  bool shouldRefresh(DioException err) {
    final isUnauthorized = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra[_retriedKey] == true;
    return isUnauthorized && !alreadyRetried;
  }
}
