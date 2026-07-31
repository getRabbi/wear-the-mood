/// Read claims out of an OIDC ID token.
///
/// ⚠️ This does NOT verify the token. It does not check the signature, issuer,
/// audience or expiry, and nothing here may ever be used to decide whether a
/// token is trustworthy. Verification is Supabase's job, server-side, and it
/// still happens in full.
///
/// Two legitimate uses, both non-authoritative:
///   * comparing the `nonce` claim against the hash of the nonce THIS attempt
///     generated, so an unrelated token can be refused (see `oidc_nonce.dart`);
///   * privacy-safe diagnostics (see `auth_diagnostics.dart`).
///
/// It must never again be used to decide what to SEND to Supabase. Echoing an
/// unverified claim back makes the server's nonce check pass while proving
/// nothing about which sign-in the token came from.
library;

import 'dart:convert';

/// Every claim in [idToken]'s payload, or an empty map when it cannot be read.
///
/// Total by construction: a malformed, truncated, non-JWT or non-JSON input
/// returns empty rather than throwing. A sign-in must never crash because a
/// provider handed us a token shaped differently than expected.
Map<String, dynamic> claimsOf(String idToken) {
  // header.payload.signature — the payload is base64url, usually unpadded.
  final parts = idToken.split('.');
  if (parts.length != 3) return const {};

  try {
    final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final claims = jsonDecode(json);
    return claims is Map ? Map<String, dynamic>.from(claims) : const {};
  } on FormatException {
    return const {};
  } on ArgumentError {
    return const {};
  }
}

/// The `nonce` claim in [idToken], or null when the token carries none.
String? nonceClaimOf(String idToken) {
  final nonce = claimsOf(idToken)['nonce'];
  // An empty string is what GoTrue treats as "no nonce"; normalise to null so
  // both sides agree on absence.
  return (nonce is String && nonce.isNotEmpty) ? nonce : null;
}
