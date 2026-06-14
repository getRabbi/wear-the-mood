import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env/app_env.dart';

/// Thin wrapper over Supabase auth. Google + email first (CLAUDE.md §23);
/// Apple Sign-In deferred to pre-iOS. All token handling stays server-trusted —
/// the backend re-verifies the JWT (CLAUDE.md §11).
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  // google_sign_in v7 wants `initialize()` called once per process.
  bool _googleInitialized = false;

  Session? get currentSession => _auth.currentSession;
  User? get currentUser => _auth.currentUser;
  Stream<AuthState> authStateChanges() => _auth.onAuthStateChange;

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) => _auth.signUp(email: email, password: password);

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) => _auth.signInWithPassword(email: email, password: password);

  /// Deep link the OAuth browser flow returns to. Must match the Android
  /// intent-filter (AndroidManifest) AND Supabase's "Redirect URLs" allowlist.
  static const _oauthRedirect = 'com.fashionos.app://login-callback/';

  /// Google sign-in. Prefers the **native** account picker (google_sign_in v7 →
  /// Supabase `signInWithIdToken`): no browser hop, and it sidesteps the
  /// "unverified app / access blocked" wall for basic email+profile scopes.
  /// Falls back to the system-browser OAuth flow when the native client isn't
  /// configured yet (`GOOGLE_WEB_CLIENT_ID` empty) or the platform can't do it.
  Future<bool> signInWithGoogle() async {
    final webClientId = AppEnv.googleWebClientId;
    final google = GoogleSignIn.instance;

    if (webClientId.isNotEmpty && google.supportsAuthenticate()) {
      try {
        if (!_googleInitialized) {
          await google.initialize(serverClientId: webClientId);
          _googleInitialized = true;
        }
        final account = await google.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          throw const AuthException('Google sign-in returned no ID token.');
        }
        await _auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
        );
        return true;
      } on GoogleSignInException catch (e) {
        // User dismissed the picker — not an error, just stop.
        if (e.code.name == 'canceled') return false;
        rethrow;
      }
    }

    // Fallback: system-browser OAuth (deep-links back via [_oauthRedirect]).
    return _auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirect,
    );
  }

  /// Changes the account email. Supabase sends a confirmation link to the new
  /// address; the change only takes effect once the user confirms it.
  Future<void> updateEmail(String email) =>
      _auth.updateUser(UserAttributes(email: email));

  /// Sets a new password for the signed-in user.
  Future<void> updatePassword(String password) =>
      _auth.updateUser(UserAttributes(password: password));

  /// Re-verifies the current password (re-authentication). Throws an
  /// [AuthException] if it's wrong — gate sensitive changes (password change)
  /// behind this so an open session alone can't reset the password (§11).
  Future<void> reauthenticate({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithPassword(email: email, password: password);
  }

  /// Emails a password-reset link that deep-links back into the app (handled as
  /// an `AuthChangeEvent.passwordRecovery`). Used by "Forgot password?".
  Future<void> sendPasswordReset(String email) =>
      _auth.resetPasswordForEmail(email, redirectTo: _oauthRedirect);

  Future<void> signOut() async {
    // Clear the native Google session too, so the next sign-in re-prompts.
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Best-effort; ignore if Google sign-in was never used.
    }
    await _auth.signOut();
  }
}
