/// Nonce utilities for Sign in with Apple (Supabase `signInWithIdToken` flow).
///
/// Apple receives the SHA-256 of a one-shot random nonce; Supabase receives the
/// raw nonce and verifies it against the hash embedded in Apple's identity
/// token — binding the token to this exact sign-in attempt (replay protection).
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Unreserved URL-safe characters, matching Firebase/Supabase reference nonces.
const String appleNonceCharset =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

/// A cryptographically secure random nonce. [random] is injectable for tests
/// only — production callers use the default [Random.secure].
String generateAppleNonce({int length = 32, Random? random}) {
  final rng = random ?? Random.secure();
  return List.generate(
    length,
    (_) => appleNonceCharset[rng.nextInt(appleNonceCharset.length)],
  ).join();
}

/// Lowercase hex SHA-256, the digest form Apple expects for the nonce.
String sha256OfString(String input) =>
    sha256.convert(utf8.encode(input)).toString();
