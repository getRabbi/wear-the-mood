import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Outcome of the native Play Install Referrer lookup (§24).
class InstallReferrerResult {
  const InstallReferrerResult({required this.status, this.token, this.referrer});

  /// ok | notSupported | unavailable | timeout | error
  final String status;
  final String? token;
  final String? referrer;

  bool get hasToken => (token ?? '').isNotEmpty;
}

/// Extract ONLY `referral_token` from a Play referrer query string; unrelated
/// UTM/organic values are ignored, and a malformed/empty string yields null.
/// Kept in Dart so it is unit-testable independently of the platform channel.
String? parseReferralToken(String? referrer) {
  if (referrer == null || referrer.isEmpty) return null;
  try {
    final token = Uri.splitQueryString(referrer)['referral_token'];
    return (token != null && token.isNotEmpty) ? token : null;
  } catch (_) {
    return null;
  }
}

/// Thin wrapper over the native `wtm/install_referrer` MethodChannel (the Google
/// Play Install Referrer Client Library). Deferred install attribution only — a
/// direct APK/ADB install has no Play referrer and returns without a token, so
/// referral credit is simply not attributed (organic).
class InstallReferrerChannel {
  const InstallReferrerChannel();

  static const _channel = MethodChannel('wtm/install_referrer');

  Future<InstallReferrerResult> getReferrer() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getReferrer');
      if (res == null) return const InstallReferrerResult(status: 'error');
      final referrer = res['referrer'] as String?;
      final token =
          (res['referralToken'] as String?) ?? parseReferralToken(referrer);
      return InstallReferrerResult(
        status: res['status'] as String? ?? 'error',
        token: token,
        referrer: referrer,
      );
    } on MissingPluginException {
      return const InstallReferrerResult(status: 'notSupported');
    } on PlatformException {
      return const InstallReferrerResult(status: 'error');
    }
  }
}

final installReferrerChannelProvider = Provider<InstallReferrerChannel>(
  (ref) => const InstallReferrerChannel(),
);
