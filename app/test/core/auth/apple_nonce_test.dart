import 'dart:math';

import 'package:app/core/auth/apple_nonce.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateAppleNonce', () {
    test('has the requested length and stays inside the charset', () {
      final nonce = generateAppleNonce();
      expect(nonce.length, 32);
      for (final char in nonce.split('')) {
        expect(
          appleNonceCharset.contains(char),
          isTrue,
          reason: '"$char" is outside the nonce charset',
        );
      }
    });

    test('two nonces differ (one-shot replay protection)', () {
      expect(generateAppleNonce(), isNot(generateAppleNonce()));
    });

    test('is deterministic under an injected Random (test seam)', () {
      expect(
        generateAppleNonce(random: Random(7)),
        generateAppleNonce(random: Random(7)),
      );
    });
  });

  group('sha256OfString', () {
    test('matches the known SHA-256 test vector', () {
      // FIPS 180-2 test vector for "abc".
      expect(
        sha256OfString('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('is lowercase hex of 64 chars (the form Apple verifies)', () {
      final digest = sha256OfString(generateAppleNonce());
      expect(digest.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(digest), isTrue);
    });
  });
}
