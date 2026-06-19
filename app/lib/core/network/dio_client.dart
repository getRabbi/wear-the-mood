import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../env/app_env.dart';
import 'auth_interceptor.dart';

/// Configured Dio client for talking to the FastAPI backend, with auth
/// (token attach + 401 refresh) wired to the Supabase session.
final dioProvider = Provider<Dio>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  // Rebuild this client (and cascade-refresh every repository that depends on
  // it) whenever the signed-in identity changes, so cached data never lingers
  // from a previous user / guest across sign-in or sign-out (CLAUDE.md §11).
  ref.watch(authUserIdProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: AppEnv.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      accessToken: () => supabase.auth.currentSession?.accessToken,
      refreshToken: () async {
        // Swallow refresh failures (offline / expired / revoked) and report no
        // token, so the interceptor treats it as an auth failure rather than
        // throwing out of the error handler.
        try {
          final res = await supabase.auth.refreshSession();
          return res.session?.accessToken;
        } catch (_) {
          return null;
        }
      },
      onAuthFailure: () => ref.read(authRepositoryProvider).signOut(),
    ),
  );

  return dio;
});
