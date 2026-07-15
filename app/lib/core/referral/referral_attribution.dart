import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/referral_rewards_repository.dart';
import '../auth/auth_providers.dart';
import 'app_link_channel.dart';
import 'install_id.dart';
import 'install_referrer_channel.dart';

/// The last claim outcome, surfaced to the UI for the referred user's subtle
/// confirmation ("Referral applied successfully."). The referred user never
/// receives credits in this version, so this never implies a personal reward.
class ReferralClaimState {
  const ReferralClaimState({this.lastStatus});

  final String? lastStatus;

  bool get applied => lastStatus == 'awarded';
  bool get notEligible => lastStatus == 'not_eligible_existing_user';
}

/// Orchestrates referral attribution + the claim across the app lifecycle (§24):
///   * capture the deferred install referrer ONCE per installation,
///   * capture cold/warm App Links → mint a token via the backend,
///   * hold the pending token in secure storage (it belongs to the INSTALL, not
///     any signed-in account),
///   * claim it for the authenticated user with bounded, lifecycle-aware retry.
/// The backend is the sole authority; this never grants credits locally.
class ReferralAttribution extends Notifier<ReferralClaimState> {
  static const _pendingKey = 'wtm.referral.pending_token';
  static const _installCheckedKey = 'wtm.referral.install_checked';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _claiming = false;
  bool _bootstrapped = false;
  StreamSubscription<String>? _linkSub;

  @override
  ReferralClaimState build() => const ReferralClaimState();

  /// Once per app process: subscribe to warm App Links, handle the cold-start
  /// App Link, and capture the deferred install referrer (first launch only).
  /// Fire-and-forget — never blocks the visible app or a normal organic launch.
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    try {
      _linkSub ??= ref.read(appLinkChannelProvider).codes.listen(
        (code) => unawaited(_captureAppLinkCode(code)),
      );
      final initial = await ref.read(appLinkChannelProvider).initialCode();
      if (initial != null) await _captureAppLinkCode(initial);
      await _captureInstallReferrerOnce();
      await tryClaim();
    } catch (_) {
      // Attribution is best-effort — it must never break app startup.
    }
  }

  Future<void> _captureInstallReferrerOnce() async {
    if (await _storage.read(key: _installCheckedKey) == 'true') return;
    final result = await ref.read(installReferrerChannelProvider).getReferrer();
    // Only burn the one-shot on a DEFINITIVE answer; a transient service failure
    // (unavailable/timeout/error) is retried on a later bootstrap.
    if (result.status == 'ok' || result.status == 'notSupported') {
      await _storage.write(key: _installCheckedKey, value: 'true');
    }
    if (result.hasToken) await _setPending(result.token!);
  }

  Future<void> _captureAppLinkCode(String code) async {
    if (await pendingToken() != null) return; // keep the first pending token
    try {
      final token = await ref.read(referralRewardsRepositoryProvider).click(code);
      await _setPending(token);
      await tryClaim();
    } catch (_) {
      // Invalid/expired code or offline — nothing pending, no harm.
    }
  }

  /// Manually enter an invite CODE (iOS post-App-Store fallback, or any
  /// platform). Resolves it to an opaque token via the backend, stores it, and
  /// claims if already authenticated. Returns true if the code was accepted
  /// (a token was minted), false if invalid/expired/offline. The user's explicit
  /// action is required — the clipboard is never read automatically (§10).
  Future<bool> submitInviteCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    try {
      final token = await ref
          .read(referralRewardsRepositoryProvider)
          .click(normalized);
      await _setPending(token);
      await tryClaim();
      return true;
    } catch (_) {
      return false; // invalid / expired code, or offline
    }
  }

  Future<String?> pendingToken() => _storage.read(key: _pendingKey);
  Future<void> _setPending(String t) => _storage.write(key: _pendingKey, value: t);
  Future<void> _clearPending() => _storage.delete(key: _pendingKey);

  /// Claim the pending token for the currently authenticated user. One attempt
  /// per call, re-entrancy guarded (never fires on every rebuild). A DEFINITIVE
  /// result clears the token; a transient failure keeps it for the next
  /// lifecycle event (bootstrap / resume / after sign-in). No-op with no token
  /// or no session — referral failure never blocks auth or normal use.
  Future<void> tryClaim() async {
    if (_claiming) return;
    if (!ref.read(isAuthenticatedProvider)) return;
    _claiming = true;
    try {
      final token = await pendingToken();
      if (token == null) return;
      final installId = await ref.read(installIdStoreProvider).getOrCreate();
      final result = await ref
          .read(referralRewardsRepositoryProvider)
          .claim(token: token, installId: installId);
      // Definitive server outcome → never retry this token.
      await _clearPending();
      state = ReferralClaimState(lastStatus: result.status);
      // The referrer's total changed server-side; refresh local credit state so
      // any watching screen reflects it (no-op for the referred user's own total).
      ref.invalidate(creditsProvider);
    } catch (_) {
      // Transient (offline / timeout) — keep the token for a later attempt.
    } finally {
      _claiming = false;
    }
  }

  /// Clear the one-time confirmation once the UI has shown it.
  void acknowledge() => state = const ReferralClaimState();
}

final referralAttributionProvider =
    NotifierProvider<ReferralAttribution, ReferralClaimState>(
      ReferralAttribution.new,
    );
