import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../data/models/monetization.dart';
import '../../data/repositories/monetization_repository.dart';

/// The ONE place that decides whether WTM may raise a monetization surface, and
/// the one place that records that it did (RETENTION spec §10).
///
/// Why this exists at all: before it, every screen that wanted to sell
/// something would have had to keep its own timestamp, and no screen could see
/// anybody else's. That is exactly how an app ends up showing a user three
/// paywalls in an afternoon while each individual screen believes it showed
/// one. The cooldown is computed server-side from a single ledger, so the rules
/// hold across screens, sessions and devices.
///
/// **The distinction that matters:** a surface the USER opened — tapping
/// Upgrade, tapping a locked feature, running out mid-action — is never gated
/// and never starts a cooldown. Only surfaces WTM decides to raise on its own
/// go through [mayInterrupt]. Blocking a user from a paywall they asked for
/// would be absurd; letting a screen nag them because they once tapped Upgrade
/// would be worse.
class MonetizationGate {
  MonetizationGate(this._ref);

  final Ref _ref;

  /// May WTM raise an INTERRUPTIVE monetization surface right now?
  ///
  /// Fails OPEN on error, and that is deliberate: the consequence of a wrong
  /// `true` here is one paywall the user can close, while the consequence of a
  /// wrong `false` is a user who can never be told they have run out. Neither
  /// is good; only one of them is recoverable by the user.
  Future<bool> mayInterrupt() async {
    try {
      final config = await _ref
          .read(monetizationRepositoryProvider)
          .getConfig();
      return config.paywall.mayInterrupt;
    } catch (_) {
      return true;
    }
  }

  /// Every record path funnels through here, and every one of them is
  /// swallowed on failure.
  ///
  /// This is not defensive clutter, it is the rule: **the pressure ledger is
  /// for us, not for the user.** A paywall that fails to open, or a purchase
  /// confirmation that fails to appear, because a bookkeeping row could not be
  /// written would be a self-inflicted outage on the one screen where a failure
  /// costs money. The catch is deliberately broad — it also covers the case
  /// where the HTTP client itself cannot be constructed (no session yet, a
  /// widget test with no Supabase), which is a throw rather than a rejected
  /// future and would otherwise escape as an unhandled async error.
  Future<void> _record(
    MonetizationSurface surface,
    MonetizationAction action, {
    bool interruptive = false,
    Map<String, String>? context,
    String? event,
  }) async {
    try {
      await _ref
          .read(monetizationRepositoryProvider)
          .recordEvent(
            surface: surface,
            action: action,
            interruptive: interruptive,
            context: context,
          );
      if (event != null) {
        await _ref
            .read(analyticsProvider)
            .track(
              event,
              properties: {
                'surface': surface.wire,
                'interruptive': interruptive,
              },
            );
      }
    } catch (_) {
      // Intentionally silent.
    }
  }

  /// Record that a surface was shown. Pass `interruptive: true` ONLY when WTM
  /// raised it — never for a paywall the user opened themselves.
  Future<void> recordViewed(
    MonetizationSurface surface, {
    bool interruptive = false,
  }) => _record(
    surface,
    MonetizationAction.viewed,
    interruptive: interruptive,
    event: AnalyticsEvents.paywallViewed,
  );

  /// Record a dismissal. A dismissal of an interruptive surface starts the
  /// cooldown: dismissing is an answer, and asking again an hour later is not
  /// asking, it is nagging.
  Future<void> recordDismissed(
    MonetizationSurface surface, {
    bool interruptive = false,
  }) => _record(
    surface,
    MonetizationAction.dismissed,
    interruptive: interruptive,
    event: AnalyticsEvents.paywallDismissed,
  );

  Future<void> recordCta(MonetizationSurface surface) => _record(
    surface,
    MonetizationAction.ctaTapped,
    event: AnalyticsEvents.paywallCtaTapped,
  );

  /// Record a completed purchase. This is what buys the user their quiet
  /// period — somebody who just paid must not immediately be asked to pay
  /// again (§10).
  Future<void> recordPurchased(
    MonetizationSurface surface, {
    String? productId,
  }) async {
    await _record(
      surface,
      MonetizationAction.purchased,
      context: {'product_id': ?productId},
    );
    // The config carries the cooldown that just started, so anything still
    // holding the old snapshot would believe the user is still interruptible.
    try {
      _ref.invalidate(monetizationConfigProvider);
    } catch (_) {
      // The provider was never built; there is nothing stale to invalidate.
    }
  }
}

final monetizationGateProvider = Provider<MonetizationGate>((ref) {
  return MonetizationGate(ref);
});
