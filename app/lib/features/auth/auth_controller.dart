import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';

/// Outcome of a sign-up: signed straight in, created but awaiting email
/// confirmation, or failed (error is on the controller state).
enum SignUpResult { signedIn, needsConfirmation, failed }

/// Drives email/password + Google auth for the auth screen. Exposes an
/// `AsyncValue<void>` so the UI gets loading/error for free; methods return a
/// result so the screen can act on it. The backend re-verifies every token
/// (CLAUDE.md §11) — nothing here is trusted server-side.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> signInEmail(String email, String password) => _run(
    () => ref
        .read(authRepositoryProvider)
        .signInWithEmail(email: email, password: password),
  );

  /// Signs up; a session means signed in, no session means email confirmation is
  /// required (so the screen shouldn't pretend the user is logged in).
  Future<SignUpResult> signUpEmail(String email, String password) async {
    state = const AsyncLoading();
    try {
      final res = await ref
          .read(authRepositoryProvider)
          .signUpWithEmail(email: email, password: password);
      state = const AsyncData(null);
      return res.session != null
          ? SignUpResult.signedIn
          : SignUpResult.needsConfirmation;
    } on AuthException catch (error, st) {
      state = AsyncError(error.message, st);
      return SignUpResult.failed;
    } catch (error, st) {
      state = AsyncError(error, st);
      return SignUpResult.failed;
    }
  }

  Future<bool> signInWithGoogle() =>
      _run(() => ref.read(authRepositoryProvider).signInWithGoogle());

  /// Clear any error/loading state (e.g. when toggling sign-in ↔ sign-up).
  void clear() => state = const AsyncData(null);

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
