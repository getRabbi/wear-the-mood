import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/features/auth/auth_error.dart';
import 'package:app/l10n/app_localizations.dart';

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('invalid credentials → friendly message (not the raw string)', () {
    final m = authErrorMessage(
      const AuthException('Invalid login credentials',
          code: 'invalid_credentials'),
      l10n,
    );
    expect(m, l10n.authErrorInvalidCredentials);
    expect(m, isNot(contains('Invalid login credentials')));
  });

  test('email not confirmed', () {
    expect(
      authErrorMessage(
        const AuthException('Email not confirmed', code: 'email_not_confirmed'),
        l10n,
      ),
      l10n.authErrorEmailNotConfirmed,
    );
  });

  test('already registered', () {
    expect(
      authErrorMessage(
        const AuthException('User already registered',
            code: 'user_already_exists'),
        l10n,
      ),
      l10n.authErrorEmailRegistered,
    );
  });

  test('weak password (typed exception)', () {
    expect(
      authErrorMessage(
        AuthWeakPasswordException(
          message: 'Password is too weak',
          statusCode: '422',
          reasons: const ['length'],
        ),
        l10n,
      ),
      l10n.authErrorWeakPassword,
    );
  });

  test('rate limited by 429 status', () {
    expect(
      authErrorMessage(
        const AuthException('Too many requests', statusCode: '429'),
        l10n,
      ),
      l10n.authErrorRateLimited,
    );
  });

  test('retryable fetch failure → network message', () {
    expect(
      authErrorMessage(AuthRetryableFetchException(message: 'x'), l10n),
      l10n.authErrorNetwork,
    );
  });

  test('any non-auth error → network message (never an empty/raw throw)', () {
    expect(authErrorMessage(Exception('SocketException'), l10n),
        l10n.authErrorNetwork);
    expect(authErrorMessage(null, l10n), l10n.authErrorNetwork);
  });

  test('unrecognized auth error falls back to the server message', () {
    expect(
      authErrorMessage(const AuthException('Some unusual server message'), l10n),
      'Some unusual server message',
    );
  });
}
