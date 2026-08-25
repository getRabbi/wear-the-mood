import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/auth/guest_session.dart';
import '../../core/auth/pending_auth_intent.dart';
import '../../core/auth/protected_action.dart';
import '../../core/platform/platform_capabilities.dart';
import '../../core/router/routes.dart';

/// Completes the guest → account conversion after a real session arrives.
///
/// Called from the app-level auth listener on `signedIn`, which is the only
/// place that sees every way a session can appear: Apple, Google, email
/// sign-in, email sign-up auto-login, and the OAuth deep-link return.
///
/// The order here is the contract:
///
///  1. **Verify a real session.** A guest flag is cleared only against a
///     genuine authenticated identity, never optimistically.
///  2. **Clear guest state**, so the gates stop denying and the network guard
///     stops rewriting reads onto the public mirrors.
///  3. **Take the intent — once.** [PendingAuthIntentController.take] reads and
///     clears atomically, so a rebuild, a second listener, or an auth event
///     that fires twice cannot resume the same thing twice. That single
///     property is what makes the resume idempotent: it cannot duplicate a
///     save, an entry, a credit or a job, because it cannot run twice.
///  4. **Navigate to the START of the intended flow.** Never to a submit.
///
/// For [ProtectedAction.tryOn] this lands on the first step of the
/// authenticated try-on flow. It does not select a photo, does not pre-accept
/// Consent v2, does not spend a credit and does not submit a generation — the
/// user re-expresses the intent inside the real flow, with the consent sheet in
/// its normal place before any photo is transmitted.
Future<void> resumePendingIntentAfterAuth(
  WidgetRef ref,
  GoRouter router,
) async {
  // (0) Off iOS this returns before touching anything at all — no storage read,
  // no provider initialised, no navigation. Guest state cannot exist on Android,
  // so there is never an intent to resume, and "never" should cost nothing:
  // Android's sign-in path must be byte-for-byte what it was.
  if (!ref.read(guestModeSupportedProvider)) return;

  // (1) A real session, or nothing happens.
  if (!ref.read(appSessionProvider).canPerformProtectedActions) return;

  // (2) The account wins over any lingering guest flag.
  await ref.read(guestSessionProvider.notifier).exitGuest();

  // (3) Exactly once.
  final intent = await ref.read(pendingAuthIntentProvider.notifier).take();
  if (intent == null) return;

  unawaited(
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.iosGuestAuthCompleted,
          properties: {'action': intent.action.analyticsName},
        ),
  );

  final destination = _resumeLocation(intent);
  if (destination == null) {
    // An intent we can no longer place (an id that went away, a route that no
    // longer exists). Drop it silently rather than dumping the user somewhere
    // arbitrary — they are signed in and on a working screen, which is the
    // important half.
    debugPrint('guest resume skipped: no destination for $intent');
    return;
  }

  unawaited(
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.iosGuestIntentResumed,
          properties: {'action': intent.action.analyticsName},
        ),
  );

  // (4) `go`, not `push`: the conversion sheet and any auth screen above it are
  // gone by now, and the destination should be the top of a clean stack rather
  // than a layer over a public screen the user has finished with.
  router.go(destination);
}

/// The route to resume at, with the public id reattached where the destination
/// needs one. Returns null when the intent cannot be honoured.
String? _resumeLocation(PendingAuthIntent intent) {
  final route = intent.action.resumeRoute;
  if (!intent.action.resumeNeedsResourceId) return route;

  final id = intent.resourceId;
  if (id == null || id.isEmpty) return null;
  final encoded = Uri.encodeQueryComponent(id);
  return switch (intent.action) {
    // Back to the product, where the user completes or reconfirms the save
    // themselves. Nothing is saved on their behalf.
    ProtectedAction.saveProduct => '${AppRoute.wtmProduct}?id=$encoded',
    // Back to the giveaway they were looking at, not into an entry.
    ProtectedAction.giveawayEntry =>
      '${AppRoute.wtmGiveawayDetail}?id=$encoded',
    _ => route,
  };
}
