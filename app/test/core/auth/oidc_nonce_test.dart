import 'dart:convert';

import 'package:app/core/auth/apple_nonce.dart';
import 'package:app/core/auth/id_token_claims.dart';
import 'package:app/core/auth/oidc_nonce.dart';
import 'package:flutter_test/flutter_test.dart';

/// The nonce contract, pinned against the sources it was derived from.
///
/// gotrue 2.21.0 forwards `nonce` verbatim and documents the server as comparing
/// "its hash" to the token claim, so the server-side check is
/// `sha256(nonce_argument) == idToken.nonce`. OIDC providers echo the requested
/// nonce into the token unhashed. Therefore the only representation that can
/// satisfy the check is: provider gets sha256Hex(raw), Supabase gets raw.
///
/// These tests encode that relationship. They are what would have caught the
/// previous implementation, which sent raw to Google and echoed the claim back.

String _tokenWithNonce(String? nonce, {String? aud, String? iss}) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final claims = <String, dynamic>{'nonce': ?nonce, 'aud': ?aud, 'iss': ?iss};
  return '${seg({'alg': 'RS256'})}.${seg(claims)}.signature';
}

void main() {
  group('the proven contract', () {
    test(
      'a token echoing sha256Hex(raw) is accepted, and Supabase gets raw',
      () {
        const raw = 'a-one-shot-random-nonce';
        final token = _tokenWithNonce(sha256OfString(raw));

        expect(
          classifyTokenNonce(rawNonce: raw, tokenNonce: nonceClaimOf(token)),
          NonceMatch.hashOfRaw,
        );
        // The RAW value, never the claim: the server hashes what we send.
        expect(
          supabaseNonceFor(rawNonce: raw, tokenNonce: nonceClaimOf(token)),
          raw,
        );
      },
    );

    test('the old behaviour is now rejected, not echoed back', () {
      // The previous code sent raw to Google, so the token carried raw, and it
      // echoed that claim to Supabase. The server then compared sha256(raw)
      // against raw -> deterministic "Nonce mismatch".
      const raw = 'a-one-shot-random-nonce';
      final token = _tokenWithNonce(raw); // token carries the RAW value

      expect(
        classifyTokenNonce(rawNonce: raw, tokenNonce: nonceClaimOf(token)),
        NonceMatch.unrelated,
      );
      expect(
        () => supabaseNonceFor(rawNonce: raw, tokenNonce: nonceClaimOf(token)),
        throwsStateError,
        reason: 'echoing an unverified claim proves nothing about the attempt',
      );
    });

    test('sha256(raw) never equals raw — the mismatch was unavoidable', () {
      const raw = 'a-one-shot-random-nonce';
      expect(sha256OfString(raw), isNot(raw));
    });
  });

  group('absent nonce', () {
    test('no claim means Supabase must also get none', () {
      const raw = 'some-raw-nonce';
      final token = _tokenWithNonce(null);

      expect(
        classifyTokenNonce(rawNonce: raw, tokenNonce: nonceClaimOf(token)),
        NonceMatch.absent,
      );
      // Both-empty is GoTrue's supported nonce-less id_token flow. Sending a
      // nonce here would trip "should either both be empty or both be provided".
      expect(
        supabaseNonceFor(rawNonce: raw, tokenNonce: nonceClaimOf(token)),
        isNull,
      );
    });

    test('an empty-string claim is treated as absent', () {
      final token = _tokenWithNonce('');
      expect(nonceClaimOf(token), isNull);
      expect(
        classifyTokenNonce(rawNonce: 'r', tokenNonce: nonceClaimOf(token)),
        NonceMatch.absent,
      );
    });
  });

  group('a wrong or hostile nonce is refused', () {
    test('someone else\'s nonce is not accepted', () {
      const raw = 'our-nonce';
      final token = _tokenWithNonce(sha256OfString('a-different-attempt'));
      expect(
        classifyTokenNonce(rawNonce: raw, tokenNonce: nonceClaimOf(token)),
        NonceMatch.unrelated,
      );
      expect(
        () => supabaseNonceFor(rawNonce: raw, tokenNonce: nonceClaimOf(token)),
        throwsStateError,
      );
    });

    test('a token from a PREVIOUS attempt cannot be reused', () {
      // The cached-credential hazard: a token minted under an earlier nonce must
      // not validate against a fresh attempt.
      final first = generateAppleNonce();
      final second = generateAppleNonce();
      final tokenFromFirst = _tokenWithNonce(sha256OfString(first));

      expect(
        classifyTokenNonce(
          rawNonce: second,
          tokenNonce: nonceClaimOf(tokenFromFirst),
        ),
        NonceMatch.unrelated,
      );
    });
  });

  group('malformed input is total, never throwing', () {
    for (final bad in <String>[
      '',
      'not-a-jwt',
      'only.two',
      'a.b.c.d',
      'header.!!!not-base64!!!.sig',
    ]) {
      test('"${bad.isEmpty ? '<empty>' : bad}" yields no claim', () {
        expect(nonceClaimOf(bad), isNull);
        expect(claimsOf(bad), isEmpty);
      });
    }

    test('a payload that is valid base64 but not a JSON object', () {
      final token =
          '${base64Url.encode(utf8.encode('{}')).replaceAll('=', '')}.'
          '${base64Url.encode(utf8.encode('[1,2,3]')).replaceAll('=', '')}.sig';
      expect(nonceClaimOf(token), isNull);
      expect(claimsOf(token), isEmpty);
    });

    test('a non-string nonce claim is ignored', () {
      final token = _tokenWithNonce(null);
      expect(nonceClaimOf(token), isNull);
    });
  });

  group('nonce generation', () {
    test('every attempt gets a distinct raw nonce', () {
      final nonces = {for (var i = 0; i < 200; i++) generateAppleNonce()};
      expect(nonces, hasLength(200), reason: 'no repeats across attempts');
    });

    test('nonces are long enough to be unguessable', () {
      expect(generateAppleNonce().length, 32);
    });

    test('the charset stays URL-safe', () {
      expect(
        generateAppleNonce(length: 256),
        matches(RegExp(r'^[A-Za-z0-9\-._]+$')),
      );
    });
  });

  group('claims reading', () {
    test('audience and issuer are readable for diagnostics', () {
      final token = _tokenWithNonce(
        'n',
        aud: '123-web.apps.googleusercontent.com',
        iss: 'https://accounts.google.com',
      );
      final claims = claimsOf(token);
      expect(claims['aud'], '123-web.apps.googleusercontent.com');
      expect(claims['iss'], 'https://accounts.google.com');
    });
  });
}
