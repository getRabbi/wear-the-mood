/// Regression cover for the Google sign-in nonce handshake (2026-07-31).
///
/// On a real iPhone, Supabase rejected the Google ID token twice for opposite
/// reasons: "Passed nonce and nonce in id_token should either both exist or
/// not" when we sent no nonce, then "Nonce mismatch" when we sent our own. The
/// token always carried a nonce and it was never the one we requested, so the
/// only value that can be correct is the one already inside the token.
library;

import 'dart:convert';

import 'package:app/core/auth/id_token_claims.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a structurally real JWT: base64url, UNPADDED, as providers send it.
String _jwt(Object? claims) {
  String seg(Object? value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${seg({'alg': 'RS256', 'typ': 'JWT'})}.${seg(claims)}.notasignature';
}

void main() {
  group('nonceClaimOf', () {
    test('returns the nonce the token actually carries', () {
      expect(nonceClaimOf(_jwt({'nonce': 'abc123', 'sub': 'u1'})), 'abc123');
    });

    test('returns the token nonce even when it is NOT the one we requested', () {
      // The exact production failure: our requested nonce is irrelevant: what
      // Supabase compares against is the claim, so the claim is what we send.
      const requested = 'the-nonce-we-asked-for';
      const inToken = 'the-nonce-the-sdk-used';
      final nonce = nonceClaimOf(_jwt({'nonce': inToken}));
      expect(nonce, inToken);
      expect(nonce, isNot(requested));
    });

    test('returns null when the token carries no nonce', () {
      // Passing null makes gotrue send JSON null, which reads as absent, so
      // "both exist or not" is satisfied by both sides being absent.
      expect(nonceClaimOf(_jwt({'sub': 'u1', 'aud': 'client'})), isNull);
    });

    test('treats an empty nonce as absent', () {
      // GoTrue compares against "", so an empty claim must normalise to null
      // rather than being echoed back as a present-but-empty value.
      expect(nonceClaimOf(_jwt({'nonce': ''})), isNull);
    });

    test('decodes an unpadded base64url payload', () {
      // Real tokens strip '='. Verify against a payload whose length forces
      // padding when encoded normally.
      final token = _jwt({'nonce': 'x'});
      expect(token.split('.')[1], isNot(contains('=')));
      expect(nonceClaimOf(token), 'x');
    });

    test('decodes a payload containing multi-byte UTF-8', () {
      expect(nonceClaimOf(_jwt({'name': 'রাব্বি', 'nonce': 'ok'})), 'ok');
    });

    test('ignores a non-string nonce', () {
      expect(nonceClaimOf(_jwt({'nonce': 12345})), isNull);
      expect(nonceClaimOf(_jwt({'nonce': ['a']})), isNull);
      expect(nonceClaimOf(_jwt({'nonce': null})), isNull);
    });

    group('never throws on malformed input', () {
      // A sign-in must not crash because a provider sent an unexpected shape.
      test('wrong segment count', () {
        expect(nonceClaimOf(''), isNull);
        expect(nonceClaimOf('onlyonesegment'), isNull);
        expect(nonceClaimOf('two.segments'), isNull);
        expect(nonceClaimOf('a.b.c.d'), isNull);
      });

      test('payload is not valid base64url', () {
        expect(nonceClaimOf('header.!!!not-base64!!!.sig'), isNull);
      });

      test('payload is not JSON', () {
        final garbage = base64Url.encode(utf8.encode('plain text'));
        expect(nonceClaimOf('header.$garbage.sig'), isNull);
      });

      test('payload is JSON but not an object', () {
        expect(nonceClaimOf(_jwt(['a', 'b'])), isNull);
        expect(nonceClaimOf(_jwt('a string')), isNull);
        expect(nonceClaimOf(_jwt(42)), isNull);
      });

      test('payload is not valid UTF-8', () {
        final bad = base64Url.encode([0xC3, 0x28, 0xA0]);
        expect(nonceClaimOf('header.$bad.sig'), isNull);
      });
    });

    test('does not confuse a nonce in the header with one in the payload', () {
      // Only the payload is read. A header-only nonce must not be picked up.
      String seg(Object? v) =>
          base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
      final token = '${seg({'alg': 'RS256', 'nonce': 'from-header'})}'
          '.${seg({'sub': 'u1'})}.sig';
      expect(nonceClaimOf(token), isNull);
    });
  });
}
