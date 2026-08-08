import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_localizations.dart';

/// Maps any auth failure to a clear, friendly, localized message (CLAUDE.md §13).
///
/// Prefers Supabase's structured [AuthException.code] (with a message fallback
/// for older servers), and treats anything non-auth (no connection, timeout) as
/// a network problem. Never returns an empty string — the UI always has
/// something honest to show instead of a raw exception or a silent failure.
String authErrorMessage(Object? error, AppLocalizations l10n) {
  // Retryable fetch failures are gotrue's "couldn't reach the server".
  if (error is AuthRetryableFetchException) return l10n.authErrorNetwork;
  if (error is AuthWeakPasswordException) return l10n.authErrorWeakPassword;

  if (error is AuthException) {
    final code = error.code?.toLowerCase() ?? '';
    final msg = error.message.toLowerCase();
    bool any(List<String> needles) =>
        needles.any((n) => code.contains(n) || msg.contains(n));

    if (any(['email_not_confirmed', 'not confirmed', 'email not confirmed'])) {
      return l10n.authErrorEmailNotConfirmed;
    }
    if (any(['invalid_credentials', 'invalid login', 'invalid_grant'])) {
      return l10n.authErrorInvalidCredentials;
    }
    if (any([
      'user_already_exists',
      'email_exists',
      'already registered',
      'already been registered',
    ])) {
      return l10n.authErrorEmailRegistered;
    }
    if (any(['weak_password', 'should be at least', 'at least 6 char'])) {
      return l10n.authErrorWeakPassword;
    }
    if (any([
          'over_email_send_rate_limit',
          'over_request_rate_limit',
          'rate limit',
        ]) ||
        error.statusCode == '429') {
      return l10n.authErrorRateLimited;
    }
    if (any(['user_not_found'])) {
      return l10n.authErrorInvalidCredentials;
    }
    if (any(['signup_disabled', 'signups not allowed', 'signups_disabled'])) {
      return l10n.authErrorSignupDisabled;
    }
    // A known auth error we didn't special-case: prefer the server's own
    // (human-readable) message, never an empty string.
    return error.message.isNotEmpty ? error.message : l10n.authGenericError;
  }

  // Only genuine transport failures are a "network" problem. Everything else —
  // notably `GoogleSignInException`, which is what a Google/OAuth configuration
  // fault throws — used to land here too, so a config error was reported to the
  // user (and to us) as "check your connection". That cost a whole debugging
  // session on a phone that demonstrably had network.
  if (error is SocketException ||
      error is TimeoutException ||
      error is HandshakeException ||
      (error is DioException && _isTransport(error))) {
    return l10n.authErrorNetwork;
  }
  return l10n.authGenericError;
}

/// True only for Dio failures that really are transport-level.
bool _isTransport(DioException error) => switch (error.type) {
  DioExceptionType.connectionError ||
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout => true,
  _ => false,
};
