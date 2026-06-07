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

  /// Google sign-in via Supabase OAuth (system-browser redirect).
  ///
  /// Requires (founder/dashboard setup, before this works end-to-end):
  /// - Google provider enabled in the Supabase dashboard (client id/secret), and
  /// - a deep-link redirect configured (Android intent-filter + redirect URL).
  Future<bool> signInWithGoogle() =>
      _auth.signInWithOAuth(OAuthProvider.google);

  Future<void> signOut() => _auth.signOut();
}
