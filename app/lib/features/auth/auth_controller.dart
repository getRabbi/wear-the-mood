import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';

/// Outcome of a sign-up: signed straight in, created but awaiting email
/// confirmation, the email already has an account, or failed (a mapped error is
/// on the controller state).
enum SignUpResult { signedIn, needsConfirmation, alreadyRegistered, failed }

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

  /// Signs up. A session means signed in; no session means email confirmation is
  /// required (so the screen shouldn't pretend the user is logged in). Supabase's
  /// anti-enumeration returns a user with EMPTY [identities] (and no session)
  /// when the email already has an account — distinguished here so the UI can say
  /// "already registered, sign in instead" rather than "check your email".
  Future<SignUpResult> signUpEmail(String email, String password) async {
    state = const AsyncLoading();
    try {
      final res = await ref
          .read(authRepositoryProvider)
          .signUpWithEmail(email: email, password: password);
      state = const AsyncData(null);
      if (res.session != null) return SignUpResult.signedIn;
      final identities = res.user?.identities;
      if (identities != null && identities.isEmpty) {
        return SignUpResult.alreadyRegistered;
      }
      return SignUpResult.needsConfirmation;
    } on AuthException catch (error, st) {
      state = AsyncError(error, st);
      // With email confirmation OFF, an existing email surfaces as an error.
      final code = error.code?.toLowerCase() ?? '';
      final msg = error.message.toLowerCase();
      if (code.contains('already') ||
          code.contains('email_exists') ||
          msg.contains('already registered')) {
        return SignUpResult.alreadyRegistered;
      }
      return SignUpResult.failed;
    } catch (error, st) {
      state = AsyncError(error, st);
      return SignUpResult.failed;
    }
  }

  Future<bool> signInWithGoogle() =>
      _run(() => ref.read(authRepositoryProvider).signInWithGoogle());

  /// Native Sign in with Apple (offered on iOS only). Returns true once the
  /// Supabase session exists; false covers both user-cancel and failure (a
  /// mapped error lands on the controller state for the failure case).
  Future<bool> signInWithApple() async {
    state = const AsyncLoading();
    try {
      final signedIn = await ref.read(authRepositoryProvider).signInWithApple();
      state = const AsyncData(null);
      return signedIn;
    } on AuthException catch (error, st) {
      state = AsyncError(error, st);
      return false;
    } catch (error, st) {
      state = AsyncError(error, st);
      return false;
    }
  }

  /// Sends a password-reset email (Forgot password?). Surfaces loading/error
  /// through the controller state like the other actions.
  Future<bool> sendPasswordReset(String email) =>
      _run(() => ref.read(authRepositoryProvider).sendPasswordReset(email));

  /// Clear any error/loading state (e.g. when toggling sign-in ↔ sign-up).
  void clear() => state = const AsyncData(null);

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
      return true;
    } on AuthException catch (error, st) {
      // Keep the structured exception (not just its message) so the UI can map
      // it to a clear, localized error (CLAUDE.md §13).
      state = AsyncError(error, st);
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
