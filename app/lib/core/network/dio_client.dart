import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../env/app_env.dart';
import 'auth_interceptor.dart';

/// Configured Dio client for talking to the FastAPI backend, with auth
/// (token attach + 401 refresh) wired to the Supabase session.
final dioProvider = Provider<Dio>((ref) {
  final supabase = ref.watch(supabaseClientProvider);

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
        final res = await supabase.auth.refreshSession();
        return res.session?.accessToken;
      },
    ),
  );

  return dio;
});
