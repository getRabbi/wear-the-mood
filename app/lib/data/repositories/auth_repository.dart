import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/apple_nonce.dart';
import '../../core/auth/auth_diagnostics.dart';
import '../../core/auth/id_token_claims.dart';
import '../../core/auth/oidc_nonce.dart';
import '../../core/env/app_env.dart';

/// Thin wrapper over Supabase auth: email + Google everywhere, native Sign in
/// with Apple on iOS (App Store guideline 4.8). All token handling stays
/// server-trusted — the backend re-verifies the JWT (CLAUDE.md §11).
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

  /// Google sign-in. Prefers the **native** account picker (google_sign_in v7 →
  /// Supabase `signInWithIdToken`): no browser hop, and it sidesteps the
  /// "unverified app / access blocked" wall for basic email+profile scopes.
  /// Falls back to the system-browser OAuth flow when the native client isn't
  /// configured yet (`GOOGLE_WEB_CLIENT_ID` empty) or the platform can't do it.
  /// `GoogleSignIn.initialize` is documented as a once-only call, and its tail
  /// subscribes to the platform's `authenticationEvents` — so re-running it per
  /// attempt risks stacking a listener. It is therefore guarded here, and the
  /// PER-ATTEMPT nonce is applied through `GoogleSignInPlatform.instance.init`
  /// instead: the same public entry point `initialize` delegates to, minus the
  /// stream wiring. Both pinned implementations
  /// (google_sign_in_ios 6.3.0 / google_sign_in_android 7.2.13) store
  /// `params.nonce` there and read it back on the next `authenticate()`.
  bool _googleInitialized = false;

  /// Serialises sign-in attempts. Two rapid taps would otherwise run two
  /// interleaved flows: the second `init` would overwrite the first's nonce, and
  /// the first token would come back bound to a nonce we had already discarded.
  Future<void>? _googleInFlight;

  Future<bool> signInWithGoogle() async {
    // A second tap joins the in-flight attempt rather than starting a rival one.
    final inFlight = _googleInFlight;
    if (inFlight != null) {
      await inFlight;
      return _auth.currentSession != null;
    }
    final attempt = _signInWithGoogle();
    _googleInFlight = attempt.then((_) {}, onError: (_, _) {});
    try {
      return await attempt;
    } finally {
      _googleInFlight = null;
    }
  }

  Future<bool> _signInWithGoogle() async {
    final webClientId = AppEnv.googleWebClientId;
    final google = GoogleSignIn.instance;

    if (webClientId.isNotEmpty && google.supportsAuthenticate()) {
      try {
        // THE NONCE HANDSHAKE. Verified against the pinned sources, not guessed
        // (full derivation in core/auth/oidc_nonce.dart):
        //
        //   * gotrue 2.21.0 forwards `nonce` VERBATIM and documents the server
        //     as comparing "its hash" to the token claim — i.e. the check is
        //     sha256(nonce_argument) == idToken.nonce, done server-side;
        //   * google_sign_in_ios 6.3.0 hands our nonce straight to
        //     `signInWithPresentingViewController:...nonce:`, and OIDC providers
        //     echo the request nonce into the token UNHASHED.
        //
        // So the provider must receive sha256Hex(raw) and Supabase the raw —
        // the same shape Sign in with Apple has always used here, which is
        // precisely why that path works and this one did not.
        //
        // The previous code sent the RAW nonce to Google and then echoed the
        // token's claim (also raw) back to Supabase, which hashed it and
        // compared sha256(raw) against raw. That cannot match: a deterministic
        // "Nonce mismatch" on every attempt where the token carried a nonce.
        //
        // Apple is deliberately NOT routed through here. Only the nonce
        // representation is shared; the handshakes around it are not
        // interchangeable and stay separate.
        final rawNonce = generateAppleNonce();
        if (!_googleInitialized) {
          await google.initialize(serverClientId: webClientId);
          _googleInitialized = true;
        }
        // Per-attempt nonce without re-running initialize's stream wiring.
        await GoogleSignInPlatform.instance.init(
          InitParameters(
            serverClientId: webClientId,
            nonce: sha256OfString(rawNonce),
          ),
        );
        final account = await google.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          throw const AuthException('Google sign-in returned no ID token.');
        }

        final tokenNonce = nonceClaimOf(idToken);
        logSignInDiagnostics(
          provider: 'google',
          path: google.supportsAuthenticate() ? 'native' : 'browser_oauth',
          buildLabel: AppEnv.buildLabel,
          rawNonce: rawNonce,
          idToken: idToken,
        );

        final String? supabaseNonce;
        try {
          // Sends the raw nonce ONLY when the token provably carries
          // sha256Hex(raw); null when it carries no claim (Supabase's supported
          // nonce-less flow); refuses outright when the claim is someone
          // else's, rather than echoing it back and passing a check that would
          // then prove nothing.
          supabaseNonce = supabaseNonceFor(
            rawNonce: rawNonce,
            tokenNonce: tokenNonce,
          );
        } on StateError {
          throw const AuthException(
            'Google sign-in could not be verified. Please try again.',
          );
        }

        await _auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          nonce: supabaseNonce,
        );
        return true;
      } on GoogleSignInException catch (e) {
        // User dismissed the picker — not an error, just stop.
        if (e.code.name == 'canceled') return false;
        rethrow;
      }
    }

    // Fallback: system-browser OAuth (deep-links back via [_oauthRedirect]).
    // signInWithOAuth only LAUNCHES the browser — sign-in completes later when
    // the deep link returns and the auth stream emits `signedIn`. Report "not
    // signed in yet" so the UI doesn't prematurely treat the user as
    // authenticated; the auth-state listener closes the auth screen once the
    // session actually arrives (CLAUDE.md §23).
    await _auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirect,
    );
    return false;
  }

  /// Native Sign in with Apple (iOS only — the WTM auth screen only offers it
  /// there). Uses the standard Supabase nonce flow: Apple gets the SHA-256 of
  /// a one-shot nonce, Supabase gets the raw nonce with the identity token and
  /// verifies the pair. Returns false when the user dismissed the Apple sheet.
  ///
  /// Account behavior: Supabase signs into the existing account when the
  /// Apple-verified email matches one (no duplicate profile); "Hide My Email"
  /// relay addresses create their own account, as designed. Apple returns the
  /// user's name ONLY on first authorization, so it is persisted exactly then.
  Future<bool> signInWithApple() async {
    final rawNonce = generateAppleNonce();
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256OfString(rawNonce),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      // User closed the Apple sheet — not an error, just stop.
      if (e.code == AuthorizationErrorCode.canceled) return false;
      throw AuthException('Apple sign-in failed: ${e.code.name}');
    }

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple sign-in returned no identity token.');
    }
    await _auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // First-authorization-only name: persist it while Apple still provides it.
    final fullName = [
      credential.givenName,
      credential.familyName,
    ].whereType<String>().join(' ').trim();
    if (fullName.isNotEmpty) {
      try {
        await _auth.updateUser(UserAttributes(data: {'full_name': fullName}));
      } catch (_) {
        // Best-effort — the session is already valid without the name.
      }
    }
    return true;
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
