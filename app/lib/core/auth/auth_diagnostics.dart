/// Privacy-safe diagnostics for one sign-in attempt.
///
/// Nonce mismatches are impossible to debug from a device without SOME signal,
/// and equally impossible to debug safely if that signal leaks credentials. So
/// this emits booleans, lengths and truncated fingerprints — never a raw nonce,
/// a nonce claim, an ID token, an email, a subject or an audience.
///
/// A fingerprint is the first 8 hex chars of a SHA-256. That is enough to say
/// "these two values are the same one" across two log lines, and far too little
/// to reverse. Comparisons that actually matter are reported as booleans, so
/// nothing has to be reconstructed from fingerprints at all.
///
/// Gated on [enabled], which is off unless the build opted in — diagnostics are
/// for a diagnostic build, not for production.
library;

import 'package:flutter/foundation.dart';

import 'apple_nonce.dart';
import 'id_token_claims.dart';
import 'oidc_nonce.dart';

/// Whether sign-in diagnostics are emitted. Compile-time so a production build
/// strips the calls entirely.
const bool authDiagnosticsEnabled = bool.fromEnvironment(
  'AUTH_DIAGNOSTICS',
  defaultValue: false,
);

/// First 8 hex chars of the SHA-256 of [value] — an identity marker, not a
/// recoverable value. Null in, null out.
String? fingerprint(String? value) =>
    value == null ? null : sha256OfString(value).substring(0, 8);

/// Emit one structured line for a sign-in attempt.
///
/// [path] is which implementation ran: `native_ios`, `native_android` or
/// `browser_oauth`. [buildLabel] should carry version+build and the short
/// commit SHA so a report can be tied to an exact artifact.
void logSignInDiagnostics({
  required String provider,
  required String path,
  required String buildLabel,
  String? rawNonce,
  String? idToken,
  String? supabaseError,
  String? supabaseErrorCode,
}) {
  if (!authDiagnosticsEnabled) return;

  final tokenNonce = idToken == null ? null : nonceClaimOf(idToken);
  final claims = idToken == null
      ? const <String, dynamic>{}
      : claimsOf(idToken);

  final fields = <String, Object?>{
    'provider': provider,
    'path': path,
    'build': buildLabel,
    'platform': defaultTargetPlatform.name,
    // What we asked for.
    'raw_nonce_present': rawNonce != null,
    'raw_nonce_len': rawNonce?.length,
    'raw_nonce_fp': fingerprint(rawNonce),
    // What came back.
    'token_present': idToken != null,
    'token_nonce_present': tokenNonce != null,
    'token_nonce_len': tokenNonce?.length,
    'token_nonce_fp': fingerprint(tokenNonce),
    // The three relationships that decide the whole handshake. Booleans only —
    // this is the entire diagnosis in three bits.
    if (rawNonce != null) ...{
      'nonce_eq_raw': tokenNonce == rawNonce,
      'nonce_eq_sha256_raw': tokenNonce == sha256OfString(rawNonce),
      'classification': classifyTokenNonce(
        rawNonce: rawNonce,
        tokenNonce: tokenNonce,
      ).name,
    },
    // Audience wiring, fingerprinted — enough to tell "wrong client id" from
    // "right client id", without publishing either.
    'has_aud': claims['aud'] != null,
    'aud_fp': fingerprint(claims['aud'] as String?),
    'has_azp': claims['azp'] != null,
    'azp_fp': fingerprint(claims['azp'] as String?),
    'has_iss': claims['iss'] != null,
    // `iss` is a fixed public constant (accounts.google.com), so it is safe
    // whole and is the fastest way to spot a token from the wrong provider.
    'iss': claims['iss'],
    'supabase_error': ?supabaseError,
    'supabase_error_code': ?supabaseErrorCode,
  };

  debugPrint(
    'AUTH_DIAG ${fields.entries.where((e) => e.value != null).map((e) => '${e.key}=${e.value}').join(' ')}',
  );
}
