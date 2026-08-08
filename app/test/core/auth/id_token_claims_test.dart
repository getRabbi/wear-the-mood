/// Reading claims out of an ID token.
///
/// SCOPE NOTE. This file covers the PARSER only. It deliberately makes no claim
/// about what should be sent to Supabase — an earlier version of this file did,
/// and it was wrong: it concluded that because the token carries a nonce, the
/// claim is what Supabase wants back. gotrue 2.21.0 documents the opposite (the
/// server hashes the argument and compares it to the claim), so echoing the
/// claim guaranteed the "Nonce mismatch" it was meant to fix.
///
/// The handshake itself is specified and tested in `oidc_nonce_test.dart`.
/// `nonceClaimOf` survives because classification and diagnostics still need to
/// READ the claim — never to decide what to send.
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

    test('reports a claim that differs from what we requested', () {
      // The parser reports what is THERE. Deciding that such a token cannot be
      // trusted is `classifyTokenNonce`'s job, not this function's.
      const requested = 'the-nonce-we-asked-for';
      const inToken = 'a-nonce-from-somewhere-else';
      final nonce = nonceClaimOf(_jwt({'nonce': inToken}));
      expect(nonce, inToken);
      expect(nonce, isNot(requested));
    });

    test('returns null when the token carries no nonce', () {
      // Absence matters: it selects GoTrue's supported nonce-less flow, where
      // both sides send nothing.
      expect(nonceClaimOf(_jwt({'sub': 'u1', 'aud': 'client'})), isNull);
    });

    test('treats an empty nonce as absent', () {
      // An empty claim must normalise to null so both sides agree on absence.
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
      expect(
        nonceClaimOf(
          _jwt({
            'nonce': ['a'],
          }),
        ),
        isNull,
      );
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
      final token =
          '${seg({'alg': 'RS256', 'nonce': 'from-header'})}'
          '.${seg({'sub': 'u1'})}.sig';
      expect(nonceClaimOf(token), isNull);
    });
  });
}
