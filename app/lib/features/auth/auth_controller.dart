import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';

/// Drives email/password + Google auth for the auth screen. Exposes an
/// `AsyncValue<void>` so the UI gets loading/error for free; methods return a
/// success bool so the screen can pop on success. The backend re-verifies every
/// token (CLAUDE.md §11) — nothing here is trusted server-side.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> signInEmail(String email, String password) => _run(
    () => ref
        .read(authRepositoryProvider)
        .signInWithEmail(email: email, password: password),
  );

  Future<bool> signUpEmail(String email, String password) => _run(
    () => ref
        .read(authRepositoryProvider)
        .signUpWithEmail(email: email, password: password),
  );

  Future<bool> signInWithGoogle() =>
      _run(() => ref.read(authRepositoryProvider).signInWithGoogle());

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
      return true;
    } on AuthException catch (error, st) {
      state = AsyncError(error.message, st);
      return false;
    } catch (error, st) {
      state = AsyncError(error, st);
      return false;
    }
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);
