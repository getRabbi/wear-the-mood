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
    this.onAuthFailure,
  });

  final Dio dio;
  final String? Function() accessToken;
  final Future<String?> Function() refreshToken;

  /// Invoked when a 401 cannot be recovered because the refresh produced no
  /// token — i.e. the session is dead. The app signs out so it drops cleanly to
  /// guest instead of stranding the user on a 401'd screen (CLAUDE.md §11).
  final Future<void> Function()? onAuthFailure;

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
      // Refresh failed → the session can't be recovered. Sign out so the app
      // returns to a clean guest state rather than looping on 401s. We only do
      // this after attempting a refresh (the "only then sign-out" rule, §11).
      await onAuthFailure?.call();
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
