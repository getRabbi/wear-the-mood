import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/apple_nonce.dart';
import '../../core/auth/id_token_claims.dart';
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
  Future<bool> signInWithGoogle() async {
    final webClientId = AppEnv.googleWebClientId;
    final google = GoogleSignIn.instance;

    if (webClientId.isNotEmpty && google.supportsAuthenticate()) {
      try {
        // Supabase rejects the token unless the `nonce` we pass and the `nonce`
        // claim inside the ID token either BOTH exist or BOTH don't, and then
        // that they MATCH. Both halves were observed failing on a real iPhone:
        //
        //   passing nothing  -> "Passed nonce and nonce in id_token should
        //                        either both exist or not"   (token HAD one)
        //   passing our own  -> "Nonce mismatch"             (token had ANOTHER)
        //
        // Together those prove the iOS token always carries a nonce and it is
        // never the one we asked for, even though google_sign_in_ios 6.3.0 does
        // forward `nonce:` all the way to
        // `signInWithPresentingViewController:hint:additionalScopes:nonce:`.
        // Whatever the native SDK does with it, we cannot dictate the claim.
        //
        // So stop trying to predict it and READ it. Sending back exactly the
        // nonce the token carries makes both failure modes structurally
        // impossible on every platform: present-and-equal when a nonce exists,
        // absent-on-both-sides when it does not (a null `nonce` is sent as JSON
        // null, which GoTrue reads as absent).
        //
        // We still REQUEST a fresh nonce per attempt, so on a platform that
        // honours it the token stays bound to this sign-in. Where the SDK
        // overrides it the nonce check degrades to a no-op -- the same posture
        // as Supabase's officially supported nonce-less id_token flow. Supabase
        // still verifies signature, issuer, audience and expiry server-side;
        // `nonceClaimOf` deliberately verifies nothing (see its doc comment).
        //
        // Apple is NOT routed through here: its token carries the SHA-256 while
        // Supabase needs the raw value, so [signInWithApple] keeps passing the
        // raw nonce it generated.
        //
        // `initialize` is the ONLY place the plugin accepts a nonce, so it is
        // re-run per attempt rather than guarded by a once-only flag: a nonce
        // reused across attempts would defeat the replay protection it exists
        // to provide, and Android DOES honour ours.
        //
        // google_sign_in documents calling `initialize` more than once as
        // "undefined behavior", so this is deliberate, not careless. The one
        // real hazard is its tail, which subscribes to the platform's
        // `authenticationEvents` and would stack a listener per call. Checked
        // against the pinned implementations: neither google_sign_in_ios 6.3.0
        // nor google_sign_in_android 7.2.13 overrides `authenticationEvents`,
        // so both inherit the platform-interface default of null, the package
        // takes its `_createAuthenticationStreamEvents` branch instead, and no
        // subscription is created on either platform we ship. The rest of
        // `init` just re-applies the nonce and re-runs an idempotent
        // `configure`. Re-verify this if google_sign_in is upgraded.
        final rawNonce = generateAppleNonce();
        await google.initialize(serverClientId: webClientId, nonce: rawNonce);
        final account = await google.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          throw const AuthException('Google sign-in returned no ID token.');
        }
        await _auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          nonce: nonceClaimOf(idToken),
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
