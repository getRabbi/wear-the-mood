import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/auth/pending_auth_intent.dart';
import '../../core/auth/protected_action.dart';
import '../../core/platform/platform_capabilities.dart';
import '../../core/router/routes.dart';
import '../../features/auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// What the user chose in the sheet.
enum GuestConversionOutcome {
  /// Authenticated successfully. The caller resumes the pending intent.
  authenticated,

  /// Sent to the full auth screen; the outcome arrives later via the auth
  /// state listener, which resumes the intent.
  handedOff,

  /// "Not Now", a back gesture, or a tap outside. The user stays exactly where
  /// they were, on the same public screen, with nothing started.
  dismissed,
}

/// The ONE account-conversion sheet.
///
/// Every protected action a guest reaches shows this, with copy chosen by
/// [ProtectedAction]. One component rather than a sheet per feature, for the
/// same reason there is one `ensureAiConsent`: a per-screen copy of a gate is a
/// gate the next screen forgets, and forgetting here means a guest walks into a
/// flow that cannot work.
///
/// It is only ever raised by a deliberate user action. There are no timed
/// prompts, no "you have been browsing for a while" interstitials and no
/// repeat-on-every-scroll modals — the sheet appears when the person asks for
/// something that needs an account, and at no other moment.
///
/// Nothing about the underlying action starts before it returns
/// [GuestConversionOutcome.authenticated]: no photo picker, no permission
/// prompt, no consent sheet, no spinner, no request.
Future<GuestConversionOutcome> showGuestConversionSheet(
  BuildContext context,
  WidgetRef ref, {
  required ProtectedAction action,
  String? resourceId,
}) async {
  unawaited(
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.iosGuestAuthPromptViewed,
          properties: {'action': action.analyticsName},
        ),
  );

  // Record the intent BEFORE the sheet opens. If iOS backgrounds (or kills) the
  // app during a browser round trip, the intent is already on disk and the
  // resume still happens on relaunch.
  await ref
      .read(pendingAuthIntentProvider.notifier)
      .set(PendingAuthIntent(action: action, resourceId: resourceId));

  if (!context.mounted) return GuestConversionOutcome.dismissed;

  final outcome = await showModalBottomSheet<GuestConversionOutcome>(
    context: context,
    backgroundColor: WtmColors.panel,
    isScrollControlled: true,
    // Dismissible on purpose: guideline 5.1.1(v) is about not trapping people,
    // and a sheet you cannot close is a smaller version of the same trap.
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(WtmRadius.sheetTop),
      ),
    ),
    builder: (context) => _GuestConversionSheet(action: action),
  );

  final result = outcome ?? GuestConversionOutcome.dismissed;
  if (result == GuestConversionOutcome.dismissed) {
    // Dismissing is a decision, not a pause. Clearing here is what stops a
    // long-abandoned intent from firing days later after an unrelated sign-in.
    await ref.read(pendingAuthIntentProvider.notifier).clear();
    unawaited(
      ref
          .read(analyticsProvider)
          .track(
            AnalyticsEvents.iosGuestAuthDismissed,
            properties: {'action': action.analyticsName},
          ),
    );
  }
  return result;
}

class _GuestConversionSheet extends ConsumerStatefulWidget {
  const _GuestConversionSheet({required this.action});

  final ProtectedAction action;

  @override
  ConsumerState<_GuestConversionSheet> createState() =>
      _GuestConversionSheetState();
}

class _GuestConversionSheetState extends ConsumerState<_GuestConversionSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _apple() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    unawaited(
      ref
          .read(analyticsProvider)
          .track(
            AnalyticsEvents.iosGuestAuthStarted,
            properties: {
              'action': widget.action.analyticsName,
              'method': 'apple',
            },
          ),
    );
    var ok = false;
    try {
      ok = await ref.read(authControllerProvider.notifier).signInWithApple();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      // The auth-state listener clears guest state and resumes the intent; the
      // sheet just gets out of the way.
      Navigator.of(context).pop(GuestConversionOutcome.authenticated);
      return;
    }
    // A cancelled or failed sign-in leaves the guest exactly where they were,
    // with the sheet still open so they can try another route.
    setState(() {
      _busy = false;
      _error = AppLocalizations.of(context).wtmGuestAuthFailed;
    });
  }

  void _otherOptions() {
    if (_busy) return;
    // Captured BEFORE the pop. Reading an inherited widget off a context whose
    // route is being removed is how you get "looking up a deactivated widget's
    // ancestor" — rare, timing-dependent, and a crash when it happens.
    final router = GoRouter.of(context);
    Navigator.of(context).pop(GuestConversionOutcome.handedOff);
    // Pushed, not `go`: the public screen underneath survives, so cancelling
    // out of the auth screen returns to it rather than to a rebuilt Home.
    router.push(AppRoute.wtmAuth);
  }

  void _notNow() {
    if (_busy) return;
    Navigator.of(context).pop(GuestConversionOutcome.dismissed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final copy = guestConversionCopy(l10n, widget.action);
    // Sign in with Apple is offered only where it exists. Everywhere else the
    // sheet leads with the full options screen instead of a button that cannot
    // work.
    final apple =
        ref.watch(platformCapabilitiesProvider).platform == TargetPlatform.iOS;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          WtmSpace.screenH,
          WtmSpace.s18,
          WtmSpace.screenH,
          WtmSpace.s18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: TheOrb(size: 52)),
            const SizedBox(height: WtmSpace.s14),
            Text(
              copy.title,
              textAlign: TextAlign.center,
              style: WtmType.h1.copyWith(fontSize: 21),
            ),
            const SizedBox(height: WtmSpace.s8),
            Text(copy.body, textAlign: TextAlign.center, style: WtmType.sub),
            if (_error != null) ...[
              const SizedBox(height: WtmSpace.s10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: WtmType.micro.copyWith(color: WtmColors.danger),
              ),
            ],
            const SizedBox(height: WtmSpace.s18),
            if (apple)
              GradientCta(
                label: l10n.wtmGuestContinueApple,
                onPressed: _busy ? null : _apple,
              )
            else
              GradientCta(
                label: l10n.wtmWelcomeCreate,
                onPressed: _busy ? null : _otherOptions,
              ),
            const SizedBox(height: WtmSpace.s10),
            GhostButton(
              label: l10n.wtmGuestOtherOptions,
              onPressed: _busy ? null : _otherOptions,
            ),
            const SizedBox(height: WtmSpace.s6),
            Semantics(
              button: true,
              enabled: !_busy,
              label: l10n.wtmGuestNotNow,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy ? null : _notNow,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.center,
                    child: Text(
                      l10n.wtmGuestNotNow,
                      style: WtmType.micro.copyWith(color: WtmColors.muted),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Title + body for a protected action. Separate from the widget so the copy
/// mapping is unit-testable without pumping a sheet.
({String title, String body}) guestConversionCopy(
  AppLocalizations l10n,
  ProtectedAction action,
) => switch (action) {
  ProtectedAction.tryOn => (
    title: l10n.wtmGuestTryOnTitle,
    body: l10n.wtmGuestTryOnBody,
  ),
  ProtectedAction.closet || ProtectedAction.bodyPhoto => (
    title: l10n.wtmGuestClosetTitle,
    body: l10n.wtmGuestClosetBody,
  ),
  ProtectedAction.saveProduct => (
    title: l10n.wtmGuestSaveTitle,
    body: l10n.wtmGuestSaveBody,
  ),
  ProtectedAction.saveLook => (
    title: l10n.wtmGuestLookTitle,
    body: l10n.wtmGuestLookBody,
  ),
  ProtectedAction.community => (
    title: l10n.wtmGuestCommunityTitle,
    body: l10n.wtmGuestCommunityBody,
  ),
  ProtectedAction.giveawayEntry || ProtectedAction.giveawayManage => (
    title: l10n.wtmGuestGiveawayTitle,
    body: l10n.wtmGuestGiveawayBody,
  ),
  ProtectedAction.stylist => (
    title: l10n.wtmGuestStylistTitle,
    body: l10n.wtmGuestStylistBody,
  ),
  ProtectedAction.purchase => (
    title: l10n.wtmGuestPurchaseTitle,
    body: l10n.wtmGuestPurchaseBody,
  ),
  ProtectedAction.history ||
  ProtectedAction.notifications ||
  ProtectedAction.accountSettings ||
  ProtectedAction.profile => (
    title: l10n.wtmGuestAccountTitle,
    body: l10n.wtmGuestAccountBody,
  ),
};
