/// The OIDC nonce handshake shared by every `signInWithIdToken` provider.
///
/// ## The contract, from the pinned sources
///
/// GoTrue does NOT hash on the client. `gotrue-2.21.0/lib/src/gotrue_client.dart`
/// forwards the `nonce` argument verbatim in the request body, and documents it
/// as: *"If the ID token contains a `nonce` claim, then [nonce] must be provided
/// **to compare its hash** with the value in the ID token."* The comparison is
/// therefore `sha256(nonce_argument) == idToken.nonce`, performed server-side.
///
/// OIDC providers echo the requested nonce into the token **verbatim** — they do
/// not hash it. So the only representation that can satisfy the server is:
///
/// ```text
///   raw = random()
///   provider  <- sha256Hex(raw)      // request parameter
///   idToken.nonce == sha256Hex(raw)  // echoed back verbatim
///   Supabase  <- raw                 // server hashes it and compares
/// ```
///
/// This is exactly what Sign in with Apple has always done here, and why that
/// path works. Google needs the same SHAPE — but the two flows are NOT merged:
/// each provider keeps its own call sequence, because only the nonce
/// representation is common, not the handshake around it.
///
/// ## What went wrong
///
/// Google was being handed the RAW nonce, so the token came back carrying the
/// raw value; the raw value was then echoed straight back to Supabase, which
/// hashed it and compared `sha256(raw)` against `raw`. That can never match —
/// hence a deterministic "Nonce mismatch" on every iOS attempt.
library;

import 'apple_nonce.dart';

/// How a returned ID token's `nonce` claim relates to the attempt that asked
/// for it. Drives BOTH what we send to Supabase and what we refuse to send.
enum NonceMatch {
  /// The claim is exactly `sha256Hex(raw)`. The token provably belongs to this
  /// attempt, so Supabase gets the raw nonce and re-verifies it itself.
  hashOfRaw,

  /// The token carries no nonce claim. Supabase must then also be given no
  /// nonce — its supported nonce-less `signInWithIdToken` flow.
  absent,

  /// A claim exists but is not ours. The token cannot be shown to belong to
  /// this sign-in, so the attempt is refused rather than echoed back.
  unrelated,
}

/// Classify [tokenNonce] against the [rawNonce] this attempt generated.
NonceMatch classifyTokenNonce({required String rawNonce, String? tokenNonce}) {
  if (tokenNonce == null || tokenNonce.isEmpty) return NonceMatch.absent;
  if (tokenNonce == sha256OfString(rawNonce)) return NonceMatch.hashOfRaw;
  return NonceMatch.unrelated;
}

/// The value to hand Supabase's `signInWithIdToken(nonce:)`, or null when the
/// token carries no claim.
///
/// Throws [StateError] for [NonceMatch.unrelated]. Echoing an unverified claim
/// back would make the nonce check pass while proving nothing — precisely the
/// replay protection it exists to provide. Callers surface this as a clean
/// sign-in failure.
String? supabaseNonceFor({required String rawNonce, String? tokenNonce}) {
  switch (classifyTokenNonce(rawNonce: rawNonce, tokenNonce: tokenNonce)) {
    case NonceMatch.hashOfRaw:
      return rawNonce;
    case NonceMatch.absent:
      return null;
    case NonceMatch.unrelated:
      throw StateError(
        'ID token nonce does not belong to this sign-in attempt.',
      );
  }
}
