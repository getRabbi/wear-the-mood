import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper over Supabase auth. Google + email first (CLAUDE.md §23);
/// Apple Sign-In deferred to pre-iOS. All token handling stays server-trusted —
/// the backend re-verifies the JWT (CLAUDE.md §11).
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

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

  /// Google sign-in via Supabase OAuth (system-browser redirect, then deep-links
  /// back into the app). Requires the Google provider enabled in Supabase
  /// (client id/secret) + this redirect URL allow-listed there.
  Future<bool> signInWithGoogle() => _auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: _oauthRedirect,
  );

  Future<void> signOut() => _auth.signOut();
}
