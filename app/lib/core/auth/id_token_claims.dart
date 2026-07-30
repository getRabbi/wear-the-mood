/// Read a single claim out of an OIDC ID token, for the Supabase
/// `signInWithIdToken` nonce handshake.
///
/// ⚠️ This does NOT verify the token. It does not check the signature, issuer,
/// audience or expiry, and nothing here may ever be used to decide whether a
/// token is trustworthy. Verification is Supabase's job, server-side, and it
/// still happens in full. The only thing read here is the `nonce` claim, so the
/// value handed back to Supabase is the one the token actually carries.
library;

import 'dart:convert';

/// The `nonce` claim in [idToken], or null when the token carries none.
///
/// Total by construction: a malformed, truncated, non-JWT or non-JSON input
/// returns null rather than throwing. A sign-in must never crash because a
/// provider handed us a token shaped differently than expected.
String? nonceClaimOf(String idToken) {
  // header.payload.signature — the payload is base64url, usually unpadded.
  final parts = idToken.split('.');
  if (parts.length != 3) return null;

  try {
    final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final claims = jsonDecode(json);
    if (claims is! Map) return null;
    final nonce = claims['nonce'];
    // An empty string is what GoTrue treats as "no nonce"; normalise to null so
    // both sides agree on absence.
    return (nonce is String && nonce.isNotEmpty) ? nonce : null;
  } on FormatException {
    return null;
  }
}
